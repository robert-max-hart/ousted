# ----------------------------------------------------------------
# Settings panel fit
#     The settings window must stay inside a short screen: the options
#     scroll and the Back button is always on screen (it used to run off
#     the bottom of the title screen, leaving no way to close it with
#     the mouse). Checked in viewports of several heights.
#     godot --headless --path . --fixed-fps 60 res://tests/settings_fit.tscn
# ----------------------------------------------------------------
extends Node;

const HEIGHTS:Array[int] = [360, 480, 600, 900, 1400];

var _fails:int = 0;
var _step:int = 0;
var _vp:SubViewport;
var _panel:SettingsPanel;

func _ready() -> void:
    SaveGame.autosave_enabled = false;

func _process(_delta:float) -> void:
    _step += 1;
    var phase:int = _step / 4;
    var sub:int = _step % 4;
    if phase >= HEIGHTS.size():
        print("SETTINGS FIT %s" % ("PASS" if _fails == 0 else "FAIL"));
        get_tree().quit(1 if _fails > 0 else 0);
        return;
    if sub == 1:
        _vp = SubViewport.new();
        _vp.size = Vector2i(1000, HEIGHTS[phase]);
        add_child(_vp);
        _panel = SettingsPanel.new();
        _vp.add_child(_panel);
    elif sub == 3:
        var back:Button = _find(_panel, "Back");
        var h:int = HEIGHTS[phase];
        _expect("height %d: the Back button exists" % h, back != null);
        if back != null:
            var r:Rect2 = back.get_global_rect();
            _expect("height %d: Back is on screen (%.0f to %.0f)" % [h, r.position.y, r.end.y], r.position.y >= 0.0 and r.end.y <= float(h));
            _expect("height %d: and the panel top is on screen" % h, _panel.get_child(1).get_child(0).get_global_rect().position.y >= 0.0);
        _vp.queue_free();

func _find(n:Node, text:String) -> Button:
    if n is Button and (n as Button).text == text:
        return n;
    for c in n.get_children():
        var r:Button = _find(c, text);
        if r != null:
            return r;
    return null;

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
