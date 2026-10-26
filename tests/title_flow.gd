# ----------------------------------------------------------------
# Title flow test
#     New Game on the title screen: the difficulty and seed choices
#     carry into the game, which starts at the first morning with the
#     starting settlers, and the title's own frozen clock and weather
#     do not leak into it.
#     godot --headless --path . --fixed-fps 60 res://tests/title_flow.tscn
# ----------------------------------------------------------------
extends Node;

var _frame:int = 0;
var _title:TitleScreen;
var _started:bool = false;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    _title = TitleScreen.new();
    add_child(_title);

func _process(_delta:float) -> void:
    _frame += 1;
    if _frame == 5:
        _expect("the title speed is stopped", GameClock.speed() == 0.0);
        _title._show_new_game();
        _expect("New Game opens the panel", _title._new_panel.visible and not _title._menu.visible);
        _title._pick_difficulty(&"hard");
        _expect("the difficulty text lists the starting seeds", _title._diff_text.text.contains("Wheat") and not _title._diff_text.text.contains("Barley"));
        _title._seed_edit.text = "4242";
        # keep this node alive when the scene changes
        var keeper:Node = Node.new();
        get_tree().root.add_child(keeper);
        get_tree().current_scene = keeper;
        _title._on_start();
        _started = true;
    elif _started and _frame == 12:
        var w:World = World.instance;
        _expect("a game started with the chosen seed (%d)" % w.world_seed, w.world_seed == 4242);
        _expect("on the chosen difficulty", Defs.difficulty == &"hard" and w.seeds.known.size() == 1);
        _expect("with the starting settlers (%d)" % w.pawns.size(), w.pawns.size() == World.START_PAWNS);
        _expect("with a HUD", w.hud != null and w.tools != null);
        _expect("at the first morning (%.1f)" % GameClock.total_hours, GameClock.total_hours < 20.0);
        _expect("running at normal speed", GameClock.speed() == 1.0);
        _expect("not a backdrop", not World.backdrop);
        Defs.difficulty = &"normal";
        get_tree().quit();

func _expect(what:String, ok:bool) -> void:
    print(("PASS " if ok else "FAIL ") + what);
