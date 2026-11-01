# ----------------------------------------------------------------
# Stone house
#     The stone house costs more stone and some iron, burns half the
#     fuel of a wooden house, counts as a house for goals, and a
#     wooden house can be upgraded in place: the residents stay, the
#     def changes, the fuel and settings are kept.
#     godot --headless --path . --fixed-fps 60 res://tests/stone_house.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    Weather.drought_enabled = false;
    GameRules.reset();
    GameRules.illness = 0;
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    var wood:Dictionary = Defs.BUILDINGS[&"house"];
    var stone:Dictionary = Defs.BUILDINGS[&"stone_house"];
    _expect("more stone and some iron", stone["cost"][&"stone"] > wood["cost"][&"stone"] and stone["cost"].get(&"iron", 0) > 0);
    _expect("in the Housing menu", (Defs.BUILD_CATEGORIES[0][1] as Array).has(&"stone_house") and Defs.BUILD_MENU.has(&"stone_house"));
    _expect("the wooden house offers the upgrade", wood["upgrades"][&"stone"]["becomes"] == &"stone_house");
    var a:Vector2i = TestSite.spot(world, Vector2i(3, 3), Vector2i(-8, 8));
    var w:Building = world.place_building(&"house", a, Vector2i(3, 3), true);
    var b_at:Vector2i = TestSite.spot(world, Vector2i(3, 3), Vector2i(8, 8));
    var s:Building = world.place_building(&"stone_house", b_at, Vector2i(3, 3), true);
    _expect("both built", w != null and s != null and w.is_complete() and s.is_complete());
    var p1:Pawn = world.pawns[0];
    var p2:Pawn = world.pawns[1];
    p1.home = w;
    w.residents.append(p1);
    p2.home = s;
    s.residents.append(p2);
    Weather.temperature = 0.0;
    for i in range(24):
        w._burn_fuel(1.0);
        s._burn_fuel(1.0);
    w.fuel = 40;
    s.fuel = 40;
    for i in range(24):
        w._burn_fuel(1.0);
        s._burn_fuel(1.0);
    var wburn:int = 40 - w.fuel;
    var sburn:int = 40 - s.fuel;
    _expect("the stone house burns half (%d against %d a day)" % [sburn, wburn], wburn > 0 and sburn * 2 <= wburn + 1 and sburn * 2 >= wburn - 1);
    _expect("it counts as a house", s.def.get("counts_as", &"") == &"house");
    # upgrade in place
    w.fuel = 25;
    w.settings["fuel_target"] = 15;
    _expect("upgrade can start", w.upgrade_block_reason(&"stone") == "");
    _expect("it starts", w.start_upgrade(&"stone"));
    for item in w.cost():
        w.receive(item, w.cost()[item]);
    _expect("materials are in", w.has_all_materials());
    _expect("work finishes it", w.add_work(w.work_required()));
    _expect("it is a stone house now", w.def_id == &"stone_house" and w.def == stone and w.is_complete() and w.upgrading == &"");
    _expect("the residents stay", w.residents.has(p1) and is_same(p1.home, w));
    _expect("fuel and settings are kept", w.fuel == 25 and w.settings["fuel_target"] == 15);
    _expect("no upgrade left on it", w.upgrades_done.is_empty() and not w.def.has("upgrades"));
    _expect("what it cost is the stone house's cost", w.delivered == stone["cost"]);
    w.fuel = 40;
    for i in range(24):
        w._burn_fuel(1.0);
    _expect("and it burns half now (%d)" % (40 - w.fuel), absi((40 - w.fuel) - sburn) <= 1);
    _expect("it still draws (body and door exist)", w._body != null and w._door != null);
    # saving keeps it
    var data:Dictionary = world.serialize();
    var kinds:Array = [];
    for d in data["buildings"]:
        kinds.append(d.get("def_id", d.get("id", "")));
    _expect("saved as a stone house", kinds.count(&"stone_house") + kinds.count("stone_house") >= 2);
    print("STONE_HOUSE %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
