# ----------------------------------------------------------------
# Look shot (a sixth argument, a tree distance 0 to 2, sets that setting for the shot and puts it back after)
#     The land in a chosen climate, season and snow cover, from the start site and over the water's edge.
#     godot --path . res://tests/look_shot.tscn -- <out_dir> <climate 0..3> <season 0..3> <snow 0..1> [map seed]
# ----------------------------------------------------------------
extends Node;

var world:World;
var _out:String = "user://";
var _frame:int = 0;
var _snow:float = 0.0;
var _kept_distance:int = 2;

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
    if args.size() > 5:
        Settings.set_value("tree_distance", int(args[5]));
    Defs.difficulty = &"easy";
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON * season + 3) * GameClock.HOURS_PER_DAY + 12.0;
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    Weather._update_temperature();
    world.camera_rig._distance = 38.0;
    world.camera_rig._target_distance = 38.0;
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
            get_tree().quit();

func _shot(n:String) -> void:
    get_viewport().get_texture().get_image().save_png(_out.path_join("%s.png" % n));
