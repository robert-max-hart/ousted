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
var fuel        :int = 0;           # firewood stocked here (houses)
var fuel_incoming:int = 0;          # firewood being carried here
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
    return state == State.COMPLETE and def.get("storage", false);

func capacity() -> int:
    return def.get("capacity", 0);

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
    if not is_storage() or forbidden.has(item):
        return false;
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
    return def["cost"];

# Units of item still needed that nobody is bringing yet.
func remaining(item:StringName) -> int:
    return cost().get(item, 0) - delivered.get(item, 0) - incoming.get(item, 0);

func has_all_materials() -> bool:
    for item in cost():
        if delivered.get(item, 0) < cost()[item]:
            return false;
    return true;

func work_required() -> float:
    return def["work"];

func progress() -> float:
    if work_required() <= 0.0:
        return 1.0;
    return clampf(work_done / work_required(), 0.0, 1.0);

func ready_for_work() -> bool:
    return state == State.CONSTRUCTION and has_all_materials() and world.is_site_clear(self);

func receive(item:StringName, n:int) -> void:
    incoming[item] = maxi(0, incoming.get(item, 0) - n);
    delivered[item] = delivered.get(item, 0) + n;

func cancel_incoming(item:StringName, n:int) -> void:
    incoming[item] = maxi(0, incoming.get(item, 0) - n);

# Adds labor; returns true once construction is finished.
func add_work(hours:float) -> bool:
    if state != State.CONSTRUCTION:
        return true;
    work_done += hours;
    _update_visual();
    if work_done >= work_required():
        complete();
        return true;
    return false;

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
    if not def.has("beds"):
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
    if def.get("storage", false) and state == State.COMPLETE:
        s += "Stored %d / %d\n" % [used(), capacity()];
        for item in stored:
            s += "  %s: %d\n" % [Defs.item_name(item), stored[item]];
        if def.has("spoil_mult"):
            s += "Food keeps %s here.\n" % ("twice as long" if is_equal_approx(spoil_mult(), 0.5) else "longer" if spoil_mult() < 1.0 else "for less time");
    if def.has("fuel_capacity") and state == State.COMPLETE:
        s += "Firewood: %d / %d" % [fuel, def["fuel_capacity"]];
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
