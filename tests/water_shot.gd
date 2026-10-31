# ----------------------------------------------------------------
# Water screenshot
#     The same map at noon, close to the first river ford, with the water
#     a moment apart (two pictures, to see it move) and a wider view.
#     godot --path . res://tests/water_shot.tscn -- <out_dir> [label]
# ----------------------------------------------------------------
extends Node;

var world:World;
var _out:String = "user://";
var _label:String = "water";
var _frame:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0:
        _out = args[0];
    if args.size() > 1:
        _label = args[1];
    GameClock.reset();
    GameClock.total_hours = float(2 * GameClock.HOURS_PER_DAY + 12);        # noon
    Weather.reset();
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    world.world_seed = 4242;
    add_child(world);
    GameClock.set_speed(0);
    world.hud.visible = false;

func _process(_delta:float) -> void:
    _frame += 1;
    var rig:Node = world.camera_rig;
    if _frame == 2:
        var f:Vector2 = world.terrain.river_fords[0] if not world.terrain.river_fords.is_empty() else Vector2(80, 80);
        rig.focus_on(Vector3(f.x, 0.0, f.y));
        rig._distance = 30.0;
        rig._target_distance = 30.0;
        rig._pitch = deg_to_rad(-38.0);
    if _frame == 12:
        get_viewport().get_texture().get_image().save_png(_out.path_join(_label + "_a.png"));
        if world.visuals.has_method("_update_water"):
            GameClock.set_speed(1);          # (the water clock follows the game speed: paused water does not move)
            for i in 90:
                world.visuals._update_water(0.1);       # nine seconds on
            GameClock.set_speed(0);
    if _frame == 22:
        get_viewport().get_texture().get_image().save_png(_out.path_join(_label + "_b.png"));
        get_tree().quit();
