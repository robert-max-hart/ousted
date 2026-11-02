# ----------------------------------------------------------------
# Settings: window size
#     The size is saved with the other settings and read back, the choices
#     are presets that fit the screen (plus a saved odd size), and only
#     the size and fullscreen changes resize the window. Puts the user's
#     own setting back at the end.
#     godot --headless --path . --fixed-fps 60 res://tests/settings_window.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Settings.ensure_loaded();
    var keep:Vector2i = Vector2i(Settings.window_w, Settings.window_h);
    var screen:Vector2i = DisplayServer.screen_get_size();
    var choices:Array[Vector2i] = Settings.window_size_choices();
    _expect("there are window sizes to choose from (%d)" % choices.size(), choices.size() > 0);
    for v in choices:
        if screen.x > 0 and Vector2i(Settings.window_w, Settings.window_h) != v:
            _expect("%s fits the screen %s" % [v, screen], v.x <= screen.x and v.y <= screen.y);
    Settings.set_value("window_size", Vector2i(1366, 768));
    _expect("the size is kept (%d x %d)" % [Settings.window_w, Settings.window_h], Settings.window_w == 1366 and Settings.window_h == 768);
    Settings.window_w = 0;
    Settings.window_h = 0;
    Settings._loaded = false;
    Settings.ensure_loaded();
    _expect("and comes back from the file (%d x %d)" % [Settings.window_w, Settings.window_h], Settings.window_w == 1366 and Settings.window_h == 768);
    Settings.set_value("window_size", Vector2i(1111, 650));
    var odd:Array[Vector2i] = Settings.window_size_choices();
    _expect("a saved size that is not a preset is listed too", odd.has(Vector2i(1111, 650)));
    Settings.set_value("window_size", Vector2i(-5, 999999));
    _expect("a silly size is clamped (%d x %d)" % [Settings.window_w, Settings.window_h], Settings.window_w == 0 and Settings.window_h == 16384);
    Settings.set_value("window_size", keep);
    print("SETTINGS WINDOW %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
