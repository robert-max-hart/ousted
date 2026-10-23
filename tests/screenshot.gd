# ----------------------------------------------------------------
# Screenshot helper
#     Loads the game, lets it run, saves a few screenshots and quits.
#     godot --path . res://tests/screenshot.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

var world:World;
var _frame:int = 0;
var _out:String = "user://";

func _ready() -> void:
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0:
        _out = args[0];
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(3);
    var th:Building = world.town_hall;
    world.place_building(&"field", th.origin + Vector2i(7, -1), Vector2i(6, 6));
    world.place_building(&"house", th.origin + Vector2i(-5, 0), Vector2i(3, 3));
    for x in range(-6, 12):
        world.set_road(th.origin + Vector2i(x, 5), true);

func _process(_delta:float) -> void:
    _frame += 1;
    Weather.is_raining = false;
    if _frame == 240:
        _shot("shot_overview.png");
        world.tools.select(world.pawns[0]);
    if _frame == 600:
        world.camera_rig.focus_on(world.town_hall.position);
        _shot("shot_later.png");
    if _frame == 610:
        get_tree().quit();

func _shot(file:String) -> void:
    var img:Image = get_viewport().get_texture().get_image();
    img.save_png(_out.path_join(file));
    print("saved %s (fps %d)" % [_out.path_join(file), Engine.get_frames_per_second()]);
