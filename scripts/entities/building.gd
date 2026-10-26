# ----------------------------------------------------------------
# Building
#     A placed structure. Goes through construction (materials hauled
#     in, then labor) before it starts functioning.
# ----------------------------------------------------------------
class_name Building extends Node3D;

enum State { CONSTRUCTION, COMPLETE };

var def_id      :StringName;
var def         :Dictionary;
var origin      :Vector2i;
var size        :Vector2i;
var state       :int = State.CONSTRUCTION;
var delivered   :Dictionary = {};   # item -> int already on site
var incoming    :Dictionary = {};   # item -> int being carried here
var work_done   :float = 0.0;
var builders    :int = 0;
var residents   :Array[Pawn] = [];
var removed     :bool = false;
var world       :World;

# Storage buildings only
var stored      :Dictionary = {};   # item -> int in the building
var out_reserved:Dictionary = {};   # item -> int promised to a pawn who is on the way to collect it
var in_reserved :int = 0;           # units of space promised to pawns on the way to deliver
var forbidden   :Dictionary = {};   # item -> true when the player has forbidden it here
var settings    :Dictionary = {};   # control id -> current value (see Defs control schema)
var fuel        :int = 0;           # fuel stocked here in firewood-equivalents (houses; coal counts double)
var fuel_incoming:int = 0;          # firewood being carried here
var inputs      :Dictionary = {};   # item -> int in the input inventory (production buildings)
var input_incoming:Dictionary = {}; # item -> int being carried here
var upgrades_done:Dictionary = {};   # upgrade id -> true
var upgrading   :StringName = &"";  # upgrade being built right now, or &"" (while set, delivered/incoming/work_done belong to it)
var _base_spent :Dictionary = {};   # materials the building itself cost, set aside while an upgrade is built
var dig_progress:Dictionary = {};   # item -> labor-hours into the next unit (mines)
var cost_mult   :float = 1.0;       # share of the build cost and work (a relocation costs Defs.RELOCATE_COST_MULT)
var relocating_from:Building = null;    # on a relocation site: the building it replaces
var relocating_to:Building = null;      # on the old building: the site being built for it
var teaching     :bool = false;      # a teacher is at this school right now
var teaching_mult:float = 1.0;       # how much faster pupils learn under the teacher present (Defs.teacher_multiplier)
var attendees    :int = 0;           # children who have a seat here (school)
var workers     :int = 0;           # citizens currently working here (job buildings)
var _spoil_acc  :Dictionary = {};
var _burn_acc   :float = 0.0;   # item -> fractional units spoiled so far

var _body       :MeshInstance3D;
var _roof       :MeshInstance3D;
var _body_mat   :StandardMaterial3D;

func setup(w:World, id:StringName, o:Vector2i, s:Vector2i) -> void:
    world = w;
    def_id = id;
    def = Defs.BUILDINGS[id];
    origin = o;
    size = s;
    name = "%s_%d_%d" % [id, o.x, o.y];
    for c in def.get("controls", []):
        settings[c["id"]] = c["default"];
    var center:Vector2 = Vector2(origin.x + size.x * 0.5, origin.y + size.y * 0.5);
    position = Vector3(center.x, w.terrain.height_at(center.x, center.y), center.y);
    _build_visual();
    _update_visual();

func rect() -> Rect2i:
    return Rect2i(origin, size);

func display_name() -> String:
    return def["name"];

func is_complete() -> bool:
    return state == State.COMPLETE;

func is_walkable() -> bool:
    return def.get("walkable", false);

# --------------------------------
# Storage

func is_storage() -> bool:
    return state == State.COMPLETE and capacity() > 0;

# Built-in capacity plus what its finished upgrades add (the Town Hall's store rooms).
func capacity() -> int:
    var n:int = def.get("capacity", 0) if def.get("storage", false) else 0;
    for id in upgrades_done:
        n += def.get("upgrades", {}).get(id, {}).get("capacity", 0);
    return n;

func used() -> int:
    var n:int = 0;
    for item in stored:
        n += stored[item];
    return n;

# Space that is neither filled nor promised to someone already on the way.
func free_space() -> int:
    return maxi(0, capacity() - used() - in_reserved);

# Whether this building would take the item at all (type rules and the player's filter).
func accepts(item:StringName) -> bool:
    if not is_storage() or forbidden.has(item) or def.get("temporary", false) or relocating_to != null:
        return false;       # a supply cart only gives, and a building being moved takes nothing new
    if def.has("accepts_items"):
        return (def["accepts_items"] as Array).has(item);
    return Defs.is_food(item) or not def.get("food_only", false);

func can_store(item:StringName) -> bool:
    return accepts(item) and free_space() > 0;

func amount(item:StringName) -> int:
    return stored.get(item, 0);

func available(item:StringName) -> int:
    return amount(item) - out_reserved.get(item, 0);

# Stores up to n units straight away, returns how many fit.
func store(item:StringName, n:int) -> int:
    var t:int = mini(n, maxi(0, capacity() - used()));
    if t > 0:
        stored[item] = amount(item) + t;
    return t;

# Promises up to n units of space to an arriving pawn, returns how many were promised.
func reserve_space(n:int) -> int:
    var r:int = clampi(n, 0, free_space());
    in_reserved += r;
    return r;

func release_space(n:int) -> void:
    in_reserved = maxi(0, in_reserved - n);

# Reserves up to n available units for a pawn who is coming to collect them.
func reserve_out(item:StringName, n:int) -> int:
    var r:int = clampi(n, 0, available(item));
    out_reserved[item] = out_reserved.get(item, 0) + r;
    return r;

func release_out(item:StringName, n:int) -> void:
    out_reserved[item] = maxi(0, out_reserved.get(item, 0) - n);

# Removes up to n units, returns how many were taken.
func take(item:StringName, n:int) -> int:
    var t:int = mini(n, amount(item));
    stored[item] = amount(item) - t;
    if stored[item] <= 0:
        stored.erase(item);
    return t;

func take_reserved(item:StringName, n:int) -> int:
    release_out(item, n);
    return take(item, n);

# True when nothing is stored and nobody is coming to collect or deliver.
func is_empty() -> bool:
    if in_reserved > 0:
        return false;
    for item in out_reserved:
        if out_reserved[item] > 0:
            return false;
    return used() == 0;

# Multiplier on spoilage speed here (granary 0.5, and so on). Room for upgrades and add-ons later.
func spoil_mult() -> float:
    return def.get("spoil_mult", 1.0);

# Spoils stored food for `hours` game hours at the current temperature. Returns units lost.
# Units promised to a pawn who is on the way to collect them are spared.
func spoil_tick(hours:float) -> int:
    var lost:int = 0;
    var k:float = Defs.spoil_temp_factor(Weather.temperature) * spoil_mult() * hours;
    for item in stored.keys():
        var rate:float = Defs.spoil_per_hour(item);
        if rate <= 0.0 or Defs.ITEMS[item].get("outside_only", false):
            continue;
        _spoil_acc[item] = _spoil_acc.get(item, 0.0) + available(item) * rate * k;
        var whole:int = mini(floori(_spoil_acc[item]), available(item));
        if whole > 0:
            _spoil_acc[item] -= whole;
            take(item, whole);
            lost += whole;
    return lost;

# Production cap for an output item: 0 means no cap. The cap compares against the colony-wide stock.
func production_cap(item:StringName) -> int:
    return settings.get("cap_%s" % item, 0);

func production_allowed(item:StringName) -> bool:
    var cap:int = production_cap(item);
    return cap <= 0 or Stock.amount(item) < cap;

# --------------------------------
# Input inventory (production buildings: see "inputs" and "recipes" in Defs)

func input_amount(item:StringName) -> int:
    return inputs.get(item, 0)

func add_input(item:StringName, n:int) -> void:
    inputs[item] = input_amount(item) + n;

func take_input(item:StringName, n:int) -> void:
    inputs[item] = maxi(0, input_amount(item) - n);

func cancel_input_incoming(item:StringName, n:int) -> void:
    input_incoming[item] = maxi(0, input_incoming.get(item, 0) - n);

func recipe_enabled(item:StringName) -> bool:
    var toggle:String = def["recipes"][item].get("toggle", "make_%s" % item);
    return settings.get(toggle, true) and production_allowed(item);

func has_inputs(recipe:Dictionary) -> bool:
    for item in recipe["inputs"]:
        if input_amount(item) < recipe["inputs"][item]:
            return false;
    return true;

# Input units still wanted for the recipes that are switched on and under their cap.
func inputs_wanted() -> Dictionary:
    var want:Dictionary = {};
    if not is_complete() or not def.has("recipes"):
        return want;
    for item in def["recipes"]:
        if recipe_enabled(item):
            for in_item in def["recipes"][item]["inputs"]:
                var n:int = def["inputs"].get(in_item, 0) - input_amount(in_item) - input_incoming.get(in_item, 0);
                if n > 0:
                    want[in_item] = n;
    return want;

func radius() -> float:
    return def.get("radius", 0.0);

func center_cell() -> Vector2:
    return Vector2(origin) + Vector2(size) * 0.5;

func set_forbidden(item:StringName, forbid:bool) -> void:
    if forbid:
        forbidden[item] = true;
    else:
        forbidden.erase(item);

# --------------------------------
# Construction

func cost() -> Dictionary:
    if upgrading != &"":
        return def["upgrades"][upgrading]["cost"];
    if cost_mult == 1.0:
        return def["cost"];
    var c:Dictionary = {};
    for item in def["cost"]:
        c[item] = maxi(1, ceili(def["cost"][item] * cost_mult));
    return c;

# True while the building is being constructed or upgraded: materials and labor are still wanted.
func is_site() -> bool:
    return state == State.CONSTRUCTION or upgrading != &"";

# Units of item still needed that nobody is bringing yet.
func remaining(item:StringName) -> int:
    return cost().get(item, 0) - delivered.get(item, 0) - incoming.get(item, 0);

func has_all_materials() -> bool:
    for item in cost():
        if delivered.get(item, 0) < cost()[item]:
            return false;
    return true;

func work_required() -> float:
    return def["upgrades"][upgrading]["work"] if upgrading != &"" else def["work"] * cost_mult;

func progress() -> float:
    if work_required() <= 0.0:
        return 1.0;
    return clampf(work_done / work_required(), 0.0, 1.0);

func ready_for_work() -> bool:
    return is_site() and has_all_materials() and (upgrading != &"" or world.is_site_clear(self));

func receive(item:StringName, n:int) -> void:
    incoming[item] = maxi(0, incoming.get(item, 0) - n);
    delivered[item] = delivered.get(item, 0) + n;

func cancel_incoming(item:StringName, n:int) -> void:
    incoming[item] = maxi(0, incoming.get(item, 0) - n);

# Adds labor; returns true once construction is finished.
func add_work(hours:float) -> bool:
    if not is_site():
        return true;
    work_done += hours;
    _update_visual();
    if work_done >= work_required():
        if upgrading != &"":
            _finish_upgrade();
        else:
            complete();
        return true;
    return false;

# --------------------------------
# Upgrades (see "upgrades" in Defs)

func has_upgrade(id:StringName) -> bool:
    return upgrades_done.has(id);

# Why an upgrade can't be started right now, or "" when it can.
func upgrade_block_reason(id:StringName) -> String:
    var ups:Dictionary = def.get("upgrades", {});
    if not ups.has(id) or not is_complete():
        return "Not available";
    if has_upgrade(id):
        return "Already built";
    if upgrading != &"":
        return "Another upgrade is in progress";
    for other in upgrades_done:
        if (ups[id].get("excludes", []) as Array).has(other) or (ups.get(other, {}).get("excludes", []) as Array).has(id):
            return "Excluded by %s" % ups[other]["name"];
    for req in ups[id].get("requires", []):
        if not has_upgrade(req):
            return "Needs %s first" % ups[req]["name"];
    return "";

func start_upgrade(id:StringName) -> bool:
    if upgrade_block_reason(id) != "":
        return false;
    _base_spent = delivered;
    delivered = {};
    incoming = {};
    work_done = 0.0;
    upgrading = id;
    return true;

# Stops the upgrade in progress and returns the materials already delivered to it.
func cancel_upgrade() -> void:
    if upgrading == &"":
        return;
    for item in delivered:
        world.deposit(item, delivered[item], position);
    # hauling and building aimed here stops now, before the project it served is gone
    for p in world.pawns:
        if p.task != null and is_same(p.task.target, self) and p.task.kind in [&"haul", &"build"]:
            p.end_task(false);
    delivered = _base_spent;
    _base_spent = {};
    incoming = {};
    work_done = work_required();
    upgrading = &"";

func _finish_upgrade() -> void:
    for item in _base_spent:
        delivered[item] = delivered.get(item, 0) + _base_spent[item];
    _base_spent = {};
    incoming = {};
    upgrades_done[upgrading] = true;
    world.notify("%s: %s built." % [display_name(), def["upgrades"][upgrading]["name"]]);
    upgrading = &"";
    work_done = def["work"];

# Whether this building handles the item yet (a mine needs Deep Shafts before it digs coal).
func item_unlocked(item:StringName) -> bool:
    var need:Variant = def.get("locked_until", {}).get(item, null);
    return need == null or has_upgrade(need);

# All materials ever delivered here, for refunds.
func all_delivered() -> Dictionary:
    var all:Dictionary = _base_spent.duplicate();
    for item in delivered:
        all[item] = all.get(item, 0) + delivered[item];
    return all;

func complete() -> void:
    state = State.COMPLETE;
    work_done = work_required();
    _update_visual();
    world.on_building_completed(self);

# --------------------------------
# Simulation hooks (called by World)

func on_hour() -> void:
    _burn_fuel(1.0);

func on_day() -> void:
    pass;

func on_terrain_changed() -> void:
    pass;

# --------------------------------
# Heating (housing)

# Whether occupants stay warm here. Buildings with no fuel need (the Town Hall) are always warm.
func is_heated() -> bool:
    if def.has("heated_by"):
        return is_complete() and has_upgrade(def["heated_by"]);
    if not def.has("beds") or def.get("shack", false):
        return false;
    if not def.has("fuel_capacity"):
        return true;
    return settings.get("heating", false) and fuel > 0;

func fuel_wanted() -> int:
    if not def.has("fuel_capacity") or not settings.get("heating", false) or not is_complete():
        return 0;
    return maxi(0, mini(def["fuel_capacity"], settings.get("fuel_target", 0)) - fuel - fuel_incoming);

# Burns firewood while it is cold and someone lives here; the colder, the faster.
func _burn_fuel(hours:float) -> void:
    if not def.has("fuel_capacity") or not is_complete() or not settings.get("heating", false):
        return;
    if residents.is_empty() or Weather.temperature >= Defs.HEATING_BELOW:
        return;
    var cold:float = (Defs.HEATING_BELOW - Weather.temperature) / Defs.HEATING_BELOW;
    _burn_acc += cold * Defs.FIREWOOD_PER_DAY_AT_0C / GameClock.HOURS_PER_DAY * hours;
    var whole:int = floori(_burn_acc + 0.0001);
    if whole > 0:
        _burn_acc -= whole;
        fuel = maxi(0, fuel - whole);

# --------------------------------
# Save and load. Reservations, incoming deliveries and who is working here are not saved: citizens
# start over without tasks, so those are all empty again.

func to_dict() -> Dictionary:
    return {
        "id": def_id, "origin": origin, "size": size, "state": state, "delivered": delivered.duplicate(),
        "work_done": work_done, "stored": stored.duplicate(), "forbidden": forbidden.duplicate(),
        "settings": settings.duplicate(), "fuel": fuel, "inputs": inputs.duplicate(),
        "upgrades_done": upgrades_done.duplicate(), "upgrading": upgrading, "base_spent": _base_spent.duplicate(),
        "dig_progress": dig_progress.duplicate(), "spoil_acc": _spoil_acc.duplicate(), "burn_acc": _burn_acc,
        "cost_mult": cost_mult, "reloc_from": world.buildings.find(relocating_from) if relocating_from != null else -1,
        "reloc_to": world.buildings.find(relocating_to) if relocating_to != null else -1,
    };

func restore_dict(d:Dictionary) -> void:
    state = d["state"];
    delivered = d["delivered"];
    work_done = d["work_done"];
    stored = d["stored"];
    forbidden = d["forbidden"];
    for key in d["settings"]:
        if settings.has(key):          # controls added since the save keep their defaults
            settings[key] = d["settings"][key];
    fuel = d["fuel"];
    inputs = d["inputs"];
    upgrades_done = d["upgrades_done"];
    upgrading = d["upgrading"];
    _base_spent = d["base_spent"];
    dig_progress = d["dig_progress"];
    _spoil_acc = d["spoil_acc"];
    _burn_acc = d["burn_acc"];
    cost_mult = d.get("cost_mult", 1.0);
    _update_visual();

# --------------------------------
# Info

func info_text() -> String:
    var s:String = "";
    if state == State.CONSTRUCTION:
        s += "Under construction (%d%%)\n" % roundi(progress() * 100.0);
        if not world.is_site_clear(self):
            s += "Waiting for the site to be cleared\n";
        for item in cost():
            s += "  %s: %d / %d\n" % [Defs.item_name(item), delivered.get(item, 0), cost()[item]];
        if not has_all_materials():
            s += "Waiting for materials\n";
        s += "Builders: %d\n" % builders;
    else:
        s += def.get("desc", "") + "\n";
    if capacity() > 0 and state == State.COMPLETE:
        s += "Stored %d / %d\n" % [used(), capacity()];
        for item in stored:
            s += "  %s: %d\n" % [Defs.item_name(item), stored[item]];
        if def.has("spoil_mult"):
            s += "Food keeps %s here.\n" % ("twice as long" if is_equal_approx(spoil_mult(), 0.5) else "longer" if spoil_mult() < 1.0 else "for less time");
    if def.has("school_capacity") and state == State.COMPLETE:
        s += "Pupils: %d / %d\n" % [attendees, def["school_capacity"]];
        s += "Teacher: %s\n" % ("teaching now (pupils learn %.2fx)" % teaching_mult if teaching else "none present");
    if def_id == &"town_hall" and not world.death_log.is_empty():
        s += "Recent deaths:\n";
        for entry in world.death_log.slice(-5):
            s += "  %s, age %d, %s (%s)\n" % [entry["name"], entry["age"], entry["cause"], entry["when"]];
    if upgrading != &"":
        s += "Upgrading: %s (%d%%)\n" % [def["upgrades"][upgrading]["name"], roundi(progress() * 100.0)];
        for item in cost():
            s += "  %s: %d / %d\n" % [Defs.item_name(item), delivered.get(item, 0), cost()[item]];
        if not has_all_materials():
            s += "Waiting for materials\n";
        s += "Builders: %d\n" % builders;
    if not upgrades_done.is_empty():
        var names:PackedStringArray = [];
        for id in upgrades_done:
            names.append(def["upgrades"][id]["name"]);
        s += "Upgrades: %s\n" % ", ".join(names);
    if def.has("inputs") and state == State.COMPLETE:
        var parts:PackedStringArray = [];
        for item in def["inputs"]:
            parts.append("%s %d/%d" % [Defs.item_name(item), input_amount(item), def["inputs"][item]]);
        s += "Inputs: %s\n" % ", ".join(parts);
    if def.has("fuel_capacity") and state == State.COMPLETE:
        s += "Fuel: %d / %d" % [fuel, def["fuel_capacity"]];
        if not settings.get("heating", false):
            s += " (heating off)";
        elif fuel <= 0:
            s += " (cold!)";
        s += "\n";
    if def.has("beds"):
        var names:PackedStringArray = [];
        for p in residents:
            names.append(p.first_name);
        s += "Residents (%d/%d): %s\n" % [residents.size(), def["beds"], ", ".join(names)];
    return s;

# --------------------------------
# Visuals

func _build_visual() -> void:
    var shape:String = def.get("shape", "house");
    var h:float = def.get("height", 2.0);
    _body_mat = StandardMaterial3D.new();
    _body_mat.albedo_color = def.get("color", Color.GRAY);
    _body_mat.roughness = 0.9;
    match shape:
        "house":
            var box:BoxMesh = BoxMesh.new();
            box.size = Vector3(size.x - 0.5, h, size.y - 0.5);
            _body = _add_mesh(box, _body_mat, Vector3(0, h * 0.5, 0));
            var prism:PrismMesh = PrismMesh.new();
            prism.size = Vector3(size.x - 0.1, h * 0.6, size.y - 0.2);
            _roof = _add_mesh(prism, _flat_mat(def.get("roof", Color.DARK_RED)), Vector3(0, h + h * 0.3, 0));
        "well":
            var cyl:CylinderMesh = CylinderMesh.new();
            cyl.top_radius = 0.7;
            cyl.bottom_radius = 0.75;
            cyl.height = h;
            _body = _add_mesh(cyl, _body_mat, Vector3(0, h * 0.5, 0));
            var cap:PrismMesh = PrismMesh.new();
            cap.size = Vector3(1.6, 0.5, 1.2);
            _roof = _add_mesh(cap, _flat_mat(def.get("roof", Color.BROWN)), Vector3(0, h + 0.9, 0));
        "mine":
            var pit:BoxMesh = BoxMesh.new();
            pit.size = Vector3(size.x - 0.3, 0.2, size.y - 0.3);
            _add_mesh(pit, _flat_mat(Color(0.32, 0.28, 0.25)), Vector3(0, 0.1, 0));
            var shed:BoxMesh = BoxMesh.new();
            shed.size = Vector3(size.x * 0.5, h, size.y * 0.4);
            _body = _add_mesh(shed, _body_mat, Vector3(-size.x * 0.2, h * 0.5, -size.y * 0.25));
            var cap:PrismMesh = PrismMesh.new();
            cap.size = Vector3(size.x * 0.55, h * 0.4, size.y * 0.45);
            _roof = _add_mesh(cap, _flat_mat(def.get("roof", Color.BROWN)), Vector3(-size.x * 0.2, h + h * 0.2, -size.y * 0.25));
            var heap:BoxMesh = BoxMesh.new();
            heap.size = Vector3(1.2, 0.6, 1.2);
            _add_mesh(heap, _flat_mat(Color(0.6, 0.6, 0.6)), Vector3(size.x * 0.25, 0.4, size.y * 0.2));
        "graveyard":
            var ground:BoxMesh = BoxMesh.new();
            ground.size = Vector3(size.x - 0.1, h, size.y - 0.1);
            _body = _add_mesh(ground, _body_mat, Vector3(0, h * 0.5, 0));
        "cart":
            var bed:BoxMesh = BoxMesh.new();
            bed.size = Vector3(size.x - 0.3, h * 0.5, size.y * 0.8);
            _body = _add_mesh(bed, _body_mat, Vector3(0, h * 0.55, 0));
            var load_mesh:BoxMesh = BoxMesh.new();
            load_mesh.size = Vector3(size.x - 0.7, h * 0.35, size.y * 0.55);
            _roof = _add_mesh(load_mesh, _flat_mat(Color(0.75, 0.65, 0.4)), Vector3(0, h * 0.95, 0));
            var wheel:CylinderMesh = CylinderMesh.new();
            wheel.top_radius = 0.28;
            wheel.bottom_radius = 0.28;
            wheel.height = 0.1;
            for sx in [-0.55, 0.55]:
                var w:MeshInstance3D = _add_mesh(wheel, _flat_mat(Color(0.25, 0.18, 0.12)), Vector3(sx, 0.28, size.y * 0.42));
                w.rotation.z = PI * 0.5;
        "pile":
            var pad:BoxMesh = BoxMesh.new();
            pad.size = Vector3(size.x - 0.3, h, size.y - 0.3);
            _body = _add_mesh(pad, _body_mat, Vector3(0, h * 0.5, 0));
            var crate:BoxMesh = BoxMesh.new();
            crate.size = Vector3(0.7, 0.6, 0.7);
            _roof = _add_mesh(crate, _flat_mat(Color(0.6, 0.45, 0.28)), Vector3(-0.8, h + 0.3, -0.8));
        _:
            pass;

func _update_visual() -> void:
    if _body == null:
        return;
    var building:bool = state == State.CONSTRUCTION;
    _body_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if building else BaseMaterial3D.TRANSPARENCY_DISABLED;
    var col:Color = def.get("color", Color.GRAY);
    col.a = 0.45 if building else 1.0;
    _body_mat.albedo_color = col;
    var sy:float = lerpf(0.15, 1.0, progress()) if building else 1.0;
    _body.scale = Vector3(1.0, sy, 1.0);
    var h:float = def.get("height", 2.0);
    _body.position.y = h * 0.5 * sy;
    if _roof != null:
        _roof.visible = not building;

func _add_mesh(mesh:Mesh, mat:Material, at:Vector3) -> MeshInstance3D:
    var mi:MeshInstance3D = MeshInstance3D.new();
    mi.mesh = mesh;
    mi.material_override = mat;
    mi.position = at;
    add_child(mi);
    return mi;

func _flat_mat(c:Color) -> StandardMaterial3D:
    var m:StandardMaterial3D = StandardMaterial3D.new();
    m.albedo_color = c;
    m.roughness = 0.9;
    return m;
