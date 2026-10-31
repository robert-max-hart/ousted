# ----------------------------------------------------------------
# TestSite
#     Where tests may put things. A world's map changes every run (a
#     river now runs through it, close to the start), so a fixed offset
#     from the Town Hall can land in the water or on a hill. These find
#     dry, gentle, empty ground near the offset a test would like.
# ----------------------------------------------------------------
class_name TestSite extends RefCounted;

const FREE_AREA:Vector2i = Vector2i(26, 14);       # what `near` keeps clear: from 3 cells before the origin, this far on

# Where the colony began: the Town Hall's origin, or the first building's if it started without one.
static func anchor(world:World) -> Vector2i:
    return (world.town_hall if world.town_hall != null else world.start_building).origin;

# The origin of a free area (FREE_AREA, or `area`) near Town Hall origin + prefer; the old fixed spot if nothing is free.
static func near(world:World, prefer:Vector2i, area:Vector2i = FREE_AREA) -> Vector2i:
    var home:Vector2i = TestSite.anchor(world) + prefer;
    for r in range(0, 48, 2):
        for dz in range(-r, r + 1, 2):
            for dx in range(-r, r + 1, 2):
                if maxi(absi(dx), absi(dz)) != r:
                    continue;
                var c:Vector2i = home + Vector2i(dx, dz);
                if _free(world, Rect2i(c - Vector2i(3, 3), area)):
                    return c;
    return home;

# The origin for a building of `size` near Town Hall origin + prefer, with a free cell around it.
static func spot(world:World, size:Vector2i, prefer:Vector2i) -> Vector2i:
    var home:Vector2i = TestSite.anchor(world) + prefer;
    for r in range(0, 48):
        for dz in range(-r, r + 1):
            for dx in range(-r, r + 1):
                if maxi(absi(dx), absi(dz)) != r:
                    continue;
                var c:Vector2i = home + Vector2i(dx, dz);
                if _free(world, Rect2i(c - Vector2i.ONE, size + Vector2i(2, 2))):
                    return c;
    return home;

static func _free(world:World, r:Rect2i) -> bool:
    var t:Terrain = world.terrain;
    if not Rect2i(2, 2, Terrain.SIZE - 4, Terrain.SIZE - 4).encloses(r):
        return false;
    for z in range(r.position.y, r.end.y):
        for x in range(r.position.x, r.end.x):
            var c:Vector2i = Vector2i(x, z);
            if t.is_water(c) or t.cell_height(c) < Terrain.WATER_LEVEL + 0.5 or t.cell_slope(c) > 1.3 or world.occupant[world.idx(c)] != null:
                return false;
    return true;
