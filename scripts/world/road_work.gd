# ----------------------------------------------------------------
# RoadWork
#     Staked roads and dug channels: planning, the work done on them,
#     finishing them, and the irrigation flow of a connected channel.
#     The state (road_work, road_kind, pending_roads...) stays on
#     World.
# ----------------------------------------------------------------
class_name RoadWork extends RefCounted;

static func can_road(world:World, c:Vector2i) -> bool:
    return world.terrain.in_bounds(c) and not world.terrain.is_water(c) and world.occupant[world.idx(c)] == null and world.node_at[world.idx(c)] == null;

# Whether the Road tool can work on this cell: not water and not under a building (a tree or rock is cleared first).
static func can_plan_road(world:World, c:Vector2i) -> bool:
    return world.terrain.in_bounds(c) and not world.terrain.is_water(c) and world.occupant[world.idx(c)] == null;

# Plans a road cell for the Road tool. Anything in the way is marked for clearing first; then the cell is staked out
# and citizens do ROAD_WORK_HOURS of work on it (no materials). Returns true if it is waiting on something to be cleared.
static func plan_road(world:World, c:Vector2i, kind:int = Terrain.Overlay.ROAD) -> bool:
    if not RoadWork.can_plan_road(world, c) or world.terrain.get_overlay(c) != Terrain.Overlay.NONE or world.road_work.has(c) or world.pending_roads.has(c):
        return false;
    world.road_kind[c] = kind;
    var rn:ResourceNode = world.node_at[world.idx(c)];
    if rn == null:
        RoadWork.stake_road(world, c);
        return false;
    world.mark_for_clearing(rn);
    world.pending_roads[c] = true;
    return true;

static func stake_road(world:World, c:Vector2i) -> void:
    if not RoadWork.can_road(world, c):
        return;
    world.road_work[c] = 0.0;
    world.terrain.set_overlay(c, Terrain.Overlay.ROAD_SITE);       # faintly worn ground until the road is done

static func cancel_road(world:World, c:Vector2i) -> void:
    world.pending_roads.erase(c);
    world.road_kind.erase(c);
    if world.road_work.erase(c):
        world.road_claimed.erase(c);
        world.terrain.set_overlay(c, Terrain.Overlay.NONE);

# Adds work to a staked road cell; true once the road is laid.
static func work_road(world:World, c:Vector2i, dh:float) -> bool:
    if not world.road_work.has(c):
        return true;
    world.road_work[c] += dh;
    var channel:bool = world.road_kind.get(c, Terrain.Overlay.ROAD) == Terrain.Overlay.CHANNEL;
    if world.road_work[c] < (Defs.CHANNEL_WORK_HOURS if channel else Defs.ROAD_WORK_HOURS):
        return false;
    world.road_work.erase(c);
    world.road_kind.erase(c);
    world.terrain.set_overlay(c, Terrain.Overlay.NONE);
    if channel:
        world.terrain.set_overlay(c, Terrain.Overlay.CHANNEL);
        RoadWork.update_irrigation(world);
    else:
        RoadWork.set_road(world, c, true);
    return true;

static func is_channel(world:World, c:Vector2i) -> bool:
    var o:int = world.terrain.get_overlay(c) if world.terrain.in_bounds(c) else Terrain.Overlay.NONE;
    return o == Terrain.Overlay.CHANNEL or o == Terrain.Overlay.CHANNEL_WET;

static func remove_channel(world:World, c:Vector2i) -> void:
    if RoadWork.is_channel(world, c):
        world.terrain.set_overlay(c, Terrain.Overlay.NONE);
        RoadWork.update_irrigation(world);

# Marks every channel cell reachable from water as flowing.
static func update_irrigation(world:World) -> void:
    var wet:Dictionary = {};
    var open:Array[Vector2i] = [];
    var dirs:Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)];
    var cells:Array[Vector2i] = [];
    for z in Terrain.SIZE:
        for x in Terrain.SIZE:
            if world.terrain.overlay[z * Terrain.SIZE + x] == Terrain.Overlay.CHANNEL or world.terrain.overlay[z * Terrain.SIZE + x] == Terrain.Overlay.CHANNEL_WET:
                cells.append(Vector2i(x, z));
    for c in cells:
        for d in dirs:
            if world.terrain.in_bounds(c + d) and world.terrain.is_water(c + d):
                wet[c] = true;
                open.append(c);
                break;
    while not open.is_empty():
        var c:Vector2i = open.pop_back();
        for d in dirs:
            var n:Vector2i = c + d;
            if not wet.has(n) and RoadWork.is_channel(world, n):
                wet[n] = true;
                open.append(n);
    for c in cells:
        world.terrain.set_overlay(c, Terrain.Overlay.CHANNEL_WET if wet.has(c) else Terrain.Overlay.CHANNEL);
    world.irrigation_version += 1;

static func set_road(world:World, c:Vector2i, on:bool) -> void:
    if on and not RoadWork.can_road(world, c):
        return;
    if not on and world.terrain.get_overlay(c) != Terrain.Overlay.ROAD:
        return;
    world.terrain.set_overlay(c, Terrain.Overlay.ROAD if on else Terrain.Overlay.NONE);
    world._refresh_nav(c);
