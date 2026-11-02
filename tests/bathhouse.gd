# ----------------------------------------------------------------
# Bathhouse (and the Open switch)
#     Citizens of 5 and over come for a bath every few days: better in
#     mood for two days, less likely to catch or spread a sickness for
#     three, warmed through in the cold, on hot water that costs a
#     firewood for every six bathers (three in the cold). Buildings with
#     no workers that people visit (tavern, chapel, bathhouse, arbor)
#     have an Open switch: closed, nobody goes and the visitors leave.
#     godot --headless --path . --fixed-fps 60 res://tests/bathhouse.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;
var world:World;
var _bath:Building;
var _bather:Pawn;
var _phase:int = 0;
var _start:float = 0.0;
var _set:bool = false;
var _day:int = 0;
var _firewood0:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    Weather.drought_enabled = false;
    GameRules.reset();
    GameRules.illness = 2;
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    Weather._day_offset = 0.0;
    await get_tree().process_frame;
    var def:Dictionary = Defs.BUILDINGS[&"bathhouse"];
    _expect("it is in the Civic menu and needs water", Defs.BUILD_MENU.has(&"bathhouse") and (Defs.BUILD_CATEGORIES[4][1] as Array).has(&"bathhouse") and def["needs_water"] > 0.0);
    _expect("it is a plain stone and wood building, no iron", def["cost"].keys().all(func(k:StringName) -> bool: return k == &"wood" or k == &"stone"));
    for id in [&"tavern", &"chapel", &"bathhouse", &"arbor"]:
        var has_switch:bool = false;
        for c in Defs.BUILDINGS[id].get("controls", []):
            has_switch = has_switch or (c["id"] == "open" and c["type"] == "toggle");
        _expect("%s has an Open switch" % id, Defs.BUILDINGS[id].get("closable", false) and has_switch);
    _expect("buildings with workers do not", not Defs.BUILDINGS[&"school"].get("closable", false) and not Defs.BUILDINGS[&"house"].get("closable", false));
    for b in world.buildings.duplicate():
        if b.def_id == &"cart":
            world.remove_building(b, false);
    var o:Vector2i = TestSite.spot(world, Vector2i(4, 3), Vector2i(-8, 8));
    _bath = world.place_building(&"bathhouse", o, Vector2i(4, 3), true);
    _expect("it was built, with water in reach", _bath != null and _bath.is_complete() and _bath.has_water());
    # fuel: six bathers to a firewood, three in the cold
    _bath.add_input(&"firewood", 2);
    var hot:int = 0;
    while _bath.bath_use(false) and hot < 40:
        hot += 1;
    _expect("2 firewood heat the water for 12 bathers (%d)" % hot, hot == 12);
    _bath.add_input(&"firewood", 2);
    hot = 0;
    while _bath.bath_use(true) and hot < 40:
        hot += 1;
    _expect("and for 6 in the cold (%d)" % hot, hot == 6);
    _expect("then it is a cold bath", not _bath.bath_use(false));
    # the bather's side
    var p:Pawn = world.pawns[0];
    p.warmth = 0.4;
    Weather.temperature = 15.0;
    p.bathe(true);
    var mood_named:bool = false;
    for f in p.happiness_factors():
        mood_named = mood_named or (f[0] == "Freshly bathed" and is_equal_approx(f[1], Defs.BATH_MOOD));
    _expect("a hot bath: the mood factor and protection", mood_named and is_equal_approx(p.clean_factor(), Defs.BATH_ILLNESS_MULT) and p.warmth == 0.4);
    _expect("illness onset is lower while clean", Illness.new(world).onset_chance(p) < Illness.new(world).onset_chance(world.pawns[1]) or world.pawns[1].clean_factor() < 1.0);
    Weather.temperature = 0.0;
    p.bathe(true);
    _expect("in the cold it warms the bather through", p.warmth == 1.0);
    p.bathe(false);
    var cold_named:bool = false;
    for f in p.happiness_factors():
        cold_named = cold_named or (f[0] == "Freshly bathed" and is_equal_approx(f[1], Defs.BATH_COLD_MOOD));
    _expect("a cold bath is worth less (mood and protection)", cold_named and Defs.BATH_COLD_MOOD < Defs.BATH_MOOD and p.clean_factor() > Defs.BATH_ILLNESS_MULT and p.clean_factor() < 1.0);
    p.clean_until = 0.0;
    p.bath_until = 0.0;
    _expect("it wears off", is_equal_approx(p.clean_factor(), 1.0));
    var d:Dictionary = p.to_dict();
    p.bath_day = 7;
    p.restore(world, d);
    _expect("the bath is saved", p.bath_day == -1);
    # the Open switch
    _bath.settings["open"] = false;
    _expect("closed: not open, no firewood wanted, nobody due", not _bath.is_open() and _bath.inputs_wanted().is_empty() and world.pawns.all(func(q:Pawn) -> bool: return not q.bath_due()));
    _bath.settings["open"] = true;
    _bath.input_incoming.clear();
    _expect("open again: it wants firewood", _bath.inputs_wanted().has(&"firewood"));
    var arbor:Building = world.place_building(&"arbor", TestSite.spot(world, Vector2i(2, 2), Vector2i(-4, 10)), Vector2i(2, 2), true);
    _expect("an arbor can be closed too", arbor.is_open() and (func() -> bool:
        arbor.settings["open"] = false;
        var closed:bool = not arbor.is_open();
        arbor.settings["open"] = true;
        return closed).call());
    # a live bath: the first day this bather's turn comes round (and she feels like it), at the start of the bath hours
    _bather = world.pawns[1];
    var id3:int = _bather.get_instance_id() % Defs.BATH_EVERY;
    _day = 3 * GameClock.DAYS_PER_SEASON;
    while ((_day + id3) % Defs.BATH_EVERY != 0) or hash(Vector3i(_bather.get_instance_id() % 100003, _day, 11)) % 100 >= Defs.BATH_SHARE:
        _day += 1;
    GameClock.total_hours = _day * GameClock.HOURS_PER_DAY + Defs.BATH_FROM - 0.2;
    Weather.reset();
    Weather._day_offset = 0.0;
    Weather._update_temperature();
    for q in world.pawns:
        q.clear_carry();
        q.end_task(false);
    GameClock.set_speed(3);
    Engine.time_scale = 6.0;
    _phase = 1;

func _process(_delta:float) -> void:
    if _phase == 0 or _phase == 9:
        return;
    for q in world.pawns:
        q.hunger = 1.0; q.thirst = 1.0; q.warmth = 1.0; q.health = 1.0;
        q.energy = 1.0;
    if not _set:                      # (the jump of the clock spoiled the stock and moved the day on: stock again)
        _set = true;
        _bath.input_incoming.clear();
        _bath.inputs[&"firewood"] = 4;
        _start = GameClock.total_hours;
        _bather.bath_day = -1;
        _bather.bath_until = 0.0;
        _bather.clean_until = 0.0;
        return;
    var hours:float = GameClock.total_hours - _start;
    if _phase == 1:
        if _bather.bath_until > _start:
            var named:bool = false;
            for f in _bather.happiness_factors():
                named = named or f[0] == "Freshly bathed";
            _expect("the bather bathed (%.1f h in): mood lift and protection" % hours, named and _bather.clean_factor() < 1.0);
            _expect("it used hot water (firewood left %d, %.2f of the next)" % [_bath.input_amount(&"firewood"), _bath.bath_acc], _bath.input_amount(&"firewood") < 4 or _bath.bath_acc > 0.0);
            _expect("and she came out", not (_bather.indoors and is_same(_bather.shelter, _bath)));
            # now close it on the next bath day she is due and see her leave
            _day += Defs.BATH_EVERY;
            while hash(Vector3i(_bather.get_instance_id() % 100003, _day, 11)) % 100 >= Defs.BATH_SHARE:
                _day += Defs.BATH_EVERY;
            GameClock.total_hours = _day * GameClock.HOURS_PER_DAY + Defs.BATH_FROM - 0.2;
            _bather.bath_day = -1;
            _bather.bath_until = 0.0;
            _bather.end_task(false);
            _set = false;
            _phase = 2;
            return;
        if hours > 6.0:
            print("FAIL the bather never bathed (task %s, due %s)" % [_bather.task.kind if _bather.task != null else "-", str(_bather.bath_due())]);
            _phase = 9;
            get_tree().quit(1);
        return;
    if _phase == 2:
        if not _set:
            _set = true;
            _start = GameClock.total_hours;
            _bather.bath_day = -1;
            _bather.bath_until = 0.0;
            _bath.settings["open"] = true;
            return;
        if _bather.task != null and _bather.task.kind == &"bath" and _bather.indoors:
            _bath.settings["open"] = false;
            _phase = 3;
            _start = GameClock.total_hours;
            return;
        if GameClock.total_hours - _start > 6.0:
            print("FAIL she never went in the second time");
            _phase = 9;
            get_tree().quit(1);
        return;
    if _phase == 3:
        if _bather.task == null or _bather.task.kind != &"bath":
            _expect("closing the bathhouse sent the bather out (%.1f h)" % (GameClock.total_hours - _start), not (_bather.indoors and is_same(_bather.shelter, _bath)) and _bather.bath_until <= _start);
            print("BATHHOUSE %s" % ("PASS" if _fails == 0 else "FAIL"));
            _phase = 9;
            get_tree().quit(1 if _fails > 0 else 0);
        elif GameClock.total_hours - _start > 3.0:
            print("FAIL the bather was still bathing 3 hours after it closed");
            _phase = 9;
            get_tree().quit(1);

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
    else:
        print("ok: " + what);
