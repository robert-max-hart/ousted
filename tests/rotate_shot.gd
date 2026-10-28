# ----------------------------------------------------------------
# Rotation and staked-road screenshot
#     Four houses turned 0 to 3 quarter turns, a finished road beside
#     a staked one.
#     godot --path . res://tests/rotate_shot.tscn -- <out_dir>
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
    Defs.difficulty = &"easy";
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    var o:Vector2i = world.town_hall.origin + Vector2i(8, -10);
    for rn in world.nodes.duplicate():
        if Rect2i(o - Vector2i(3, 3), Vector2i(26, 20)).has_point(rn.cell):
            world.remove_node(rn);
    for i in 4:
        var size:Vector2i = Vector2i(3, 4) if i % 2 == 1 else Vector2i(4, 3);
        world.place_building(&"house", o + Vector2i(i * 5, 0), size, true, false, i);
    for x in 12:
        world.set_road(o + Vector2i(x, 7), true);
        world.stake_road(o + Vector2i(x, 9));
    world.camera_rig.focus_on(Vector3(o.x + 8, 0, o.y + 4));
    world.camera_rig._distance = 20.0;
    world.camera_rig._target_distance = 20.0;

func _process(_delta:float) -> void:
    _frame += 1;
    if _frame == 30:
        get_viewport().get_texture().get_image().save_png(_out.path_join("rotate.png"));
        get_tree().quit();
