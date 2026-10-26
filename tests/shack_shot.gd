# ----------------------------------------------------------------
# Shack and Town Hall screenshot
#     A shack, the Town Hall inspector and a house inspector with Relocate.
#     godot --path . res://tests/shack_shot.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

var world:World;
var shack:Building;
var _frame:int = 0;
var _out:String = "user://";

func _ready() -> void:
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0:
        _out = args[0];
    SaveGame.autosave_enabled = false;
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    GameClock.total_hours = 11.0;
    var th:Building = world.town_hall;
    shack = world.place_building(&"shack", th.origin + Vector2i(-6, 0), Vector2i(2, 2), true);
    world.pawns[1].homeless_hours = 80.0;
    world.tools.select(th);
    world.camera_rig.focus_on(th.position);
    world.camera_rig._distance = 16.0;
    world.camera_rig._target_distance = 16.0;

func _process(_delta:float) -> void:
    _frame += 1;
    if _frame == 60:
        _shot("shack_01.png");
        world.tools.select(shack);
    elif _frame == 80:
        _shot("shack_02.png");
        world.tools.select(world.pawns[1]);
    elif _frame == 100:
        _shot("shack_03.png");
        get_tree().quit();

func _shot(file:String) -> void:
    get_viewport().get_texture().get_image().save_png(_out.path_join(file));
    print("saved ", file);
