# ----------------------------------------------------------------
# River screenshot
#     A high view of the whole map (the river and the start beside it),
#     then a close view of the first ford. Windowed.
#     godot --path . res://tests/river_shot.tscn -- <out_dir>
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
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    world.hud.visible = false;

func _process(_delta:float) -> void:
    _frame += 1;
    var rig:Node = world.camera_rig;
    if _frame == 2:
        rig.focus_on(Vector3(Terrain.SIZE * 0.5, 0.0, Terrain.SIZE * 0.5));
        rig._distance = 190.0;
        rig._target_distance = 190.0;
    if _frame == 12:
        get_viewport().get_texture().get_image().save_png(_out.path_join("river_map.png"));
        var f:Vector2 = world.terrain.river_fords[0] if not world.terrain.river_fords.is_empty() else Vector2(80, 80);
        rig.focus_on(Vector3(f.x, 0.0, f.y));
        rig._distance = 34.0;
        rig._target_distance = 34.0;
    if _frame == 24:
        get_viewport().get_texture().get_image().save_png(_out.path_join("river_ford.png"));
        print("start at ", world.town_hall.origin, " river distance ", world.terrain.river_distance(world.town_hall.origin));
        get_tree().quit();
