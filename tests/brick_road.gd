# ----------------------------------------------------------------
# Brick road test
#     A brick road is a second kind of path: twice the walking-speed gain
#     of an earth path, one stone a tile carried from a store, listed
#     under the Paths tab. Checks the speed, the stone, the finished
#     cells and the save round trip.
#     godot --headless --path . --fixed-fps 60 res://tests/brick_road.tscn
# ----------------------------------------------------------------
extends Node;

var world:World;
var _fails:int = 0;
var cells:Array[Vector2i] = [];
var _stone_before:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    GameRules.reset();
    GameRules.illness = 0;
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    await get_tree().process_frame;
    var p:Pawn = world.pawns[0];
    var o:Vector2i = TestSite.near(world, Vector2i(-3, 6), Vector2i(8, 3));
    world.terrain.flatten_rect(Rect2i(o, Vector2i(8, 3)));
    world.terrain.set_overlay(o + Vector2i(0, 1), Terrain.Overlay.ROAD);
    world.terrain.set_overlay(o + Vector2i(1, 1), Terrain.Overlay.BRICK);
    Weather.snow_depth = 0.0;
    var gain_path:float = p.ground_speed(o + Vector2i(0, 1)) - 1.0;
    var gain_brick:float = p.ground_speed(o + Vector2i(1, 1)) - 1.0;
    _expect("a brick road doubles the path's speed gain (%.2f vs %.2f)" % [gain_brick, gain_path], is_equal_approx(gain_brick, gain_path * 2.0));
    _expect("it counts as paved", Terrain.is_paved(Terrain.Overlay.BRICK) and Terrain.is_paved(Terrain.Overlay.ROAD) and not Terrain.is_paved(Terrain.Overlay.TILLED));
    world.terrain.set_overlay(o + Vector2i(0, 1), Terrain.Overlay.NONE);
    world.terrain.set_overlay(o + Vector2i(1, 1), Terrain.Overlay.NONE);
    _expect("the build bar has a Paths tab holding the bridge", (Defs.BUILD_CATEGORIES[5][0] as String) == "Paths" and (Defs.BUILD_CATEGORIES[5][1] as Array).has(&"bridge"));
    for i in 5:
        var c:Vector2i = o + Vector2i(i, 0);
        if world.node_at[world.idx(c)] != null:
            world.remove_node(world.node_at[world.idx(c)]);
        world.plan_road(c, Terrain.Overlay.BRICK);
        if world.road_work.has(c):
            cells.append(c);
    _expect("cells are staked as brick roads needing stone", cells.size() == 5 and RoadWork.needs_stone(world, cells[0]));
    _expect("the colony has stone to lay them", Stock.available(&"stone") >= 5);
    # cancelling a paid cell gives its stone back
    var last:Vector2i = cells.pop_back();
    world.road_paid[last] = true;
    var store:Building = world.nearest_storage_with(&"stone", Vector3(o.x, 0.0, o.y));
    store.stored[&"stone"] = store.amount(&"stone") - 1;       # make room (a full store would put the stone on the ground)
    var stored:int = Stock.amount(&"stone");
    world.cancel_road(last);
    _expect("cancelling a paid cell returns the stone", Stock.amount(&"stone") == stored + 1 and not world.road_paid.has(last));
    _stone_before = Stock.amount(&"stone");
    var d:Dictionary = world.serialize();
    _expect("saved with the work", (d["road_kind"] as Array).size() >= cells.size() and d.has("road_paid"));
    Engine.time_scale = 8.0;
    GameClock.set_speed(3);

func _process(_d:float) -> void:
    if cells.is_empty():
        return;
    var done:int = cells.filter(func(c:Vector2i) -> bool: return world.terrain.get_overlay(c) == Terrain.Overlay.BRICK).size();
    if done == cells.size():
        var spent:int = _stone_before - Stock.amount(&"stone");
        _expect("one stone a tile was used (%d for %d)" % [spent, done], spent == done);
        print("BRICK ROAD %s: %d cells laid" % ["PASS" if _fails == 0 else "FAIL", done]);
        get_tree().quit(_fails);
    elif GameClock.total_hours > 30.0 + 7.0 + 72.0:
        print("BRICK ROAD FAIL: %d of %d cells laid" % [done, cells.size()]);
        get_tree().quit(1);

func _expect(what:String, ok:bool) -> void:
    if not ok:
        _fails += 1;
        print("FAIL: ", what);
    else:
        print("ok: ", what);
