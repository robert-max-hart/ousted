# ----------------------------------------------------------------
# Empty store shot (windowed): the inspector of a stockpile that is
# being emptied, to look at the new switch and note.
#     godot --path . res://tests/empty_store_shot.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

var world:World;
var _out:String = "user://";
var _frame:int = 0;
var _a:Building;

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

func _process(_delta:float) -> void:
    _frame += 1;
    if _frame == 3:
        var o:Vector2i = TestSite.near(world, Vector2i(-10, 8), Vector2i(6, 6));
        _a = world.place_building(&"stockpile", o, Vector2i(4, 4), true);
        _a.store(&"stone", 40);
        world.place_building(&"stockpile", TestSite.near(world, Vector2i(10, 8), Vector2i(6, 6)), Vector2i(4, 4), true);
        world.tools.select(_a);
        world.camera_rig.focus_on(_a.position);
    if _frame == 20:
        world.hud._empty_check.button_pressed = true;
    if _frame == 40:
        get_viewport().get_texture().get_image().save_png(_out.path_join("empty_store.png"));
        get_tree().quit();
