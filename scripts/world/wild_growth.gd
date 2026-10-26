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

# Once a day: every mature wild-food node that is not in winter may seed a new one beside it.
static func spread_daily(world:World) -> void:
    var season:int = GameClock.season();
    if season == GameClock.Season.WINTER:
        return;
    var totals:Dictionary = {};
    for rn in world.nodes:
        if rn.is_forageable():
            totals[rn.kind] = totals.get(rn.kind, 0) + 1;
    for rn in world.nodes.duplicate():
        if not rn.is_forageable() or not rn.is_mature() or rn.removed:
            continue;
        var d:Dictionary = rn.def;
        if totals.get(rn.kind, 0) >= d.get("max_total", 100):
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
    return kind != &"mushroom" or trees_near(world, c) >= 1;
