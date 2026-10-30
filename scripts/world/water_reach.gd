# ----------------------------------------------------------------
# WaterReach
#     The water-reach map behind the Water overlay: the distance from
#     every cell to the nearest water source (open water, a well, the
#     Town Hall).
# ----------------------------------------------------------------
class_name WaterReach extends RefCounted;

# Per cell, the distance (cells, close to straight-line) to the nearest water source: open water, or the middle of a finished
# well or Town Hall (the same sources Building.has_water looks for). Worked out with two sweeps over the map, kept until a
# well appears or goes.
static func water_reach(world:World) -> PackedFloat32Array:
    if not world._water_reach_dirty and not world._water_reach.is_empty():
        return world._water_reach;
    world._water_reach_dirty = false;
    var n:int = Terrain.SIZE;
    var d:PackedFloat32Array = PackedFloat32Array();
    d.resize(n * n);
    d.fill(999.0);
    for z in n:
        for x in n:
            if world.terrain.cell_height(Vector2i(x, z)) < Terrain.WATER_LEVEL:
                d[z * n + x] = 0.0;
    for b in world.buildings:
        if b.def.get("water", false) and b.is_complete():
            var c:Vector2i = Vector2i(b.center_cell());
            d[clampi(c.y, 0, n - 1) * n + clampi(c.x, 0, n - 1)] = 0.0;
    const D:float = 1.4142;
    for z in n:
        for x in n:
            var i:int = z * n + x;
            var best:float = d[i];
            if x > 0:
                best = minf(best, d[i - 1] + 1.0);
            if z > 0:
                best = minf(best, d[i - n] + 1.0);
                if x > 0:
                    best = minf(best, d[i - n - 1] + D);
                if x < n - 1:
                    best = minf(best, d[i - n + 1] + D);
            d[i] = best;
    for z in range(n - 1, -1, -1):
        for x in range(n - 1, -1, -1):
            var i:int = z * n + x;
            var best:float = d[i];
            if x < n - 1:
                best = minf(best, d[i + 1] + 1.0);
            if z < n - 1:
                best = minf(best, d[i + n] + 1.0);
                if x < n - 1:
                    best = minf(best, d[i + n + 1] + D);
                if x > 0:
                    best = minf(best, d[i + n - 1] + D);
            d[i] = best;
    world._water_reach = d;
    return d;

# A well or Town Hall appeared or went: the reach map and the overlay (when shown) are stale.
static func water_sources_changed(world:World) -> void:
    world._water_reach_dirty = true;
    if world.terrain != null and world.terrain.water_view:
        world.terrain.mark_all_dirty();
