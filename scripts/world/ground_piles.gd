# ----------------------------------------------------------------
# GroundPiles
#     Loose piles of goods on the ground (what no store had room for,
#     or a dead citizen carried): finding one, dropping goods,
#     removing one.
# ----------------------------------------------------------------
class_name GroundPiles extends RefCounted;

static func pile_at(world:World, c:Vector2i) -> GroundPile:
    for pl in world.piles:
        if pl.cell == c:
            return pl;
    return null;

# Leaves n units on the ground at the nearest suitable cell (merging with a pile of the same item).
static func drop_pile(world:World, item:StringName, n:int, near:Vector2i) -> void:
    if n <= 0:
        return;
    for radius in 6:
        for dz in range(-radius, radius + 1):
            for dx in range(-radius, radius + 1):
                if maxi(absi(dx), absi(dz)) != radius:
                    continue;
                var c:Vector2i = near + Vector2i(dx, dz);
                if not world.terrain.in_bounds(c) or world.terrain.is_water(c) or world.occupant[world.idx(c)] != null or world.node_at[world.idx(c)] != null:
                    continue;
                var existing:GroundPile = GroundPiles.pile_at(world, c);
                if existing != null:
                    if existing.item == item:
                        existing.add(n);
                        return;
                    continue;
                var pl:GroundPile = GroundPile.new();
                pl.setup(world, item, n, c);
                world._entities.add_child(pl);
                world.piles.append(pl);
                return;
    world.notify("No room to put down %d %s." % [n, Defs.item_name(item)]);

static func remove_pile(world:World, pl:GroundPile) -> void:
    if pl.removed:
        return;
    # hidden now; the collecting task frees it when it ends (see JobManager._collect_task)
    pl.removed = true;
    pl.visible = false;
    world.piles.erase(pl);
