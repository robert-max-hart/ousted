# ----------------------------------------------------------------
# Fires
#     Fire in the colony: little campfires lit by cold citizens, and
#     wildfires that start from lightning (or, in a drought or heat wave,
#     of themselves), spread from cell to cell through trees, bushes,
#     crops, dry grass and wooden buildings, and burn down what they
#     reach. Rain, snow, wet ground, roads and water hold them back.
#     Citizens run from the flames and the idle ones fight them (see
#     FireTasks). Buildings have health: wooden ones burn down, stone
#     ones come through scorched. A citizen can be burned, but rarely.
#     The Map events slider "Wildfires" (GameRules.fires) scales how
#     often fires start and how fast they spread. Owned by the World
#     (world.fires); stepped hourly from World._on_hour.
# ----------------------------------------------------------------
class_name Fires extends RefCounted;

enum Kind { CAMP, WILD };

# How long a cell burns (game hours), by what is burning.
const CAMP_HOURS     :float = 8.0;
const TREE_HOURS     :float = 4.0;
const SHRUB_HOURS    :float = 1.5;
const GRASS_HOURS    :float = 1.2;
const CROP_HOURS     :float = 2.0;
# How easily a cell catches from a burning neighbour, an hour, in dry weather (before dryness and the rule scale it).
const TREE_CATCH     :float = 0.30;
const DEAD_CATCH     :float = 0.45;
const SHRUB_CATCH    :float = 0.22;
const GRASS_CATCH    :float = 0.05;
const CROP_CATCH     :float = 0.12;
const CAMP_SPREAD    :float = 0.4;       # a campfire spreads this share as readily as a wildfire
const DIAGONAL       :float = 0.6;       # and a diagonal neighbour this share as readily as a side one
# Buildings by wall (Defs "wall"): how easily they catch, how long they burn (hours) and the health they lose an hour.
const WALLS:Dictionary = {
    &"planks":  {"catch": 0.16, "hours": 6.0, "damage": 0.25},
    &"plaster": {"catch": 0.10, "hours": 6.0, "damage": 0.15},
    &"stone":   {"catch": 0.015, "hours": 4.0, "damage": 0.03},
};
const RAIN_QUENCH    :float = 0.6;       # the chance an hour that heavy rain (full intensity) puts out a cell's fire, scaled by the rain
const RAIN_MIN       :float = 0.25;      # rain lighter than this does nothing to a fire
const SOAK_HOURS     :float = 5.0;       # ground a bucket of water has been thrown on cannot catch for this long
const SOAK_RADIUS    :int = 1;
const DOUSE_RADIUS   :int = 0;           # a bucket puts out the fire in the cell aimed at (and soaks the ground round it)
const STRIKE_DAMAGE  :Dictionary = {&"planks": 0.22, &"plaster": 0.14, &"stone": 0.05};   # health a lightning bolt takes off a building by its wall
const STRIKE_TREE    :float = 0.5;       # chance a bolt that hits a tree blasts it into a dead one, fire or no fire
const STRIKE_CATCH   :float = 0.5;       # a lightning strike on a tree or shrub in dry weather
const STRIKE_GRASS   :float = 0.12;
const SPONTANEOUS_PER_DAY:float = 0.05;  # a drought or heat wave day starts a fire on its own this often
const SCORCH_DAYS    :float = 10.0;      # burnt ground fades back to green over this long
const PASTURE_LOSS   :float = 0.04;      # share of a pasture's animals lost for each of its cells that burns
const CHIMNEY_CHANCE :float = 0.00008;   # an hour, per wooden building with a fire lit in it (house fire or forge), at the Normal rule
const NAV_WEIGHT     :float = 15.0;      # how much citizens avoid a burning cell when they walk
const MAX_CAMPS      :int = 6;
const CAMP_WARM_RADIUS:float = 2.5;       # cells: sitting this close to a campfire warms like a heated house
const FLEE_RADIUS    :int = 4;           # citizens move away from a burning cell this close
const SAFE_RADIUS    :int = 7;           # ... until they are this far
# Burns (rare): next to a wildfire's flames, or standing in them.
const BURN_NEAR_CHANCE:float = 0.05;     # an hour beside the flames
const BURN_IN_CHANCE :float = 0.35;      # an hour standing on a burning cell
const BURN_DAMAGE    :float = 0.4;
const BURN_MEMORY_HOURS:float = 24.0;    # a citizen who dies of burns within this long of the last one

class FireCell extends RefCounted:
    var kind    :int = Fires.Kind.WILD;
    var left    :float = 1.0;               # hours it burns yet
    var building:Building = null;           # the building it is burning (its whole footprint burns)

var world:World;
var cells   :Dictionary = {};               # Vector2i -> FireCell
var scorch  :Dictionary = {};               # Vector2i -> game hour it burnt: the ground stays dark for SCORCH_DAYS
var soaked  :Dictionary = {};               # Vector2i -> game hour its soaking ends
var fighters:Dictionary = {};               # Pawn -> true: the citizens at the fire (FireTasks)
var chimney_chance:float = CHIMNEY_CHANCE;  # (a variable so a test can raise it)
var buckets :int = 0;                       # buckets of water thrown, for the record
var changed :bool = true;                   # the renderer redraws when this is set
var _had_wild:bool = false;

func _init(w:World) -> void:
    world = w;

# --------------------------------
# Questions

func active() -> bool:
    return not cells.is_empty();

# Whether anything beyond a campfire is burning.
func wild_burning() -> bool:
    for c in cells:
        if (cells[c] as FireCell).kind == Kind.WILD:
            return true;
    return false;

func is_burning(c:Vector2i) -> bool:
    return cells.has(c);

func is_wild_cell(c:Vector2i) -> bool:
    return cells.has(c) and (cells[c] as FireCell).kind == Kind.WILD;

func wild_cell_count() -> int:
    var n:int = 0;
    for c in cells:
        if (cells[c] as FireCell).kind == Kind.WILD:
            n += 1;
    return n;

func camp_count() -> int:
    var n:int = 0;
    for c in cells:
        if (cells[c] as FireCell).kind == Kind.CAMP:
            n += 1;
    return n;

# The nearest wildfire cell to c within `radius` cells (square), or NO_CELL.
const NO_CELL:Vector2i = Vector2i(-9999, -9999);

func nearest_wild(c:Vector2i, radius:int) -> Vector2i:
    var best:Vector2i = NO_CELL;
    var best_d:int = 1 << 30;
    for f in cells:
        if (cells[f] as FireCell).kind != Kind.WILD:
            continue;
        var d:int = maxi(absi(f.x - c.x), absi(f.y - c.y));
        if d <= radius and (d < best_d or (d == best_d and (f - c).length_squared() < (best - c).length_squared())):
            best = f;
            best_d = d;
    return best;

# Whether a campfire with some burn left is within `radius` cells (round) of the cell.
func camp_near(c:Vector2i, radius:float) -> bool:
    for f in cells:
        var fc:FireCell = cells[f];
        if fc.kind == Kind.CAMP and fc.left > 0.2 and Vector2(f - c).length() <= radius:
            return true;
    return false;

# The nearest campfire still burning, or NO_CELL.
func nearest_camp(c:Vector2i, radius:int) -> Vector2i:
    var best:Vector2i = NO_CELL;
    var best_d:float = INF;
    for f in cells:
        var fc:FireCell = cells[f];
        if fc.kind == Kind.CAMP and fc.left > 1.0:
            var d:float = Vector2(f - c).length();
            if d <= radius and d < best_d:
                best = f;
                best_d = d;
    return best;

# How hard the weather lets a fire run: 0 under snow, little in rain and on wet ground, more in a drought or heat wave.
func dryness() -> float:
    if Weather.snow_depth >= 0.3 or Weather.temperature < -2.0:
        return 0.0;
    var d:float = clampf(1.0 - world.wetness * 0.9, 0.1, 1.0) * (1.0 - 0.9 * Weather.intensity);
    if Weather.drought_days > 0:
        d *= 1.6;
    if Weather.snap_days > 0 and Weather.snap_dir > 0:
        d *= 1.3;
    return d;

# --------------------------------
# What burns

# How easily a cell catches (0 for water, roads and bare rock) and how long it burns, as {"catch", "hours"}; empty when it cannot burn.
func flammability(c:Vector2i) -> Dictionary:
    var t:Terrain = world.terrain;
    if not t.in_bounds(c) or t.is_water(c) or Terrain.is_paved(t.get_overlay(c)):
        return {};
    var i:int = world.idx(c);
    var b:Building = world.occupant[i];
    if b != null:
        if b is Field:
            var f:Field = b;
            var state:int = f.plot_state[f.plot_index(c)];
            return {"catch": CROP_CATCH if state == Field.Plot.PLANTED or state == Field.Plot.RIPE else GRASS_CATCH * 0.5, "hours": CROP_HOURS};
        if b is Pasture:
            return {"catch": GRASS_CATCH * 1.5, "hours": GRASS_HOURS};          # grass inside a fence: it burns like open ground and the animals suffer
        if not burns(b):
            return {};
        var w:Dictionary = WALLS[wall_of(b)];
        return {"catch": w["catch"], "hours": w["hours"]};
    var rn:ResourceNode = world.node_at[i];
    if rn != null:
        if rn.is_tree():
            return {"catch": DEAD_CATCH if rn.def.get("dead", false) else TREE_CATCH, "hours": TREE_HOURS};
        if rn.is_forageable():
            return {"catch": SHRUB_CATCH, "hours": SHRUB_HOURS};
        return {};                     # rock and ore
    if t.get_overlay(c) != Terrain.Overlay.NONE:
        return {};
    return {"catch": GRASS_CATCH, "hours": GRASS_HOURS};

# Whether a building can burn at all (bridges, graves, mines and wells cannot).
static func burns(b:Building) -> bool:
    return not (b.def.get("bridge", false) or b is Graveyard or b.def.get("water", false) and b.def.get("wall", &"planks") == &"stone" or b.def_id == &"mine");

static func wall_of(b:Building) -> StringName:
    var w:StringName = b.def.get("wall", &"planks");
    return w if WALLS.has(w) else &"planks";

# --------------------------------
# Starting and stopping fires

# Lights a campfire on a bare cell. Returns whether it burns.
func light_campfire(c:Vector2i) -> bool:
    if cells.has(c) or camp_count() >= MAX_CAMPS or not world.terrain.in_bounds(c) or world.terrain.is_water(c):
        return false;
    var i:int = world.idx(c);
    if world.occupant[i] != null or world.node_at[i] != null:
        return false;
    var fc:FireCell = FireCell.new();
    fc.kind = Kind.CAMP;
    fc.left = CAMP_HOURS;
    cells[c] = fc;
    changed = true;
    return true;

# Sets the cell alight as a wildfire if it can burn and is not soaked. A building catches as a whole. Returns whether it caught.
func ignite(c:Vector2i, kind:int = Kind.WILD) -> bool:
    if cells.has(c) or is_soaked(c):
        return false;
    var fl:Dictionary = flammability(c);
    if fl.is_empty():
        return false;
    var b:Building = world.occupant[world.idx(c)];
    if b != null and not b is Field and not b is Pasture:
        return _ignite_building(b);
    var fc:FireCell = FireCell.new();
    fc.kind = kind;
    fc.left = fl["hours"];
    cells[c] = fc;
    var rn:ResourceNode = world.node_at[world.idx(c)];
    if rn != null:
        rn.burning = true;
    changed = true;
    world._refresh_nav(c);
    _announce_start(c);
    return true;

func _ignite_building(b:Building) -> bool:
    if b.burning:
        return false;
    var w:Dictionary = WALLS[wall_of(b)];
    b.burning = true;
    var r:Rect2i = b.rect();
    for z in range(r.position.y, r.end.y):
        for x in range(r.position.x, r.end.x):
            var fc:FireCell = FireCell.new();
            fc.kind = Kind.WILD;
            fc.left = w["hours"];
            fc.building = b;
            cells[Vector2i(x, z)] = fc;
            world._refresh_nav(Vector2i(x, z));
    for p in b.residents:
        if p.indoors and is_same(p.shelter, b):
            p.go_outside();           # out of a burning house
            p.end_task(false);
    changed = true;
    world.notify("The %s has caught fire!" % b.display_name().to_lower());
    _announce_start(Vector2i(b.center_cell()));
    return true;

func is_soaked(c:Vector2i) -> bool:
    return soaked.has(c) and float(soaked[c]) > GameClock.total_hours;

# A bucket of water on the cell: the fire in it and the cells next to it goes out, and ground round it cannot catch for a while.
func douse(c:Vector2i) -> void:
    buckets += 1;
    for dz in range(-SOAK_RADIUS, SOAK_RADIUS + 1):
        for dx in range(-SOAK_RADIUS, SOAK_RADIUS + 1):
            var cc:Vector2i = c + Vector2i(dx, dz);
            if maxi(absi(dx), absi(dz)) <= DOUSE_RADIUS:
                _put_out(cc);
            soaked[cc] = GameClock.total_hours + SOAK_HOURS;
    changed = true;

func _put_out(c:Vector2i) -> void:
    if not cells.has(c):
        return;
    var fc:FireCell = cells[c];
    if fc.building != null:
        fc.left -= 2.0;                # a bucket takes a couple of hours off a burning building
        if fc.left <= 0.0:
            _extinguish_building(fc.building);
        return;
    _end_cell(c, false);

# Lightning strikes the cell: a tree, shrub or building may catch, more readily when everything is dry.
func strike(c:Vector2i) -> void:
    if not world.terrain.in_bounds(c):
        return;
    _strike_damage(c);
    var share:float = GameRules.fire_share();
    if share <= 0.0:
        return;
    var fl:Dictionary = flammability(c);
    if fl.is_empty():
        return;
    var base:float = STRIKE_GRASS if fl["catch"] <= GRASS_CATCH else (STRIKE_CATCH if fl["catch"] >= SHRUB_CATCH else fl["catch"] * 1.5);
    if world.rng.randf() < minf(1.0, base * dryness() * share * 1.6):
        ignite(c);

# A bolt hurts what it hits whether or not it starts a fire: a building loses health (and burns down if that is the end of it), a tree
# may be blasted into a dead one.
func _strike_damage(c:Vector2i) -> void:
    var i:int = world.idx(c);
    var b:Building = world.occupant[i];
    if b != null and not b is Field and not b is Pasture and b.is_complete() and not b.def.get("bridge", false) and not b is Graveyard:
        b.fire_hit(STRIKE_DAMAGE[wall_of(b)]);
        world.notify("Lightning struck the %s." % b.display_name().to_lower());
        if b.health <= 0.0:
            _destroy_building(b);
        return;
    var rn:ResourceNode = world.node_at[i];
    if rn != null and rn.is_tree() and not rn.def.get("dead", false) and rn.is_mature() and world.rng.randf() < STRIKE_TREE:
        world.remove_node(rn);
        world.add_node(&"dead", c);

# --------------------------------
# Time

# Once an hour: burn down, spread, hurt buildings and the people beside the flames.
func on_hour() -> void:
    for p in fighters.keys():
        if not is_instance_valid(p) or p.removed:
            fighters.erase(p);
    for c in scorch.keys():
        if GameClock.total_hours - float(scorch[c]) > SCORCH_DAYS * GameClock.HOURS_PER_DAY:
            scorch.erase(c);
            changed = true;
    _chimney_fires();
    if cells.is_empty():
        _note_end();
        return;
    _rain_on_fires();
    if cells.is_empty():
        _note_end();
        return;
    var spread_rate:float = clampf(GameRules.fire_share(), 0.0, 2.0) * dryness();
    var burning:Array = cells.keys();
    var started:Array[Vector2i] = [];
    for c in burning:
        var fc:FireCell = cells[c];
        if fc.kind == Kind.WILD or camp_may_spread():
            var scale:float = spread_rate * (CAMP_SPREAD if fc.kind == Kind.CAMP else 1.0);
            if scale > 0.0:
                for dz in range(-1, 2):
                    for dx in range(-1, 2):
                        if dx == 0 and dz == 0:
                            continue;
                        var n:Vector2i = c + Vector2i(dx, dz);
                        if cells.has(n) or is_soaked(n):
                            continue;
                        var fl:Dictionary = flammability(n);
                        if fl.is_empty():
                            continue;
                        var chance:float = fl["catch"] * scale * (DIAGONAL if dx != 0 and dz != 0 else 1.0);
                        if world.rng.randf() < chance:
                            started.append(n);
    for n in started:
        ignite(n);
    _burn_buildings();
    for c in cells.keys():
        var fc:FireCell = cells[c];
        if fc.building != null:
            continue;
        fc.left -= 1.0;
        if fc.left <= 0.0:
            _end_cell(c, true);
    _hurt_citizens();
    changed = true;
    world.renderer.mark_dirty();
    _note_end();

# Rain (not snow) puts fires out: each open cell has a chance an hour that grows with the rain, so a storm in a drought stops a forest
# fire in a few hours and a drizzle only helps a little. A burning building loses more of its fire an hour (see _burn_buildings).
func _rain_on_fires() -> void:
    var rain:float = Weather.intensity;
    if rain < RAIN_MIN or Weather.is_snowing():
        return;
    for c in cells.keys():
        var fc:FireCell = cells.get(c);
        if fc == null or fc.building != null:
            continue;
        if world.rng.randf() < RAIN_QUENCH * rain:
            _end_cell(c, false);
            soaked[c] = GameClock.total_hours + SOAK_HOURS * 0.5;       # (the ground is wet now)

func camp_may_spread() -> bool:
    return GameRules.fire_share() > 0.0;

# A fire lit in a wooden building (a hearth, a forge or a kiln at work) very rarely gets away from it.
func _chimney_fires() -> void:
    var share:float = GameRules.fire_share();
    if share <= 0.0:
        return;
    for b in world.buildings:
        if b.burning or not b.is_complete() or not burns(b) or b.def.get("shack", false):
            continue;
        var fired:bool = b.is_burning() or (b.def.get("decor", "") in ["forge", "kiln", "still"] and _worked(b));
        if not fired:
            continue;
        var wall:float = WALLS[wall_of(b)]["catch"] / WALLS[&"planks"]["catch"];
        if world.rng.randf() < chimney_chance * share * wall:
            ignite(b.rect().position);

func _worked(b:Building) -> bool:
    for p in world.pawns:
        if p.task != null and is_same(p.task.workplace, b):
            return true;
    return false;

# Burning buildings lose health; one that is gone burns down, one whose fire has run its course is left scorched.
func _burn_buildings() -> void:
    var done:Dictionary = {};
    for c in cells.keys():
        var fc:FireCell = cells.get(c);
        if fc == null or fc.building == null or done.has(fc.building):
            continue;
        var b:Building = fc.building;
        done[b] = true;
        if not World.alive(b):
            _extinguish_building(b);
            continue;
        var rain:float = 0.0 if Weather.is_snowing() or Weather.intensity < RAIN_MIN else Weather.intensity;
        b.fire_hit(WALLS[wall_of(b)]["damage"] * (1.0 - 0.5 * rain));
        fc.left -= 1.0 + 2.0 * rain;
        for cc in cells.keys():
            if cells[cc].building == b:
                cells[cc].left = fc.left;
        if b.health <= 0.0:
            _destroy_building(b);
        elif fc.left <= 0.0:
            _extinguish_building(b);

func _extinguish_building(b:Building) -> void:
    b.burning = false;
    for c in cells.keys():
        if (cells[c] as FireCell).building == b:
            cells.erase(c);
            scorch[c] = GameClock.total_hours;
            world._refresh_nav(c);
    changed = true;

func _destroy_building(b:Building) -> void:
    var name:String = b.display_name().to_lower();
    _extinguish_building(b);
    b.stored.clear();                  # whatever was inside burned
    b.out_reserved.clear();
    b.in_reserved = 0;
    for item in b.inputs.keys():
        b.inputs[item] = 0;
    b.fuel = 0;
    world.remove_building(b, false);
    world.notify("The %s burned down." % name);

# A cell's fire is over (`burnt`: it ran its course; otherwise it was put out): what it was burning is spent.
func _end_cell(c:Vector2i, burnt:bool) -> void:
    var fc:FireCell = cells.get(c);
    if fc == null:
        return;
    cells.erase(c);
    changed = true;
    world._refresh_nav(c);
    var i:int = world.idx(c);
    var rn:ResourceNode = world.node_at[i];
    if rn != null:
        rn.burning = false;
    if not burnt or fc.kind == Kind.CAMP:
        return;
    scorch[c] = GameClock.total_hours;
    if rn != null:
        world.remove_node(rn);         # trees and shrubs are gone
        return;
    var b:Building = world.occupant[i];
    if b is Pasture:
        var pa:Pasture = b;
        var lost:int = ceili(pa.animals * PASTURE_LOSS);
        if lost > 0:
            pa.animals -= lost;
            if world.rng.randf() < 0.3:
                world.notify("%d %s died in the fire at the %s." % [lost, pa.animal()["name"].to_lower(), pa.display_name().to_lower()]);
        return;
    if b is Field:
        var f:Field = b;
        var p:int = f.plot_index(c);
        if f.plot_state[p] == Field.Plot.PLANTED or f.plot_state[p] == Field.Plot.RIPE:
            f.plot_state[p] = Field.Plot.DEAD;     # the crop burned
            f.growth[p] = 0.0;
            f._visual_dirty = true;

# Citizens next to a wildfire's flames may be burned (rarely), and standing in them is worse.
func _hurt_citizens() -> void:
    if not wild_burning():
        return;
    for p in world.pawns.duplicate():
        if p.removed or p.indoors:
            continue;                  # (indoors is safe: a burning building puts its people out first)
        var c:Vector2i = p.cell();
        var here:FireCell = cells.get(c);
        var in_flames:bool = here != null and here.kind == Kind.WILD and not p.indoors;
        if not in_flames and nearest_wild(c, 1) == NO_CELL:
            continue;
        if world.rng.randf() < (BURN_IN_CHANCE if in_flames else BURN_NEAR_CHANCE):
            p.health = maxf(0.0, p.health - BURN_DAMAGE);
            p.burned_until = GameClock.total_hours + BURN_MEMORY_HOURS;
            if world.rng.randf() < 0.5:
                world.notify("%s was burned by the fire." % p.first_name);

# Daily: in a drought or heat wave something may catch on its own.
func on_day() -> void:
    var share:float = GameRules.fire_share();
    if share <= 0.0 or not (Weather.drought_days > 0 or (Weather.snap_days > 0 and Weather.snap_dir > 0)) or Weather.temperature < 18.0:
        return;
    if world.rng.randf() >= SPONTANEOUS_PER_DAY * share:
        return;
    var trees:Array = world.nodes.filter(func(rn:ResourceNode) -> bool: return rn.is_tree() and not rn.removed);
    if trees.is_empty():
        return;
    ignite((trees[world.rng.randi_range(0, trees.size() - 1)] as ResourceNode).cell);

# --------------------------------
# Messages

func _announce_start(c:Vector2i) -> void:
    if not _had_wild and wild_burning():
        _had_wild = true;
        world.notify("A fire has broken out!");
        if not world.is_backdrop:
            Sfx.ui(&"fire_alarm");

func _note_end() -> void:
    if _had_wild and not wild_burning():
        _had_wild = false;
        fighters.clear();
        world.notify("The fire is out.");

# --------------------------------
# Saving

func to_array() -> Array:
    var out:Array = [];
    for c in cells:
        var fc:FireCell = cells[c];
        out.append([c, fc.kind, fc.left]);
    for c in scorch:
        out.append([c, -1, float(scorch[c])]);          # (kind -1: burnt ground, with the hour it burnt)
    return out;

# Puts the saved fires back (call after the nodes and buildings exist).
func restore(a:Array) -> void:
    cells.clear();
    scorch.clear();
    for e in a:
        var c:Vector2i = e[0];
        if int(e[1]) < 0:
            scorch[c] = float(e[2]);
            continue;
        var fc:FireCell = FireCell.new();
        fc.kind = int(e[1]);
        fc.left = float(e[2]);
        var b:Building = world.occupant[world.idx(c)];
        if b != null and not b is Field and not b is Pasture and fc.kind == Kind.WILD:
            fc.building = b;
            b.burning = true;
        var rn:ResourceNode = world.node_at[world.idx(c)];
        if rn != null:
            rn.burning = true;
        cells[c] = fc;
        world._refresh_nav(c);
    _had_wild = wild_burning();
    changed = true;
