# ----------------------------------------------------------------
# Loading shot
#     The loading screen: the title's picture is built under it, then a new game is built under it, with a picture every
#     few frames and the time each took. Windowed (the frame times mean little headless).
#     godot --path . res://tests/loading_shot.tscn -- <out_dir> [climate]
# ----------------------------------------------------------------
extends Node;

var _out:String = "user://";
var _frame:int = 0;
var _phase:int = 0;
var _t0:int = 0;
var _node:Node = null;
var _shots:int = 0;
var _worst:int = 0;
var _last:int = 0;
var _plain:bool = false;        # no loading screen: how the game used to load, for comparison

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0:
        _out = args[0];
    if args.size() > 1:
        Climate.current = int(args[1]);
    _plain = args.size() > 2 and args[2] == "plain";
    _start_title();

func _start_title() -> void:
    _phase = 1;
    _t0 = Time.get_ticks_msec();
    _last = _t0;
    _frame = 0;
    _shots = 0;
    _node = (load("res://scenes/title.tscn") as PackedScene).instantiate();
    add_child(_node);

func _start_game() -> void:
    _node.queue_free();
    _phase = 3;
    Defs.difficulty = &"normal";
    GameClock.reset();
    Weather.reset();
    World.choose_start = false;
    if not _plain:
        LoadingScreen.begin(get_tree());
    _t0 = Time.get_ticks_msec();
    _last = _t0;
    _frame = 0;
    _shots = 0;
    _worst = 0;
    _node = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(_node);

func _process(_delta:float) -> void:
    _frame += 1;
    var now:int = Time.get_ticks_msec();
    _worst = maxi(_worst, now - _last);
    _last = now;
    if _phase == 1 or _phase == 3:
        if _frame % 20 == 5 and _shots < 8:
            get_viewport().get_texture().get_image().save_png(_out.path_join("%s_%d.png" % ["title" if _phase == 1 else "game", _shots]));
            _shots += 1;
        if _frame > 3 and not LoadingScreen.active and _frame > 10 and (_phase == 1 or not _plain or _frame > 14):
            print("%s loaded: %d frames, %d ms, worst frame %d ms, clock held %s" % ["title" if _phase == 1 else "game", _frame, now - _t0, _worst, GameClock.held]);
            get_viewport().get_texture().get_image().save_png(_out.path_join("%s_done.png" % ("title" if _phase == 1 else "game")));
            _phase += 1;
            _frame = 0;
            _worst = 0;
    elif _phase == 2 and _frame == 40:
        _start_game();
    elif _phase == 4 and _frame == 90:
        print("after loading: worst frame in the next 90 frames %d ms" % _worst);
        get_viewport().get_texture().get_image().save_png(_out.path_join("game_after.png"));
        get_tree().quit();
