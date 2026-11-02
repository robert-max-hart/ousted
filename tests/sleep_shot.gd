# ----------------------------------------------------------------
# Sleep shot (windowed): a citizen asleep in the open, close up, to look
# at the closed eyes and the Zs.
#     godot --path . res://tests/sleep_shot.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

var world:World;
var _out:String = "user://";
var _frame:int = 0;
var _p:Pawn;
var _spot:Vector3;

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
    GameClock.set_speed(1);
    world.hud.visible = false;

func _process(_delta:float) -> void:
    _frame += 1;
    if _frame == 2:
        _p = world.pawns[0];
        _p.task = null;
        _p.position = world.pawns[1].position + Vector3(1.6, 0.0, 0.0);
        _p.sleeping = true;
        _p.indoors = false;
        _p.visible = true;
        _spot = _p.position;
        world.camera_rig.focus_on(_p.position);
        world.camera_rig._distance = 1.7;
        world.camera_rig._target_distance = 1.7;
        world.camera_rig._pitch = deg_to_rad(-60.0);
    if _frame >= 3:
        _p.task = null;
        _p.position = _spot;
        world.camera_rig.focus_on(_p.to_global(Vector3(0.0, 0.0, -0.7)));
        _p.sleeping = true;
        _p.indoors = false;
        _p.visible = true;
    if _frame == 40 or _frame == 100:
        get_viewport().get_texture().get_image().save_png(_out.path_join("sleep_%d.png" % _frame));
    if _frame == 100:
        print("SLEEPER ", _p.position, " vis=", _p.visible, " zs=", _p._zs != null, " cam=", world.camera_rig.global_position);
    if _frame == 101:
        get_tree().quit();
