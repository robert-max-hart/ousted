# ----------------------------------------------------------------
# Spoilage log test
#     The daily spoilage message names what spoiled, biggest loss
#     first, and says what was lying on the ground.
#     godot --headless --path . --fixed-fps 60 res://tests/spoilage_log.tscn
# ----------------------------------------------------------------
extends Node;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    var th:Building = world.town_hall;
    th.stored.clear();
    th.store(&"berries", 60);
    th.store(&"lettuce", 20);
    world.drop_pile(&"mushrooms", 20, th.origin + Vector2i(-6, 0));
    var pile:GroundPile = world.piles[world.piles.size() - 1];
    Weather.temperature = 25.0;
    for h in 24:
        world._spoiled_today += th.spoil_tick(1.0, world._spoiled_stored);
        world._spoiled_today += pile.spoil_tick(1.0, world._spoiled_ground);
    var text:String = world._spoilage_report();
    print(text);
    var ok:bool = text.begins_with("Spoiled yesterday: ") and text.contains("berries") and text.contains("(on the ground: ") and text.contains("mushrooms");
    print("SPOILAGE LOG %s" % ("PASS" if ok else "FAIL"));
    get_tree().quit(0 if ok else 1);
