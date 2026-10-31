# ----------------------------------------------------------------
# Edge look shot
#     The map's corner and an edge seen from the usual playing distances and from as far out as the camera goes, at noon and at dusk.
#     godot --path . res://tests/edge_look_shot.tscn -- <out_dir> [map seed]
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
    World.new_game_seed = int(args[1]) if args.size() > 1 else 5;
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON * 1 + 3) * GameClock.HOURS_PER_DAY + 12.0;
    Weather._update_temperature();
    world.tools.select(null);
    _view(Vector3(Terrain.SIZE * 0.5, 0, 1.0), 40.0, -35.0, 0.0);

func _view(at:Vector3, dist:float, pitch:float, yaw:float) -> void:
    world.camera_rig.focus_on(at);
    world.camera_rig._distance = dist;
    world.camera_rig._target_distance = dist;
    world.camera_rig._pitch = deg_to_rad(pitch);
    world.camera_rig._yaw = deg_to_rad(yaw);

func _process(_delta:float) -> void:
    _frame += 1;
    var s:float = Terrain.SIZE;
    match _frame:
        20:
            _shot("edge_a");
            _view(Vector3(s * 0.5, 0, 1.0), 120.0, -22.0, 0.0);
        40:
            _shot("edge_b");
            _view(Vector3(2.0, 0, 2.0), 60.0, -30.0, 35.0);
        60:
            _shot("edge_c");
            _view(Vector3(s - 2.0, 0, s * 0.5), 120.0, -20.0, 90.0);
        80:
            _shot("edge_d");
            _view(Vector3(s * 0.5, 0, s * 0.5), 120.0, -20.0, 200.0);
        100:
            _shot("edge_e");
            GameClock.total_hours = (GameClock.DAYS_PER_SEASON * 1 + 3) * GameClock.HOURS_PER_DAY + 19.3;
            _view(Vector3(s * 0.5, 0, 1.0), 60.0, -28.0, 20.0);
        130:
            _shot("edge_dusk");
            get_tree().quit();

func _shot(n:String) -> void:
    get_viewport().get_texture().get_image().save_png(_out.path_join("%s.png" % n));
