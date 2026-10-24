# ----------------------------------------------------------------
# Save/load screenshot test
#     Windowed: takes a screenshot, saves, loads, takes another so the two can be compared by eye.
#     godot --path . res://tests/save_load_shot.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

var _out:String = "user://";
var _frame:int = 0;
var _world:World;

func _ready() -> void:
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0:
        _out = args[0];
    SaveGame.autosave_enabled = false;
    _world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(_world);
    var th:Building = _world.town_hall;
    _world.place_building(&"field", th.origin + Vector2i(7, -1), Vector2i(6, 6));
    _world.place_building(&"house", th.origin + Vector2i(-5, 0), Vector2i(3, 3));
    for x in range(-6, 12):
        _world.set_road(th.origin + Vector2i(x, 5), true);
    _world.camera_rig._distance = 30.0;
    _world.camera_rig._target_distance = 30.0;
    GameClock.set_speed(3);

func _process(_delta:float) -> void:
    _frame += 1;
    Weather.is_raining = false;
    match _frame:
        300:
            _shot("before.png");
            SaveGame.save(_world, "test_shot");
        302:
            SaveGame.load_slot(_world, "test_shot");
        420:
            _shot("after.png");
            print("pawns after load: ", World.instance.pawns.size(), " buildings ", World.instance.buildings.size());
            get_tree().quit();

func _shot(file:String) -> void:
    get_viewport().get_texture().get_image().save_png(_out.path_join(file));
    print("saved ", file);
