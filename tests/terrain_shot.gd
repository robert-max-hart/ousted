# ----------------------------------------------------------------
# Terrain screenshots
#     The same map and view in spring with no snow, then in winter with
#     half and with full snow cover (the cover is set by hand: the
#     weather builds it up over hours). Windowed.
#     godot --path . res://tests/terrain_shot.tscn -- <out_dir> [label]
# ----------------------------------------------------------------
extends Node;

var world:World;
var _out:String = "user://";
var _label:String = "terrain";
var _frame:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0:
        _out = args[0];
    if args.size() > 1:
        _label = args[1];
    GameClock.reset();
    GameClock.total_hours = float(2 * GameClock.HOURS_PER_DAY + 12);        # a spring noon
    Weather.reset();
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    world.world_seed = 4242;
    add_child(world);
    GameClock.set_speed(0);
    world.hud.visible = false;

func _view() -> void:
    var rig:Node = world.camera_rig;
    var th:Vector3 = world.town_hall.position;
    rig.focus_on(Vector3(th.x + 6.0, 0.0, th.z));
    rig._distance = 60.0;
    rig._target_distance = 60.0;
    rig._pitch = deg_to_rad(-42.0);

func _process(_delta:float) -> void:
    _frame += 1;
    if _frame == 2:
        _view();
    if _frame == 14:
        get_viewport().get_texture().get_image().save_png(_out.path_join(_label + "_spring.png"));
        GameClock.total_hours = float(27 * GameClock.HOURS_PER_DAY + 12);        # a winter noon: the ground goes dormant
        world.terrain.set_season(GameClock.Season.WINTER);
        world.visuals.snow_cover = 0.5;
        world.visuals._apply_snow();
    if _frame == 28:
        get_viewport().get_texture().get_image().save_png(_out.path_join(_label + "_half.png"));
        world.visuals.snow_cover = 1.0;
        world.visuals._apply_snow();
    if _frame == 40:
        get_viewport().get_texture().get_image().save_png(_out.path_join(_label + "_full.png"));
        get_tree().quit();
