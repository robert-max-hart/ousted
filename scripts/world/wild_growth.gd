# ----------------------------------------------------------------
# WildGrowth
#     Wild food (berry bushes, mushrooms, hazel groves) slowly seeds
#     new patches nearby, faster close to trees. Foragers with a
#     Cultivation upgrade sow patches by hand through the same rules.
#     Static functions that take the World, so nothing holds a
#     reference back to it.
# ----------------------------------------------------------------
class_name WildGrowth extends RefCounted;

const TREE_BONUS_RANGE  :int = 3;       # trees within this many cells speed spreading up
const TREE_BONUS        :float = 0.25;  # each adds this share of the base chance...
const TREE_BONUS_CAP    :int = 8;       # ...up to this many trees

# The caps in Defs were set for the Large map: other sizes scale them by area.
static func area_share() -> float:
    return float(Terrain.SIZE * Terrain.SIZE) / float(Terrain.DEFAULT_SIZE * Terrain.DEFAULT_SIZE);

# Once a day: every mature wild-food node that is not in winter may seed a new one beside it.
static func spread_daily(world:World) -> void:
    if Climate.is_dormant():
        return;
    var totals:Dictionary = {};
    for rn in world.nodes:
        if rn.is_forageable():
            totals[rn.kind] = totals.get(rn.kind, 0) + 1;
    for rn in world.nodes.duplicate():
        if not rn.is_forageable() or not rn.is_mature() or rn.removed:
            continue;
        var d:Dictionary = rn.def;
        if not Climate.has_wild(rn.kind):
            continue;                       # (a food that does not belong on this map does not spread)
        if totals.get(rn.kind, 0) >= d.get("max_total", 100) * area_share():
            continue;
        var chance:float = d.get("spread_chance", 0.0);
        if chance <= 0.0 or world.rng.randf() >= chance * (1.0 + TREE_BONUS * mini(trees_near(world, rn.cell), TREE_BONUS_CAP)):
            continue;
        var c:Vector2i = rn.cell + Vector2i(world.rng.randi_range(-2, 2), world.rng.randi_range(-2, 2));
        if can_grow(world, c, rn.kind):
            world.sow_wild(rn.kind, c);
            totals[rn.kind] = totals.get(rn.kind, 0) + 1;

static func trees_near(world:World, c:Vector2i, r:int = TREE_BONUS_RANGE) -> int:
    var n:int = 0;
    for dz in range(-r, r + 1):
        for dx in range(-r, r + 1):
            var cc:Vector2i = c + Vector2i(dx, dz);
            if world.terrain.in_bounds(cc):
                var rn:ResourceNode = world.node_at[world.idx(cc)];
                if rn != null and rn.is_tree():
                    n += 1;
    return n;

# Free, dry, gentle ground that is not road, field or building. Mushrooms only grow among trees.
static func can_grow(world:World, c:Vector2i, kind:StringName) -> bool:
    var t:Terrain = world.terrain;
    if not t.in_bounds(c) or t.is_water(c) or t.cell_height(c) < Terrain.WATER_LEVEL + 0.4:
        return false;
    var i:int = world.idx(c);
    if world.occupant[i] != null or world.node_at[i] != null or t.get_overlay(c) != Terrain.Overlay.NONE or world.pending_roads.has(c):
        return false;
    if t.cell_slope(c) > 1.0 or world.planting.has(c):
        return false;
    if not Climate.has_wild(kind):
        return false;
    if kind == &"date" and not near_water(world, c, DATE_WATER):
        return false;
    return kind != &"mushroom" or trees_near(world, c) >= 1;

const DATE_WATER:int = 6;               # date palms grow within this many cells of water

static func near_water(world:World, c:Vector2i, r:int) -> bool:
    for dz in range(-r, r + 1, 2):
        for dx in range(-r, r + 1, 2):
            var cc:Vector2i = c + Vector2i(dx, dz);
            if world.terrain.in_bounds(cc) and world.terrain.is_water(cc):
                return true;
    return false;

# --------------------------------
# Where wild foods grow at the start of a game (World._spawn_nature): how much of each belongs to a climate is Climate "wild".

# kind: forest noise range, chance a free cell holds one, flatness, and whether it wants trees or water close. The old four are the
# temperate amounts (their own rolls are in World._spawn_nature); this table makes up the difference where a climate has more.
const SPAWN:Dictionary = {
    &"bush":     {"f": Vector2(-0.1, 0.15), "chance": 0.025, "slope": 1.0},
    &"mushroom": {"f": Vector2(0.1, 0.4), "chance": 0.035, "slope": 1.0, "trees": true},
    &"herb":     {"f": Vector2(-0.1, 0.3), "chance": 0.028, "slope": 1.0},
    &"hazel":    {"f": Vector2(-0.3, -0.1), "chance": 0.04, "slope": 1.0},
    &"lingon":   {"f": Vector2(-0.3, 0.25), "chance": 0.03, "slope": 1.0},
    &"cactus":   {"f": Vector2(-1.0, 1.0), "chance": 0.012, "slope": 1.0},
    &"date":     {"f": Vector2(-1.0, 1.0), "chance": 0.04, "slope": 1.0, "water": DATE_WATER},
    &"banana":   {"f": Vector2(-0.2, 0.4), "chance": 0.03, "slope": 1.0},
    &"coconut":  {"f": Vector2(-1.0, 1.0), "chance": 0.05, "slope": 1.0, "water": 10},
};
const OLD_KINDS:Array[StringName] = [&"bush", &"mushroom", &"hazel", &"herb"];

# Sows the foods a climate has more of than the temperate amount, and the ones only it has. `forest` is the map's forest noise.
static func spawn_extra(world:World, forest:FastNoiseLite, rng:RandomNumberGenerator) -> void:
    var wild:Dictionary = Climate.data().get("wild", {});
    for kind in SPAWN:
        var share:float = float(wild.get(kind, 0.0)) - (1.0 if OLD_KINDS.has(kind) else 0.0);
        if share <= 0.0:
            continue;
        var spec:Dictionary = SPAWN[kind];
        for z in Terrain.SIZE:
            for x in Terrain.SIZE:
                var c:Vector2i = Vector2i(x, z);
                var f:float = forest.get_noise_2d(x, z);
                if f < spec["f"].x or f > spec["f"].y:
                    continue;
                var chance:float = spec["chance"] * share;
                if spec.has("water") and not near_water(world, c, int(spec["water"])):
                    if kind == &"date":
                        continue;                                    # (dates only grow by the water)
                    chance *= 0.15;                                  # (a coconut palm now and then inland)
                if rng.randf() >= chance or not _spawn_cell_free(world, c, spec["slope"]):
                    continue;
                if spec.get("trees", false) and trees_near(world, c) < 1:
                    continue;
                world.add_node(kind, c);

static func _spawn_cell_free(world:World, c:Vector2i, max_slope:float) -> bool:
    var t:Terrain = world.terrain;
    if t.is_water(c) or t.cell_height(c) < Terrain.WATER_LEVEL + 0.4 or t.cell_slope(c) > max_slope:
        return false;
    var i:int = world.idx(c);
    return world.occupant[i] == null and world.node_at[i] == null;
