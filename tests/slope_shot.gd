# ----------------------------------------------------------------
# Slope overlay screenshot
#     A zoomed-out view of the start with the slope overlay on.
#     godot --path . res://tests/slope_shot.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

var _out:String = "user://";
var _frame:int = 0;
var _world:World;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0:
        _out = args[0];
    _world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(_world);
    GameClock.set_speed(0);

func _process(_delta:float) -> void:
    _frame += 1;
    if _frame == 5:
        _world.hud._slope_toggle.button_pressed = true;
        var th:Vector3 = _world.town_hall.position;
        _world.camera_rig.focus_on(Vector3(th.x, 0.0, th.z));
        _world.camera_rig._distance = 75.0;
        _world.camera_rig._target_distance = 75.0;
    if _frame == 25:
        get_viewport().get_texture().get_image().save_png(_out.path_join("slope.png"));
        print("SLOPE SHOT saved");
        get_tree().quit();
