# ----------------------------------------------------------------
# Title screen test
#     Builds the title screen (frozen backdrop town, menu) and saves
#     a screenshot; with a seed number after -- it uses that map.
#     godot --path . res://tests/title_shot.tscn -- <out_dir> [season]
# ----------------------------------------------------------------
extends Node;

var _out:String = "user://";
var _frame:int = 0;
var _title:TitleScreen;
var _season:int = -1;
var _cam_before:Vector3;
var _precip:float = -1.0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0:
        _out = args[0];
    if args.size() > 1:
        _season = args[1].to_int();
    if args.size() > 2:
        _precip = args[2].to_float();
    _title = TitleScreen.new();
    if _season >= 0:
        seed(_season * 7919 + 13);       # makes the title's random season repeatable
    add_child(_title);
    if _precip >= 0.0:
        Weather.reset(_precip);       # force rain or snow (which one follows the season's temperature)

func _process(_delta:float) -> void:
    _frame += 1;
    if _frame == 20:
        var w:World = World.instance;
        _expect("the backdrop world has no citizens", w.pawns.is_empty());
        _expect("and no HUD or tools", w.hud == null and w.tools == null);
        _expect("it has buildings (%d)" % w.buildings.size(), w.buildings.size() > 8);
        _expect("the clock is stopped", GameClock.speed() == 0.0);
        _cam_before = get_viewport().get_camera_3d().global_position;
        _expect("homes are lit", w.buildings.any(func(b:Building) -> bool: return b.windows_lit_always));
        var smoking:int = World.instance.buildings.filter(func(b:Building) -> bool: return b._smoke != null and b._smoke.emitting).size();
        _expect("smoke and weather run behind the title (%d chimneys smoking, rain %s)" % [smoking, Weather.intensity > 0.0], World.fx_speed() == 1.0);
        get_viewport().get_texture().get_image().save_png(_out.path_join("title_%d.png" % maxi(_season, 0)));
    elif _frame == 40:
        _expect("the clock did not move", GameClock.speed() == 0.0);
        _expect("the camera drifts (moved %.3f)" % _cam_before.distance_to(get_viewport().get_camera_3d().global_position), get_viewport().get_camera_3d() is TitleCamera and _cam_before.distance_to(get_viewport().get_camera_3d().global_position) > 0.001);
        get_tree().quit();

func _expect(what:String, ok:bool) -> void:
    print(("PASS " if ok else "FAIL ") + what);
