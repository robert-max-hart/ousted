# ----------------------------------------------------------------
# Detail settings shot
#     The same view of a forest and a field at full detail and far draw distance, at the Near draw distance (the blocks past it
#     are gone) and with the reduced models.
#     godot --path . res://tests/detail_settings_shot.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

var world:World;
var _out:String = "user://";
var _frame:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Weather.drought_enabled = false;
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0:
        _out = args[0];
    Defs.difficulty = &"easy";
    Settings.set_value("tree_distance", 2);
    Settings.set_value("model_detail", 0);
    World.new_game_seed = 5;
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON * 1 + 3) * GameClock.HOURS_PER_DAY + 12.0;
    Weather._update_temperature();
    world.seeds.unlock_all();
    var o:Vector2i = TestSite.anchor(world) + Vector2i(8, 4);
    var f:Field = world.place_building(&"field", TestSite.spot(world, Vector2i(6, 6), Vector2i(8, 4)), Vector2i(6, 6), true) as Field;
    for i in f.plot_count():
        f.plot_crop[i] = [&"wheat", &"cabbage", &"pumpkin"][i % 3];
        f.plot_state[i] = Field.Plot.RIPE;
        f.growth[i] = 1.0;
    f._visual_dirty = true;
    world.camera_rig.focus_on(Vector3(o.x, 0, o.y));
    world.camera_rig._distance = 80.0;
    world.camera_rig._target_distance = 80.0;
    world.camera_rig._pitch = deg_to_rad(-35.0);
    world.tools.select(null);

func _process(_delta:float) -> void:
    _frame += 1;
    match _frame:
        30:
            _shot("detail_full");
            Settings.set_value("tree_distance", 0);
        50:
            _shot("detail_near");
            Settings.set_value("tree_distance", 2);
            Settings.set_value("model_detail", 1);
            world.camera_rig._distance = 22.0;
            world.camera_rig._target_distance = 22.0;
        90:
            _shot("detail_reduced_close");
            Settings.set_value("model_detail", 0);
        120:
            _shot("detail_full_close");
            Settings.set_value("model_detail", 0);
            Settings.set_value("tree_distance", 2);
            get_tree().quit();

func _shot(n:String) -> void:
    get_viewport().get_texture().get_image().save_png(_out.path_join("%s.png" % n));
