# ----------------------------------------------------------------
# Wood fuel test
#     A house burns raw wood (3 firewood's worth each) only as a last
#     resort: in the cold, under half its fuel target, with no firewood
#     in storage, and never when set to burn coal only.
#     godot --headless --path . --fixed-fps 60 res://tests/wood_fuel.tscn
# ----------------------------------------------------------------
extends Node;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    var th:Building = world.town_hall;
    var house:Building = world.place_building(&"house", th.origin + Vector2i(-6, 0), Vector2i(3, 3), true);
    var p:Pawn = world.pawns[0];
    th.stored.erase(&"firewood");
    th.stored[&"wood"] = 20;
    house.fuel = 0;
    house.settings["fuel_target"] = 20;
    _expect("wood heats like 3 firewood", Defs.ITEMS[&"wood"]["heat"] == 3);
    Weather.temperature = 0.0;
    _expect("cold, empty house: wood is a fallback", _items(world, house).has(&"wood"));
    _expect("firewood still comes first", _items(world, house)[0] == &"firewood");
    Weather.temperature = 20.0;
    _expect("warm weather: no wood", not _items(world, house).has(&"wood"));
    Weather.temperature = 0.0;
    house.fuel = 12;
    _expect("a house over half its target: no wood", not _items(world, house).has(&"wood"));
    house.fuel = 0;
    house.settings["fuel_type"] = 1;
    _expect("coal only: never wood", not _items(world, house).has(&"wood"));
    house.settings["fuel_type"] = 0;
    var t:Task = world.jobs._fuel_task(p);
    _expect("a fuel task is made from wood", t != null);
    _expect("it counts 3 per wood", house.fuel_incoming % 3 == 0 and house.fuel_incoming > 0);
    print("incoming fuel ", house.fuel_incoming, " (", house.fuel_incoming / 3, " wood)");
    get_tree().quit();

func _items(world:World, house:Building) -> Array[StringName]:
    return world.jobs._fuel_items(house);

func _expect(what:String, ok:bool) -> void:
    print(("PASS " if ok else "FAIL ") + what);
