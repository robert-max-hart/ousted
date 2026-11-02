# ----------------------------------------------------------------
# Road edge shot (windowed): a dirt road, a bend and a junction on open
# ground beside the Town Hall, to look at the dithered edge.
#     godot --path . res://tests/road_edge_shot.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

var world:World;
var _out:String = "user://";
var _frame:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0:
        _out = args[0];
    GameClock.reset();
    GameClock.total_hours = float(2 * GameClock.HOURS_PER_DAY + 12);
    Weather.reset();
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    world.world_seed = 4242;
    add_child(world);
    GameClock.set_speed(0);
    world.hud.visible = false;

func _process(_delta:float) -> void:
    _frame += 1;
    if _frame == 2:
        var o:Vector2i = TestSite.near(world, Vector2i(8, 8), Vector2i(26, 18));
        for i in 14:
            world.terrain.set_overlay(o + Vector2i(i, 0), Terrain.Overlay.ROAD);
        for i in 8:
            world.terrain.set_overlay(o + Vector2i(13, i), Terrain.Overlay.ROAD);
        for i in 6:
            world.terrain.set_overlay(o + Vector2i(6, 1 + i), Terrain.Overlay.ROAD);
        for i in 5:
            world.terrain.set_overlay(o + Vector2i(14 + i, 4 + i), Terrain.Overlay.ROAD);       # a diagonal
        var rig:Node = world.camera_rig;
        rig.focus_on(Vector3(o.x + 3.0, 0.0, o.y + 0.5));
        rig._distance = 11.0;
        rig._target_distance = 11.0;
        rig._pitch = deg_to_rad(-70.0);
    if _frame == 14:
        get_viewport().get_texture().get_image().save_png(_out.path_join("road_edge.png"));
        get_tree().quit();
