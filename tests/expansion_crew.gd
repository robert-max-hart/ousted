# ----------------------------------------------------------------
# Expansion crew test
#     In a running colony citizens haul the materials and do the
#     work of expanding a stockpile and a field.
#     godot --headless --path . --fixed-fps 60 res://tests/expansion_crew.tscn
# ----------------------------------------------------------------
extends Node;

var world:World;
var _pile:Building;
var _field:Field;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    world.seeds.unlock_all();
    var o:Vector2i = TestSite.near(world, Vector2i(8, -14));
    for rn in world.nodes.duplicate():
        if Rect2i(o - Vector2i(3, 3), Vector2i(24, 24)).has_point(rn.cell):
            world.remove_node(rn);
    world.terrain.flatten_rect(Rect2i(o - Vector2i(2, 2), Vector2i(26, 26)));
    _pile = world.place_building(&"stockpile", o, Vector2i(4, 4), true);
    _field = world.place_building(&"field", o + Vector2i(0, 8), Vector2i(4, 4), true) as Field;
    Expansion.start(world, _pile, Rect2i(o, Vector2i(8, 4)));
    Expansion.start(world, _field, Rect2i(o + Vector2i(0, 8), Vector2i(6, 6)));
    Engine.time_scale = 8.0;
    GameClock.set_speed(3);

func _process(_d:float) -> void:
    if _pile.size == Vector2i(8, 4) and _field.size == Vector2i(6, 6):
        print("EXPANSION CREW PASS (hour %d)" % int(GameClock.total_hours));
        get_tree().quit(0);
    elif GameClock.total_hours > 7.0 + 24.0 * 4:
        print("EXPANSION CREW FAIL: pile %s field %s" % [_pile.size, _field.size]);
        get_tree().quit(1);
