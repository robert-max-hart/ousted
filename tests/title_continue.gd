# ----------------------------------------------------------------
# Title continue test
#     Continue on the title screen loads a saved game into the main
#     scene (a throwaway slot, removed afterwards).
#     godot --headless --path . --fixed-fps 60 res://tests/title_continue.tscn
# ----------------------------------------------------------------
extends Node;

const SLOT:String = "title_test";
var _frame:int = 0;
var _seed:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    var w:World = (load(SaveGame.MAIN_SCENE) as PackedScene).instantiate();
    add_child(w);
    _seed = w.world_seed;
    w.place_building(&"house", TestSite.spot(w, Vector2i(3, 3), Vector2i(8, 0)), Vector2i(3, 3), true);
    _expect("a save was written", SaveGame.write(w, SLOT) == "");
    w.queue_free();

func _process(_delta:float) -> void:
    _frame += 1;
    if _frame == 3:
        var keeper:Node = Node.new();
        get_tree().root.add_child(keeper);
        get_tree().current_scene = keeper;
        var err:String = SaveGame.start_from_slot(get_tree(), SLOT);
        _expect("starting from the slot gives no error (%s)" % err, err == "");
        _expect("a missing slot says so", SaveGame.start_from_slot(get_tree(), "no_such_slot") != "");
    elif _frame == 10:
        var w:World = World.instance;
        _expect("the saved world came back (seed %d)" % w.world_seed, w.world_seed == _seed and w.buildings.size() >= 2);
        DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.path_for(SLOT)));
        get_tree().quit();

func _expect(what:String, ok:bool) -> void:
    print(("PASS " if ok else "FAIL ") + what);
