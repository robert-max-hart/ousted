# ----------------------------------------------------------------
# Look shot (a sixth argument, a tree distance 0 to 2, and a seventh, the model detail 0 or 1, set those settings for the shot and put them back after;
#     an eighth gives the first picture's camera distance)
#     The land in a chosen climate, season and snow cover, from the start site and over the water's edge.
#     godot --path . res://tests/look_shot.tscn -- <out_dir> <climate 0..3> <season 0..3> <snow 0..1> [map seed]
# ----------------------------------------------------------------
extends Node;

var world:World;
var _out:String = "user://";
var _frame:int = 0;
var _snow:float = 0.0;
var _kept_distance:int = 2;
var _kept_detail:int = 0;
var _near:float = 38.0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Weather.drought_enabled = false;
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0:
        _out = args[0];
    Climate.current = int(args[1]) if args.size() > 1 else 0;
    var season:int = int(args[2]) if args.size() > 2 else 1;
    _snow = float(args[3]) if args.size() > 3 else 0.0;
    if args.size() > 4:
        World.new_game_seed = int(args[4]);
    Settings.ensure_loaded();
    _kept_distance = Settings.tree_distance;
    _kept_detail = Settings.model_detail;
    if args.size() > 6:
        Settings.set_value("model_detail", int(args[6]));
    if args.size() > 5:
        Settings.set_value("tree_distance", int(args[5]));
    Defs.difficulty = &"easy";
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON * season + 3) * GameClock.HOURS_PER_DAY + 12.0;
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    Weather._update_temperature();
    _near = float(args[7]) if args.size() > 7 else 38.0;
    world.camera_rig._distance = _near;
    world.camera_rig._target_distance = _near;
    world.camera_rig._pitch = deg_to_rad(-32.0);
    world.tools.select(null);

func _process(_delta:float) -> void:
    _frame += 1;
    world.visuals.snow_cover = _snow;
    match _frame:
        50:
            _shot("look_a");
            world.camera_rig._distance = 70.0;
            world.camera_rig._target_distance = 70.0;
            world.camera_rig._pitch = deg_to_rad(-45.0);
        90:
            _shot("look_b");
            Settings.set_value("tree_distance", _kept_distance);
            Settings.set_value("model_detail", _kept_detail);
            get_tree().quit();

func _shot(n:String) -> void:
    get_viewport().get_texture().get_image().save_png(_out.path_join("%s.png" % n));
