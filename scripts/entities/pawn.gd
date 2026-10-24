# ----------------------------------------------------------------
# Pawn
#     A citizen. Tracks needs, walks the nav grid and runs Tasks handed
#     out by the JobManager.
# ----------------------------------------------------------------
class_name Pawn extends Node3D;

const WALK_SPEED        :float = 3.0;      # metres per real second at 1x
const ROAD_SPEED_MULT   :float = 1.5;
const COLD_DAMAGE_BELOW:float = 0.2;      # warmth under this starts hurting health, more the lower it gets
const CARRY_CAP         :int = 6;
const HUNGER_HOURS      :float = 30.0;     # full -> empty
const THIRST_HOURS      :float = 20.0;
const ENERGY_HOURS      :float = 20.0;
const SLEEP_RESTORE     :float = 1.0 / 7.0;
const FAIL_COOLDOWN     :float = 6.0;      # hours before retrying a failed target
const NON_WORK_KINDS    :Array[StringName] = [&"sleep", &"eat", &"drink", &"warm", &"idle"];   # tools don't speed these up or wear
const NIGHT_EXEMPT      :Array[StringName] = [&"sleep", &"eat", &"drink", &"warm", &"deliver", &"haul"];

const MALE_NAMES        :Array[String] = ["Aldric", "Bram", "Cedric", "Dunstan", "Edwin", "Godric", "Hal", "Osric", "Rowan", "Wystan", "Alden", "Tobin"];
const FEMALE_NAMES      :Array[String] = ["Aelwen", "Bryony", "Cerys", "Edith", "Elfreda", "Hilda", "Isolde", "Maud", "Rowena", "Wren", "Tamsin", "Agnes"];

var look_seed   :int = 0;       # seeds the cosmetic randomness (shirt, skin) so a loaded citizen looks the same
var first_name  :String;
var is_male     :bool;
var age         :int;
var profession  :int = JobManager.Profession.LABORER;
var home        :Building = null;

# needs, 0..1 (1 = fully satisfied)
var hunger      :float = 1.0;
var thirst      :float = 1.0;
var energy      :float = 1.0;
var warmth      :float = 1.0;
var health      :float = 1.0;
var indoors     :bool = false;
var shelter     :Building = null;   # the building we are inside
var sleeping    :bool = false;

var carry_item  :StringName = &"";
var carry_amount:int = 0;

var tool        :StringName = &"";      # equipped tool item, or &"" for none
var tool_uses   :float = 0.0;           # game hours of work left in it

var task        :Task = null;
var status      :String = "Idle";
var removed     :bool = false;
var world       :World;

var _path           :Array[Vector2i] = [];
var _path_i         :int = 0;
var _failed         :Dictionary = {};       # target -> game hour it can be retried
var _need_block_until:float = -1.0;
var _carry_mesh     :MeshInstance3D;
var _carry_mat      :StandardMaterial3D;

func setup(w:World, cell:Vector2i, rng:RandomNumberGenerator, taken_names:Array[String] = []) -> void:
    world = w;
    is_male = rng.randf() < 0.5;
    var names:Array[String] = [];
    for n in (MALE_NAMES if is_male else FEMALE_NAMES):
        if not taken_names.has(n):
            names.append(n);
    if names.is_empty():
        names = MALE_NAMES if is_male else FEMALE_NAMES;
    first_name = names[rng.randi() % names.size()];
    age = rng.randi_range(18, 40);
    position = w.terrain.cell_center(cell);
    name = "Pawn_%s" % first_name;
    look_seed = rng.randi();
    _build_look();

# Builds the body from look_seed.
func _build_look() -> void:
    var look:RandomNumberGenerator = RandomNumberGenerator.new();
    look.seed = look_seed;
    _build_visual(look);

func to_dict() -> Dictionary:
    return {
        "name": first_name, "is_male": is_male, "age": age, "profession": profession, "look_seed": look_seed,
        "hunger": hunger, "thirst": thirst, "energy": energy, "warmth": warmth, "health": health,
        "carry_item": carry_item, "carry_amount": carry_amount, "tool": tool, "tool_uses": tool_uses,
        "position": position, "home": world.buildings.find(home) if home != null else -1,
    };

@warning_ignore("integer_division")
# Rebuilds a saved citizen. The task is not saved: it starts idle and picks something new. A citizen who was
# indoors is put on the nearest walkable cell.
func restore(w:World, d:Dictionary) -> void:
    world = w;
    first_name = d["name"];
    is_male = d["is_male"];
    age = d["age"];
    profession = d["profession"];
    look_seed = d["look_seed"];
    hunger = d["hunger"];
    thirst = d["thirst"];
    energy = d["energy"];
    warmth = d["warmth"];
    health = d["health"];
    carry_item = d["carry_item"];
    carry_amount = d["carry_amount"];
    tool = d["tool"];
    tool_uses = d["tool_uses"];
    name = "Pawn_%s" % first_name;
    _build_look();
    var c:Vector2i = w.nav.nearest_walkable(w.terrain.world_to_cell(d["position"]), 8);
    position = w.terrain.cell_center(c if c != NavGrid.NO_CELL else Vector2i(Terrain.SIZE / 2, Terrain.SIZE / 2));
    _update_carry_visual();

func _process(delta:float) -> void:
    var dh:float = GameClock.game_hours(delta);
    if dh <= 0.0:
        return;
    _update_needs(dh);
    if health <= 0.0:
        world.kill_pawn(self, _death_cause());
        return;
    if task != null and task.interruptible and _should_interrupt():
        end_task(false);
    if task == null:
        task = world.jobs.choose_task(self);
        if task == null:
            status = "Idle";
            return;
    _run_task(delta * GameClock.speed(), dh);
    position.y = world.terrain.height_at(position.x, position.z);

# --------------------------------
# Tools

func tool_bonus() -> float:
    return Defs.ITEMS[tool]["tool"]["bonus"] if tool != &"" else 0.0;

func equip(item:StringName) -> void:
    tool = item;
    tool_uses = Defs.ITEMS[item]["tool"]["uses"];

func _wear_tool(dh:float) -> void:
    if tool == &"":
        return;
    tool_uses -= dh;
    if tool_uses <= 0.0:
        world.notify("%s's %s broke." % [first_name, Defs.item_name(tool).to_lower()]);
        tool = &"";

func cell() -> Vector2i:
    return world.terrain.world_to_cell(position);

# --------------------------------
# Needs

func _update_needs(dh:float) -> void:
    hunger = maxf(0.0, hunger - dh / HUNGER_HOURS);
    thirst = maxf(0.0, thirst - dh / THIRST_HOURS);
    if sleeping:
        energy = minf(1.0, energy + dh * SLEEP_RESTORE);
    else:
        energy = maxf(0.0, energy - dh / ENERGY_HOURS);
    var temp:float = Weather.temperature;
    if indoors and (shelter == null or not World.alive(shelter) or shelter.is_heated()):
        warmth = minf(1.0, warmth + dh * 0.25);
    elif indoors and temp < 8.0:
        # a cold house keeps the wind off, but nobody warms up in it
        warmth = maxf(0.0, warmth - dh * (8.0 - temp) * 0.004);
    elif indoors:
        warmth = minf(1.0, warmth + dh * 0.1);
    elif temp < 8.0:
        warmth = maxf(0.0, warmth - dh * (8.0 - temp) * 0.006);
    else:
        warmth = minf(1.0, warmth + dh * 0.1);
    var damage:float = 0.0;
    if hunger <= 0.0:
        damage += 1.0 / 36.0;
    if thirst <= 0.0:
        damage += 1.0 / 18.0;
    if warmth < COLD_DAMAGE_BELOW:
        damage += (1.0 - warmth / COLD_DAMAGE_BELOW) / 24.0;
    if damage > 0.0:
        health = maxf(0.0, health - damage * dh);
    else:
        health = minf(1.0, health + dh / 48.0);

func _should_interrupt() -> bool:
    if GameClock.total_hours >= _need_block_until:
        if thirst < 0.2 or warmth < 0.2 or energy < 0.08:
            return true;
        if hunger < 0.15 and Stock.best_food() != &"":
            return true;
    return GameClock.is_night() and not NIGHT_EXEMPT.has(task.kind);

# Called by the JobManager when a need couldn't be met, so we don't thrash.
func block_needs(hours:float) -> void:
    _need_block_until = GameClock.total_hours + hours;

func needs_blocked() -> bool:
    return GameClock.total_hours < _need_block_until;

func _death_cause() -> String:
    if thirst <= 0.0:
        return "thirst";
    if hunger <= 0.0:
        return "starvation";
    if warmth < COLD_DAMAGE_BELOW:
        return "exposure";
    return "poor health";

func happiness() -> float:
    return clampf((hunger + thirst + energy + warmth + health) / 5.0 + (0.1 if home != null else -0.1), 0.0, 1.0);

# --------------------------------
# Carrying

func add_carry(item:StringName, n:int) -> void:
    if carry_item != item and carry_amount > 0:
        push_warning("%s dropped %d %s to carry %s" % [first_name, carry_amount, carry_item, item]);
    if carry_item != item:
        carry_amount = 0;
    carry_item = item;
    carry_amount += n;
    _update_carry_visual();

func set_carry(item:StringName, n:int) -> void:
    carry_item = item;
    carry_amount = n;
    _update_carry_visual();

func clear_carry() -> void:
    carry_item = &"";
    carry_amount = 0;
    _update_carry_visual();

func go_inside(b:Building, sleep:bool) -> void:
    indoors = true;
    shelter = b;
    sleeping = sleep;
    visible = false;
    if b != null:
        position = world.terrain.cell_center(b.origin + b.size / 2);

func go_outside() -> void:
    if not indoors:
        return;
    indoors = false;
    shelter = null;
    sleeping = false;
    visible = true;
    # step back onto a walkable cell next to wherever we were
    var c:Vector2i = world.nav.nearest_walkable(cell(), 8);
    if c != NavGrid.NO_CELL:
        position = world.terrain.cell_center(c);

# --------------------------------
# Tasks

func has_failed(target:Variant) -> bool:
    return _failed.has(target) and _failed[target] > GameClock.total_hours;

func end_task(success:bool) -> void:
    if task == null:
        return;
    var t:Task = task;
    task = null;
    _path.clear();
    t.finish(self, success);

func _fail_task() -> void:
    if task.target != null:
        _failed[task.target] = GameClock.total_hours + FAIL_COOLDOWN;
    end_task(false);

func _run_task(move_dt:float, dh:float) -> void:
    var step:Dictionary = task.current();
    if step.is_empty():
        end_task(true);
        return;
    status = step["status"];
    match step["type"]:
        Task.Step.MOVE:
            if not step.has("started"):
                step["started"] = true;
                if not _plan_path(step):
                    _fail_task();
                    return;
            if _follow_path(move_dt):
                task.index += 1;
        Task.Step.WORK:
            var working:bool = not NON_WORK_KINDS.has(task.kind);
            var speed:float = 1.0 + tool_bonus() if working else 1.0;
            if working:
                _wear_tool(dh);
            if (step["tick"] as Callable).call(self, dh * speed):
                task.index += 1;
        Task.Step.ACT:
            if (step["fn"] as Callable).call(self):
                task.index += 1;
            else:
                _fail_task();

func _plan_path(step:Dictionary) -> bool:
    var start:Vector2i = cell();
    if not world.nav.is_walkable(start):
        start = world.nav.nearest_walkable(start, 8);
        if start == NavGrid.NO_CELL:
            return false;
        position = world.terrain.cell_center(start);
    var goals:Array[Vector2i];
    if step.has("cell"):
        goals = world.access_cells_for_cell(step["cell"]);
    else:
        goals = world.access_cells(step["rect"], step["inside"]);
    goals.sort_custom(func(a:Vector2i, b:Vector2i) -> bool:
        return (a - start).length_squared() < (b - start).length_squared());
    for i in mini(goals.size(), 4):
        var path:Array[Vector2i] = world.nav.find_path(start, goals[i]);
        if not path.is_empty():
            _path = path;
            _path_i = 1;
            return true;
    return false;

# Advances along the path; returns true on arrival.
func _follow_path(move_dt:float) -> bool:
    var time:float = move_dt;
    var base:float = WALK_SPEED * (0.75 if energy < 0.15 else 1.0);
    while time > 0.0 and _path_i < _path.size():
        var c:Vector2i = _path[_path_i];
        var spd:float = base * (ROAD_SPEED_MULT if world.terrain.get_overlay(c) == Terrain.Overlay.ROAD else 1.0);
        var to:Vector2 = Vector2(c.x + 0.5 - position.x, c.y + 0.5 - position.z);
        var d:float = to.length();
        if d > 0.001:
            rotation.y = atan2(to.x, to.y);
        var reach:float = spd * time;
        if d <= reach:
            position.x = c.x + 0.5;
            position.z = c.y + 0.5;
            time -= d / spd;
            _path_i += 1;
        else:
            position.x += to.x / d * reach;
            position.z += to.y / d * reach;
            time = 0.0;
    return _path_i >= _path.size();

# --------------------------------
# Info / visuals

func profession_name() -> String:
    return JobManager.PROFESSION_NAMES[profession];

func info_text() -> String:
    var s:String = "%s, %s, age %d\n" % [profession_name(), "male" if is_male else "female", age];
    s += "Doing: %s\n" % status;
    if tool != &"":
        s += "Tool: %s (%d%% left)\n" % [Defs.item_name(tool), roundi(100.0 * tool_uses / Defs.ITEMS[tool]["tool"]["uses"])];
    else:
        s += "Tool: none\n";
    if carry_amount > 0:
        s += "Carrying: %d %s\n" % [carry_amount, Defs.item_name(carry_item)];
    s += "Home: %s\n\n" % (home.display_name() if home != null else "none");
    s += "Hunger  %s\n" % _bar(hunger);
    s += "Thirst  %s\n" % _bar(thirst);
    s += "Energy  %s\n" % _bar(energy);
    s += "Warmth  %s\n" % _bar(warmth);
    s += "Health  %s\n" % _bar(health);
    s += "Happy   %s\n" % _bar(happiness());
    return s;

func _bar(v:float) -> String:
    var n:int = roundi(v * 10.0);
    return "[%s%s] %d%%" % ["#".repeat(n), "-".repeat(10 - n), roundi(v * 100.0)];

func _build_visual(rng:RandomNumberGenerator) -> void:
    var body:MeshInstance3D = MeshInstance3D.new();
    var capsule:CapsuleMesh = CapsuleMesh.new();
    capsule.radius = 0.2;
    capsule.height = 1.1;
    body.mesh = capsule;
    body.position.y = 0.55;
    var body_mat:StandardMaterial3D = StandardMaterial3D.new();
    var shirts:Array[Color] = [Color(0.25, 0.35, 0.6), Color(0.3, 0.5, 0.3), Color(0.55, 0.3, 0.25), Color(0.5, 0.45, 0.3)];
    if not is_male:
        shirts = [Color(0.6, 0.3, 0.4), Color(0.55, 0.45, 0.6), Color(0.65, 0.5, 0.3), Color(0.35, 0.5, 0.55)];
    body_mat.albedo_color = shirts[rng.randi() % shirts.size()];
    body.material_override = body_mat;
    add_child(body);

    var head:MeshInstance3D = MeshInstance3D.new();
    var sphere:SphereMesh = SphereMesh.new();
    sphere.radius = 0.15;
    sphere.height = 0.3;
    head.mesh = sphere;
    head.position.y = 1.25;
    var skin:StandardMaterial3D = StandardMaterial3D.new();
    skin.albedo_color = Color(0.93, 0.78, 0.65).darkened(rng.randf() * 0.4);
    head.material_override = skin;
    add_child(head);

    _carry_mesh = MeshInstance3D.new();
    var box:BoxMesh = BoxMesh.new();
    box.size = Vector3(0.35, 0.3, 0.3);
    _carry_mesh.mesh = box;
    _carry_mesh.position = Vector3(0, 0.75, 0.28);
    _carry_mat = StandardMaterial3D.new();
    _carry_mesh.material_override = _carry_mat;
    _carry_mesh.visible = false;
    add_child(_carry_mesh);

func _update_carry_visual() -> void:
    _carry_mesh.visible = carry_amount > 0;
    if carry_amount > 0:
        _carry_mat.albedo_color = Defs.ITEMS[carry_item]["color"];
