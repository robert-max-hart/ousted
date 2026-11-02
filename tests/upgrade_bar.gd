# ----------------------------------------------------------------
# Upgrade progress bar
#     A building being upgraded shows a bar over it (amber while the
#     materials are delivered, blue while the builders work) and the
#     inspector shows the same bar with a label. Nothing shows when no
#     upgrade is under way. With a picture when run windowed:
#     godot --headless --path . --fixed-fps 60 res://tests/upgrade_bar.tscn
#     godot --path . res://tests/upgrade_bar.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

var world:World;
var _fails:int = 0;
var _frame:int = 0;
var _hut:Building;
var _out:String = "";

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
        var o:Vector2i = TestSite.near(world, Vector2i(-8, 8), Vector2i(8, 8));
        _hut = world.place_building(&"herbalist", o, Vector2i(3, 3), true, false, 0);
        world.tools.select(_hut);
        world.camera_rig.focus_on(_hut.position);
        world.camera_rig._distance = 12.0;
        world.camera_rig._target_distance = 12.0;
    elif _frame == 10:
        _expect("no bar over a building with no upgrade", _hut.progress_bar == null or not _hut.progress_bar.visible);
        _expect("the upgrade starts", _hut.start_upgrade(&"greenhouse"));
    elif _frame == 25:
        var bar:Dictionary = _hut.build_bar();
        _expect("waiting for materials: an amber bar at 0%% (%s)" % bar, not bar["working"] and bar["fill"] == 0.0 and "materials" in bar["text"]);
        _expect("the bar floats over the building", _hut.progress_bar != null and _hut.progress_bar.visible);
        _expect("and the inspector shows it (%s)" % world.hud._site_bar_label.text, world.hud._site_bar_label.text == bar["text"] and world.hud._site_bar.value == 0.0);
        var cost:Dictionary = _hut.cost();
        var first:StringName = cost.keys()[0];
        _hut.delivered[first] = cost[first];
        var half:float = _hut.materials_share();
        _expect("part of the materials in is a share of them (%.2f)" % half, half > 0.0 and half < 1.0 or cost.size() == 1);
        _shot("upgrade_bar_materials.png");
    elif _frame == 40:
        for item in _hut.cost():
            _hut.delivered[item] = _hut.cost()[item];
        _hut.work_done = _hut.work_required() * 0.4;
    elif _frame == 55:
        var bar2:Dictionary = _hut.build_bar();
        _expect("all materials in: a blue bar at the work done (%s)" % bar2, bar2["working"] and absf(bar2["fill"] - 0.4) < 0.01 and "Upgrading: 40%" == bar2["text"]);
        _expect("the inspector says so (%s)" % world.hud._site_bar_label.text, world.hud._site_bar_label.text == "Upgrading: 40%" and absf(world.hud._site_bar.value - 0.4) < 0.01);
        _shot("upgrade_bar_work.png");
        _hut.add_work(_hut.work_required());
    elif _frame == 70:
        _expect("done: the upgrade is built and the bar is gone", _hut.has_upgrade(&"greenhouse") and _hut.upgrading == &"" and (_hut.progress_bar == null or not _hut.progress_bar.visible));
        print("UPGRADE BAR %s" % ("PASS" if _fails == 0 else "FAIL"));
        get_tree().quit(1 if _fails > 0 else 0);

func _shot(file:String) -> void:
    if _out != "":
        get_viewport().get_texture().get_image().save_png(_out.path_join(file));

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
