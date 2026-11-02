# ----------------------------------------------------------------
# Greenhouse shot (windowed): an herbalist's hut without and with the
# herb greenhouse, with a stockpile right behind each, to see that the
# glasshouse stays inside the footprint.
#     godot --path . res://tests/greenhouse_shot.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

var world:World;
var _out:String = "user://";
var _frame:int = 0;
var _huts:Array[Herbalist] = [];

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
    world.hud.visible = false;

func _process(_delta:float) -> void:
    _frame += 1;
    if _frame == 3:
        var o:Vector2i = TestSite.near(world, Vector2i(-8, 8), Vector2i(16, 10));
        for i in 2:
            var at:Vector2i = o + Vector2i(i * 8, 4);
            var hut:Herbalist = world.place_building(&"herbalist", at, Vector2i(3, 3), true, false, 0) as Herbalist;
            world.place_building(&"stockpile", at + Vector2i(0, -4), Vector2i(3, 3), true);          # right behind it
            _huts.append(hut);
        _huts[1].upgrades_done[&"greenhouse"] = true;
        _huts[1].on_upgrade_done(&"greenhouse");
        world.camera_rig.focus_on(Vector3(o.x + 5.0, 0.0, o.y + 3.0));
        world.camera_rig._distance = 14.0;
        world.camera_rig._target_distance = 14.0;
        world.camera_rig._pitch = deg_to_rad(-40.0);
        world.camera_rig._yaw = deg_to_rad(215.0);          # from behind, where the glasshouse is
    if _frame == 20:
        get_viewport().get_texture().get_image().save_png(_out.path_join("greenhouse.png"));
        get_tree().quit();
