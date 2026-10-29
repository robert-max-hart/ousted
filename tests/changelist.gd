# ----------------------------------------------------------------
# Changelist
#     The title screen's Changelist button opens a panel built from
#     data/changelist.txt, one heading per push.
#     godot --headless --path . --fixed-fps 60 res://tests/changelist.tscn
# ----------------------------------------------------------------
extends Node;

var _title:TitleScreen;
var _frame:int = 0;
var _fails:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    _title = TitleScreen.new();
    add_child(_title);

func _process(_delta:float) -> void:
    _frame += 1;
    if _frame != 5:
        return;
    var sections:Array = Changelist.parse();
    _expect("the file has sections (%d)" % sections.size(), sections.size() >= 4);
    _expect("each has a version, a date, a title and bullets", sections.all(func(s:Dictionary) -> bool: return s["version"] != "" and s["date"] != "" and s["title"] != "" and not (s["items"] as Array).is_empty()));
    var versions:Array = sections.map(func(s:Dictionary) -> String: return s["version"]);
    _expect("versions look like 0.M.N and fall as you go down (%s)" % [versions], _ordered(versions));
    _expect("the build id is the newest version (%s)" % Changelist.build_id(), Changelist.build_id() == "Build " + versions[0] and Changelist.version() == versions[0]);
    _expect("a missing file gives nothing", Changelist.parse("res://data/nope.txt").is_empty());
    var label_found:bool = false;
    for l in _find_labels(_title):
        label_found = label_found or l.text == Changelist.build_id();
    _expect("the title shows the build id", label_found);
    _expect("the panel starts hidden", not _title._changes.visible);
    var button:Button = null;
    for b in _title._menu.get_children():
        if b is Button and (b as Button).text == "Changelist":
            button = b;
    _expect("the menu has a Changelist button", button != null);
    if button != null:
        button.pressed.emit();
        _expect("pressing it opens the panel", _title._changes.visible);
    print("CHANGELIST %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _find_labels(n:Node) -> Array[Label]:
    var out:Array[Label] = [];
    for c in n.get_children():
        if c is Label:
            out.append(c);
        out.append_array(_find_labels(c));
    return out;

# "0.M.N" or "0.M.N-dev", each older than the one before it.
func _ordered(versions:Array) -> bool:
    var last:Array = [999, 999];
    for v in versions:
        var clean:String = String(v).trim_suffix("-dev");
        var p:PackedStringArray = clean.split(".");
        if p.size() != 3 or p[0] != "0" or not p[1].is_valid_int() or not p[2].is_valid_int():
            return false;
        var now:Array = [p[1].to_int(), p[2].to_int()];
        if now[0] > last[0] or (now[0] == last[0] and now[1] >= last[1]):
            return false;
        last = now;
    return true;

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
