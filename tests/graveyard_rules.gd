# ----------------------------------------------------------------
# Graveyard rules and shack clearing test
#     A graveyard with a grave can't be demolished, the crematorium
#     upgrade burns the oldest graves for one coal each, and the
#     "clear empty shacks" policy (off by default) removes empty shacks.
#     godot --headless --path . --fixed-fps 60 res://tests/graveyard_rules.tscn
# ----------------------------------------------------------------
extends Node;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    var th:Building = world.town_hall;
    var yard:Graveyard = world.place_building(&"graveyard", th.origin + Vector2i(6, -2), Vector2i(3, 2), true) as Graveyard;
    for i in 6:
        yard.graves[i] = {"name": "G%d" % i, "age": 40, "cause": "old age", "buried_hour": float(i)};
    world.remove_building(yard, true);
    _expect("a graveyard with graves is not demolished", World.alive(yard) and world.buildings.has(yard));
    # no crematorium: nothing is burned and no coal is wanted
    yard.settings["keep_free"] = 3;
    yard.add_input(&"coal", 3);
    yard.on_day();
    _expect("no crematorium, no cremation", yard.used_slots() == 6);
    _expect("no crematorium, no coal wanted", yard.inputs_wanted().is_empty());
    yard.upgrades_done[&"crematorium"] = true;
    _expect("crematorium wants coal", yard.inputs_wanted() == {&"coal": 1});
    yard.on_day();
    _expect("the oldest graves were burned, one coal each", yard.free_slots() == 3 and yard.input_amount(&"coal") == 0);
    _expect("it burned the oldest", yard.graves[0] == null and yard.graves[1] == null and yard.graves[2] == null and yard.graves[3] != null);
    yard.settings["keep_free"] = 0;
    _expect("keep_free 0 asks for no coal", yard.inputs_wanted().is_empty());
    yard.add_input(&"coal", 3);
    yard.on_day();
    _expect("keep_free 0 burns nothing", yard.used_slots() == 3 and yard.input_amount(&"coal") == 3);
    for i in 6:
        yard.graves[i] = null;
    world.remove_building(yard, true);
    _expect("an empty graveyard can be demolished", not world.buildings.has(yard));
    # shacks
    var empty:Building = world.place_building(&"shack", th.origin + Vector2i(-6, 6), Vector2i(2, 2), true);
    var lived_in:Building = world.place_building(&"shack", th.origin + Vector2i(-6, 10), Vector2i(2, 2), true);
    world.families.move_home(world.pawns[0], lived_in);
    _expect("clearing is off by default", not world.policies.is_on(&"clear_shacks"));
    world.families._clear_shacks();
    _expect("off: empty shack stays", world.buildings.has(empty));
    world.policies.set_on(&"clear_shacks", true);
    world.families._clear_shacks();
    _expect("on: empty shack is removed", not world.buildings.has(empty));
    _expect("on: a shack with a resident stays", world.buildings.has(lived_in));
    get_tree().quit();

func _expect(what:String, ok:bool) -> void:
    print(("PASS " if ok else "FAIL ") + what);
