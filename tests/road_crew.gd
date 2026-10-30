# ----------------------------------------------------------------
# Road crew test
#     Stakes a short road and runs the game: citizens must lay it.
#     godot --headless --path . --fixed-fps 60 res://tests/road_crew.tscn
# ----------------------------------------------------------------
extends Node;

var world:World;
var cells:Array[Vector2i] = [];

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    var o:Vector2i = TestSite.near(world, Vector2i(-3, 6));
    for i in 6:
        var c:Vector2i = o + Vector2i(i, 0);
        if world.node_at[world.idx(c)] != null:
            world.remove_node(world.node_at[world.idx(c)]);
        if world.plan_road(c) == false and world.road_work.has(c):
            cells.append(c);
    Engine.time_scale = 8.0;
    GameClock.set_speed(3);

func _process(_d:float) -> void:
    var done:int = cells.filter(func(c:Vector2i) -> bool: return world.terrain.get_overlay(c) == Terrain.Overlay.ROAD).size();
    if done == cells.size() and not cells.is_empty():
        print("ROAD CREW PASS: %d cells laid" % done);
        get_tree().quit(0);
    elif GameClock.total_hours > 30.0 + 7.0 + 48.0:
        print("ROAD CREW FAIL: %d of %d cells laid" % [done, cells.size()]);
        get_tree().quit(1);
