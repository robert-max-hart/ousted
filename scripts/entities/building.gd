# ----------------------------------------------------------------
# Building
#     A placed structure. Goes through construction (materials hauled
#     in, then labor) before it starts functioning.
# ----------------------------------------------------------------
class_name Building extends Node3D;

enum State { CONSTRUCTION, COMPLETE };

# Build priority of a site (or an upgrade being built): paused sites get no hauling or building, and the rest are
# served highest first (ties go to the nearest).
const PRIORITY_NAMES:Array[String] = ["Paused", "Low", "Medium", "High", "Critical"];
const PRIORITY_PAUSED:int = 0;
const PRIORITY_MEDIUM:int = 2;

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
var fuel_coal   :int = 0;           # how much of `fuel` came from coal (it burns after the firewood: drives the smoke colour)
var fuel_incoming:int = 0;          # firewood being carried here
var inputs      :Dictionary = {};   # item -> int in the input inventory (production buildings)
var input_incoming:Dictionary = {}; # item -> int being carried here
var upgrades_done:Dictionary = {};   # upgrade id -> true
var expansion   :Dictionary = {};   # while upgrading is Expansion.ID: {rect, cost, work} for the bigger footprint
var upgrading   :StringName = &"";  # upgrade being built right now, or &"" (while set, delivered/incoming/work_done belong to it)
var _base_spent :Dictionary = {};   # materials the building itself cost, set aside while an upgrade is built
var dig_progress:Dictionary = {};   # item -> labor-hours into the next unit (mines)
var priority    :int = PRIORITY_MEDIUM;
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
var _fence      :Fence;                            # a fence or wall round the footprint (graveyard, stockpile, field)
var _decor      :Array[MeshInstance3D] = [];       # extra shapes (BuildingShapes), hidden while a site
var _body_y0    :float = 0.0;                      # where the body starts and how tall it is, for the rising frame of a site
var _body_h     :float = 0.0;
var _chimney    :MeshInstance3D;
var _smoke      :CPUParticles3D;
var _body_mat   :StandardMaterial3D;
var _door       :MeshInstance3D;
var _windows    :Array[MeshInstance3D] = [];
var windows_lit_always:bool = false;      # the title screen's mock town: lit without residents
var smoke_always:bool = false;            # ... and smoking without a fire to feed
var _window_mat :StandardMaterial3D;
var _site_label :Label3D;        # floats over a site that is paused or short of materials

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

# The ground this building holds: its rectangle, or the bigger one it is being expanded into.
func footprint() -> Rect2i:
    return expansion["rect"] if upgrading == Expansion.ID and not expansion.is_empty() else rect();

# Called once an expansion has changed origin and size: refit what is drawn (and, in subclasses, per-plot data).
func on_resized(_old:Rect2i) -> void:
    name = "%s_%d_%d" % [def_id, origin.x, origin.y];
    var center:Vector2 = Vector2(origin.x + size.x * 0.5, origin.y + size.y * 0.5);
    position = Vector3(center.x, world.terrain.height_at(center.x, center.y), center.y);
    if def.get("shape", "") == "pile" and _body != null:
        (_body.mesh as BoxMesh).size = Vector3(size.x - 0.3, def.get("height", 0.1), size.y - 0.3);
    if _fence != null:
        _fence.rebuild();

func display_name() -> String:
    return def["name"];

func is_complete() -> bool:
    return state == State.COMPLETE;

# A site can be walked over while it goes up, so whatever stands in the middle of it can still be reached and cleared.
func is_walkable() -> bool:
    return def.get("walkable", false) or state == State.CONSTRUCTION;

# --------------------------------
# Storage

func is_storage() -> bool:
    return state == State.COMPLETE and capacity() > 0;

# Built-in capacity plus what its finished upgrades add (the Town Hall's store rooms).
func capacity() -> int:
    var n:int = roundi(def.get("capacity", 0) * area_mult()) if def.get("storage", false) else 0;
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

# How well this store suits an item (lower is better): food keeps best in a Granary (spoil_mult), and a store made
# for certain goods beats a general one. A store the player has since forbidden the item in is the worst place.
func storage_rank(item:StringName) -> float:
    var rank:float = 0.0;
    if forbidden.has(item):
        rank += 100.0;
    if Defs.is_food(item):
        rank += spoil_mult() * 10.0;
    var specialised:bool = def.has("accepts_items") or (def.get("food_only", false) and Defs.is_food(item));
    return rank + (0.0 if specialised else 3.0);

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

# Spoils stored food for `hours` game hours at the current temperature. Returns units lost (and adds them, by item, to tally).
# Units promised to a pawn who is on the way to collect them are spared.
func spoil_tick(hours:float, tally:Dictionary = {}) -> int:
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
            tally[item] = tally.get(item, 0) + whole;
    return lost;

# Production cap for an output item: 0 means no cap. The cap compares against the colony-wide stock.
func production_cap(item:StringName) -> int:
    return settings.get("cap_%s" % item, 0);

func production_allowed(item:StringName) -> bool:
    var cap:int = production_cap(item);
    var have:int = Stock.food_total() if item == &"food" else Stock.amount(item);     # "food" caps the whole food stock
    return cap <= 0 or have < cap;

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
    var recipe:Dictionary = def["recipes"][item];
    if recipe.get("off_at_zero", false) and production_cap(item) <= 0:
        return false;
    var toggle:String = recipe.get("toggle", "make_%s" % item);
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
    if upgrading == Expansion.ID:
        return expansion["cost"];
    if upgrading != &"":
        return def["upgrades"][upgrading]["cost"];
    var mult:float = cost_mult * area_mult();
    if is_equal_approx(mult, 1.0):
        return def["cost"];
    var c:Dictionary = {};
    for item in def["cost"]:
        c[item] = maxi(1, ceili(def["cost"][item] * mult));
    return c;

# Buildings the player sizes by dragging and that scale with their area (stockpiles): the share of the default
# footprint, applied to cost, work and capacity.
func area_mult() -> float:
    if not def.get("scalable", false):
        return 1.0;
    var d:Vector2i = def["size"];
    return float(size.x * size.y) / (d.x * d.y);

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
    if upgrading == Expansion.ID:
        return expansion["work"];
    return def["upgrades"][upgrading]["work"] if upgrading != &"" else def["work"] * cost_mult * area_mult();

func progress() -> float:
    if work_required() <= 0.0:
        return 1.0;
    return clampf(work_done / work_required(), 0.0, 1.0);

func ready_for_work() -> bool:
    return is_site() and has_all_materials() and (upgrading != &"" or world.is_site_clear(self));

func receive(item:StringName, n:int) -> void:
    incoming[item] = maxi(0, incoming.get(item, 0) - n);
    delivered[item] = delivered.get(item, 0) + n;
    update_site_label();

func cancel_incoming(item:StringName, n:int) -> void:
    incoming[item] = maxi(0, incoming.get(item, 0) - n);

func set_priority(p:int) -> void:
    priority = clampi(p, PRIORITY_PAUSED, PRIORITY_NAMES.size() - 1);
    if priority == PRIORITY_PAUSED:
        world.release_site_workers(self);
    update_site_label();

func is_paused() -> bool:
    return is_site() and priority == PRIORITY_PAUSED;

# What the site still needs that the colony's storage can't supply, as "5 wood, 2 stone", or "" when there is enough.
func shortage_text() -> String:
    if not is_site():
        return "";
    var parts:PackedStringArray = [];
    for item in cost():
        var short:int = remaining(item) - Stock.available(item);
        if short > 0:
            parts.append("%d %s" % [short, Defs.item_name(item).to_lower()]);
    return ", ".join(parts);

# The floating note over a site: PAUSED, a priority other than the usual, and a "!" when storage can't cover
# what it still needs (the full list of what is missing shows while it is selected).
func update_site_label() -> void:
    var text:String = "";
    var short:String = shortage_text();
    if is_paused():
        text = "PAUSED";
    elif is_site() and priority != PRIORITY_MEDIUM:
        text = "%s priority" % PRIORITY_NAMES[priority];
    if short != "":
        var picked:bool = world.tools != null and is_same(world.tools.selected, self);
        text += ("\n" if text != "" else "") + ("Needs " + short if picked else "!");
    if text == "":
        if _site_label != null:
            _site_label.visible = false;
        return;
    if _site_label == null:
        _site_label = Label3D.new();
        _site_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED;
        _site_label.pixel_size = 0.015;
        _site_label.font_size = 28;
        _site_label.outline_size = 8;
        _site_label.no_depth_test = true;
        _site_label.shaded = false;
        _site_label.position = Vector3(0, def.get("height", 2.0) + 2.4, 0);
        _site_label.visible = false;
        add_child(_site_label);
    _site_label.text = text;
    _site_label.modulate = Color(1.0, 0.75, 0.25) if is_paused() else Color(1.0, 0.45, 0.4);
    _site_label.visible = true;

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
    Expansion.cancel(world, self);
    upgrading = &"";

func _finish_upgrade() -> void:
    for item in _base_spent:
        delivered[item] = delivered.get(item, 0) + _base_spent[item];
    _base_spent = {};
    incoming = {};
    if upgrading == Expansion.ID:
        upgrading = &"";
        Expansion.finish(world, self);
        work_done = work_required();
        return;
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
    update_site_label();
    world._refresh_nav_rect(rect());       # a finished building may block the cells under it
    world.on_building_completed(self);

# --------------------------------
# Simulation hooks (called by World)

func on_hour() -> void:
    update_site_label();
    update_windows();
    _burn_fuel(1.0);
    update_smoke();

func on_day() -> void:
    pass;

func on_terrain_changed() -> void:
    if _fence != null:
        _fence.rebuild();

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
        var from_coal:int = maxi(0, mini(fuel_coal, whole - (fuel - fuel_coal)));       # firewood goes first
        fuel = maxi(0, fuel - whole);
        fuel_coal = clampi(fuel_coal - from_coal, 0, fuel);

# Adds fuel delivered by a citizen (heat in firewood-equivalents), remembering how much of it is coal.
func add_fuel(item:StringName, heat:int) -> void:
    var added:int = mini(heat, def["fuel_capacity"] - fuel);
    fuel += added;
    if item == &"coal":
        fuel_coal += added;
    update_smoke();

# Whether the chimney is smoking: the house is burning fuel for someone inside.
func is_burning() -> bool:
    return def.has("fuel_capacity") and is_complete() and settings.get("heating", false) and fuel > 0 \
            and not residents.is_empty() and Weather.temperature < Defs.HEATING_BELOW;

# The smoke follows the game speed: still when paused, quicker when sped up.
func _on_clock_speed(_index:int) -> void:
    if _smoke != null:
        _smoke.speed_scale = World.fx_speed();

# Smoke is grey for firewood and black for coal (the firewood in the stock burns first).
func update_smoke() -> void:
    if _smoke == null:
        return;
    var burning:bool = smoke_always or is_burning();
    if smoke_always and not _smoke.emitting:
        _smoke.preprocess = _smoke.lifetime;       # the title's chimneys already have plumes when it appears
    _smoke.emitting = burning;
    if burning:
        var coal:bool = fuel_coal >= fuel;
        var mat:StandardMaterial3D = _smoke.mesh.material as StandardMaterial3D;
        mat.albedo_color = Color(0.08, 0.08, 0.09, 0.85) if coal else Color(0.7, 0.7, 0.72, 0.75);

# A dark door on the south face of a house-shaped body, and for homes a pair of windows that light up while
# someone lives there. (Decoration only: citizens still walk to the building's edge.)
func _build_door(body:Vector2, h:float) -> void:
    var door_h:float = minf(1.3, h * 0.65);
    var door:BoxMesh = BoxMesh.new();
    door.size = Vector3(minf(0.8, body.x * 0.3), door_h, 0.1);
    _door = _add_mesh(door, _flat_mat(Color(0.27, 0.17, 0.1)), Vector3(0, door_h * 0.5, body.y * 0.5 + 0.02));
    if not def.has("beds") or body.x < 1.9:
        return;
    _window_mat = StandardMaterial3D.new();
    _window_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED;
    var pane:BoxMesh = BoxMesh.new();
    pane.size = Vector3(0.42, 0.42, 0.08);
    for sx in [-1.0, 1.0]:
        var w:MeshInstance3D = _add_mesh(pane, _window_mat, Vector3(sx * (body.x * 0.5 - 0.5), h * 0.62, body.y * 0.5 + 0.02));
        w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
        _windows.append(w);
    update_windows();

# Windows glow warm while the house is finished and has residents, and stay dark otherwise.
func update_windows() -> void:
    if _window_mat == null:
        return;
    var lit:bool = windows_lit_always or (state == State.COMPLETE and not residents.is_empty());
    _window_mat.albedo_color = Color(1.0, 0.82, 0.4) if lit else Color(0.16, 0.2, 0.26);

func _build_chimney(h:float) -> void:
    var box:BoxMesh = BoxMesh.new();
    var pitch:float = def.get("roof_pitch", 0.55);
    var top:float = h + h * pitch + 0.35;
    var base:float = h + h * pitch * 0.5;
    box.size = Vector3(0.4, top - base, 0.4);
    _chimney = _add_mesh(box, _flat_mat(Color(0.45, 0.32, 0.28)), Vector3(size.x * 0.22, (top + base) * 0.5, size.y * 0.15));
    _smoke = CPUParticles3D.new();
    var puff:SphereMesh = SphereMesh.new();
    puff.radius = 0.32;
    puff.height = 0.64;
    puff.radial_segments = 6;
    puff.rings = 3;
    var mat:StandardMaterial3D = StandardMaterial3D.new();
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA;
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED;
    mat.albedo_color = Color(0.7, 0.7, 0.72, 0.75);
    puff.material = mat;
    _smoke.mesh = puff;
    _smoke.amount = 14;
    _smoke.lifetime = 4.0;
    _smoke.direction = Vector3.UP;
    _smoke.spread = 12.0;
    _smoke.initial_velocity_min = 0.6;
    _smoke.initial_velocity_max = 0.9;
    _smoke.gravity = Vector3(0.25, 0.0, 0.0);       # a light breeze
    _smoke.scale_amount_min = 0.7;
    _smoke.scale_amount_max = 1.1;
    var grow:Curve = Curve.new();
    grow.add_point(Vector2(0.0, 0.5));
    grow.add_point(Vector2(1.0, 2.2));
    _smoke.scale_amount_curve = grow;
    var fade:Gradient = Gradient.new();
    fade.set_color(0, Color(1, 1, 1, 1));
    fade.set_color(1, Color(1, 1, 1, 0));
    _smoke.color_ramp = fade;
    _smoke.emitting = false;
    _smoke.speed_scale = World.fx_speed();
    GameClock.speed_changed.connect(_on_clock_speed);
    _smoke.position = _chimney.position + Vector3(0, box.size.y * 0.5, 0);
    _smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
    add_child(_smoke);

# --------------------------------
# Save and load. Reservations, incoming deliveries and who is working here are not saved: citizens
# start over without tasks, so those are all empty again.

func to_dict() -> Dictionary:
    return {
        "id": def_id, "origin": origin, "size": size, "state": state, "delivered": delivered.duplicate(),
        "work_done": work_done, "stored": stored.duplicate(), "forbidden": forbidden.duplicate(),
        "settings": settings.duplicate(), "fuel": fuel, "fuel_coal": fuel_coal, "inputs": inputs.duplicate(),
        "upgrades_done": upgrades_done.duplicate(), "upgrading": upgrading, "base_spent": _base_spent.duplicate(),
        "dig_progress": dig_progress.duplicate(), "spoil_acc": _spoil_acc.duplicate(), "burn_acc": _burn_acc,
        "expansion": expansion.duplicate(true), "cost_mult": cost_mult, "priority": priority, "reloc_from": world.buildings.find(relocating_from) if relocating_from != null else -1,
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
    fuel_coal = d.get("fuel_coal", 0);
    inputs = d["inputs"];
    upgrades_done = d["upgrades_done"];
    upgrading = d["upgrading"];
    _base_spent = d["base_spent"];
    dig_progress = d["dig_progress"];
    _spoil_acc = d["spoil_acc"];
    _burn_acc = d["burn_acc"];
    cost_mult = d.get("cost_mult", 1.0);
    expansion = d.get("expansion", {});
    priority = d.get("priority", PRIORITY_MEDIUM);
    _update_visual();
    update_site_label();

# --------------------------------
# Info

func info_text() -> String:
    var s:String = "";
    if state == State.CONSTRUCTION:
        s += "Under construction (%d%%)\n" % roundi(progress() * 100.0);
        s += "Priority: %s\n" % PRIORITY_NAMES[priority];
        if not world.is_site_clear(self):
            s += "Waiting for the site to be cleared\n";
        for item in cost():
            s += "  %s: %d / %d\n" % [Defs.item_name(item), delivered.get(item, 0), cost()[item]];
        if not has_all_materials():
            s += "Waiting for materials\n";
        if shortage_text() != "":
            s += "Not enough in storage: needs %s\n" % shortage_text();
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
    if def_id == &"town_hall":
        s += "Seeds: %s\n" % world.seeds.names();
    if def_id == &"town_hall" and not world.death_log.is_empty():
        s += "Recent deaths:\n";
        for entry in world.death_log.slice(-5):
            s += "  %s, age %d, %s (%s)\n" % [entry["name"], entry["age"], entry["cause"], entry["when"]];
    if upgrading != &"":
        if upgrading == Expansion.ID:
            s += "Expanding to %dx%d (%d%%)\n" % [expansion["rect"].size.x, expansion["rect"].size.y, roundi(progress() * 100.0)];
        else:
            s += "Upgrading: %s (%d%%)\n" % [def["upgrades"][upgrading]["name"], roundi(progress() * 100.0)];
        s += "Priority: %s\n" % PRIORITY_NAMES[priority];
        if shortage_text() != "":
            s += "Not enough in storage: needs %s\n" % shortage_text();
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
    _body_mat = SurfaceTextures.material(def.get("wall", &"planks"), def.get("color", Color.GRAY));
    _body_h = h;
    match shape:
        "silo":
            BuildingShapes.silo(self);
        "hall":
            BuildingShapes.hall(self);
            if def.has("fuel_capacity"):
                _build_chimney(h);
        "house":
            var box:BoxMesh = BoxMesh.new();
            box.size = Vector3(size.x - 0.5, h, size.y - 0.5);
            _body = _add_mesh(box, _body_mat, Vector3(0, h * 0.5, 0));
            var pitch:float = def.get("roof_pitch", 0.55);
            var prism:PrismMesh = PrismMesh.new();
            prism.size = Vector3(size.x - 0.1, h * pitch, size.y - 0.2);
            _roof = _add_mesh(prism, SurfaceTextures.material(&"shingle", def.get("roof", Color.DARK_RED)), Vector3(0, h + h * pitch * 0.5, 0));
            _build_door(Vector2(size.x - 0.5, size.y - 0.5), h);
            if def.has("fuel_capacity"):
                _build_chimney(h);
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
            _roof = _add_mesh(cap, SurfaceTextures.material(&"shingle", def.get("roof", Color.BROWN)), Vector3(-size.x * 0.2, h + h * 0.2, -size.y * 0.25));
            BuildingShapes.mine_extras(self);
        "graveyard":
            _fence = Fence.new(self, &"stone", 1);       # the ground itself is a terrain overlay (Terrain.Overlay.GRAVE)
            add_child(_fence);
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
            _fence = Fence.new(self, &"rope", 2);
            add_child(_fence);
            add_child(PileGoods.new(self));
        _:
            pass;
    if def.has("decor"):
        BuildingShapes.decorate(self, def["decor"]);

# BuildingShapes: the body (which rises while a site) and roof of a custom shape, and loose extras.
func set_body(mesh:MeshInstance3D, y0:float, height:float) -> void:
    _body = mesh;
    _body_y0 = y0;
    _body_h = height;

func set_roof(mesh:MeshInstance3D) -> void:
    _roof = mesh;

func add_decor(mesh:Mesh, mat:Material, at:Vector3, rot:Vector3 = Vector3.ZERO) -> MeshInstance3D:
    var mi:MeshInstance3D = _add_mesh(mesh, mat, at);
    mi.rotation = rot;
    _decor.append(mi);
    return mi;

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
    _body.position.y = _body_y0 + _body_h * 0.5 * sy;
    for d in _decor:
        d.visible = not building;
    if _roof != null:
        _roof.visible = not building;
    if _chimney != null:
        _chimney.visible = not building;
    if _door != null:
        _door.visible = not building;
    for w in _windows:
        w.visible = not building;
    update_windows();
    update_smoke();

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
