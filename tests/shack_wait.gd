# ----------------------------------------------------------------
# Shack waiting test
#     No shack goes up while the houses under construction have beds for
#     everyone still homeless; one does when they would not be enough.
#     godot --headless --path . --fixed-fps 60 res://tests/shack_wait.tscn
# ----------------------------------------------------------------
extends Node;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    for p in world.pawns:
        p.age = 30.0;
        p.homeless_hours = 100.0;
    var th:Building = world.town_hall;
    var shacks:Callable = func() -> int:
        return world.buildings.filter(func(b:Building) -> bool: return b.def.get("shack", false)).size();
    _expect("six homeless", world.families.homeless_count() == 6);
    world.place_building(&"house", th.origin + Vector2i(-8, 0), Vector2i(3, 3));    # a site: 6 beds
    world.families._build_shacks();
    _expect("a house going up holds everyone: no shack", shacks.call() == 0);
    world.place_building(&"house", th.origin + Vector2i(-12, 0), Vector2i(3, 3));
    for b in world.buildings:
        if b.def_id == &"house":
            b.def = b.def.duplicate();
            b.def["beds"] = 2;
    _expect("beds under construction counted", world.families._beds_under_construction() == 4);
    world.families._build_shacks();
    _expect("too few beds: a shack goes up", shacks.call() >= 1);
    print("shacks ", shacks.call());
    get_tree().quit();

func _expect(what:String, ok:bool) -> void:
    print(("PASS " if ok else "FAIL ") + what);
