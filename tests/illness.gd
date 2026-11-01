# ----------------------------------------------------------------
# Illness
#     Sickness: a case slows work and wears health down, recovers faster
#     with rest and a healer's visit (much faster with herbs), spreads
#     between housemates, leaves immunity, is saved, and obeys the
#     Illness rule and the quarantine policy; a Herbalist's Hut sends its
#     healer to the sick and uses herbs from its store.
#     godot --headless --path . --fixed-fps 60 res://tests/illness.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;
var world:World;
var _hut:Building;
var _healer:Pawn;
var _patient:Pawn;
var _start:float = 0.0;
var _phase:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    Weather.drought_enabled = false;
    GameRules.reset();
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    Weather._day_offset = 0.0;
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON * 1 + 2) * GameClock.HOURS_PER_DAY + 8.0;
    Weather._update_temperature();
    var herbs:int = 0;
    for rn in world.nodes:
        if rn.kind == &"herb":
            herbs += 1;
    _expect("healing herbs grow wild (%d)" % herbs, herbs >= 20 and Defs.RESOURCE_NODES[&"herb"]["item"] == &"herbs" and not Defs.is_food(&"herbs"));
    _expect("the forager's hut has a herb toggle and cap", _control_ids(&"forager").has("forage_herb") and _control_ids(&"forager").has("cap_herbs"));
    _expect("the Herbalist's Hut is buildable and keeps herbs", Defs.BUILD_MENU.has(&"herbalist") and Defs.BUILDINGS[&"herbalist"]["inputs"].has(&"herbs"));
    _expect("Healer is a profession", JobManager.PROFESSION_NAMES.has("Healer") and JobManager.Profession.HEALER == JobManager.PROFESSION_NAMES.find("Healer"));
    _expect("quarantine is a policy", Defs.POLICIES.has(&"quarantine") and not world.policies.is_on(&"quarantine"));

    # --- one citizen
    var p:Pawn = world.pawns[0];
    p.hunger = 1.0; p.warmth = 1.0; p.health = 1.0;
    _expect("a well citizen works at full speed", is_equal_approx(Illness.work_factor(p), 1.0));
    _expect("a citizen can be infected", world.illness.infect(p) and p.illness >= 0.2);
    var eff:float = Illness.work_factor(p);
    _expect("the sick work slower (%.2f)" % eff, eff < 1.0);
    _expect("a case is counted", world.illness.ill_count() == 1);
    p.illness = 0.6;
    _expect("a bad case rests at home", Illness.must_rest(p));
    p.illness = 0.2;
    _expect("a mild case keeps working", not Illness.must_rest(p));
    world.policies.set_on(&"quarantine", true);
    _expect("quarantine keeps any case home", Illness.must_rest(p));
    world.policies.set_on(&"quarantine", false);
    var hours_plain:float = _hours_to_recover(0.6, false, false, 0.0);
    var hours_rest:float = _hours_to_recover(0.6, true, false, 0.0);
    var hours_care:float = _hours_to_recover(0.6, true, true, 0.0);
    var hours_herbs:float = _hours_to_recover(0.6, true, true, 1.0);
    _expect("rest helps (%.0f h against %.0f h)" % [hours_rest, hours_plain], hours_rest < hours_plain);
    _expect("a visit without herbs helps a little (%.0f h)" % hours_care, hours_care < hours_rest and hours_care > hours_rest * 0.7);
    _expect("herbs help a great deal (%.0f h)" % hours_herbs, hours_herbs < hours_rest * 0.5);
    var loss_plain:float = _health_lost(0.9, true, false, 0.0);
    var loss_herbs:float = _health_lost(0.9, true, true, 1.0);
    _expect("a grave case untreated nearly kills (%.2f health lost)" % loss_plain, loss_plain > 0.5);
    _expect("herbs spare most of it (%.2f)" % loss_herbs, loss_herbs < loss_plain * 0.5);
    # recovery gives immunity
    p.illness = 0.021; p.care_until = 0.0;
    Illness.tick(p, 1.0);
    _expect("a recovered citizen is well and immune", p.illness == 0.0 and not world.illness.can_catch(p));
    GameClock.total_hours += (Illness.IMMUNE_DAYS + 1.0) * GameClock.HOURS_PER_DAY;
    _expect("immunity wears off", world.illness.can_catch(p));
    # save
    p.illness = 0.5; p.care_until = GameClock.total_hours + 5.0; p.care_quality = 1.0; p.immune_until = 77.0;
    var d:Dictionary = p.to_dict();
    p.illness = 0.0; p.care_until = 0.0; p.care_quality = 0.0; p.immune_until = 0.0;
    p.restore(world, d);
    _expect("the case is saved", p.illness == 0.5 and p.care_quality == 1.0 and p.immune_until == 77.0 and p.care_until > GameClock.total_hours);
    _expect("the inspector says so", p.info_text().contains("ill") and p.info_text().contains("herbs"));
    p.illness = 0.0; p.care_until = 0.0;

    # --- the rule and spread
    GameRules.illness = 0;
    for i in 400:
        world.illness.on_day();
    _expect("with the rule on None nobody falls ill", world.illness.ill_count() == 0);
    GameRules.illness = 4;
    var cases:int = 0;
    for i in 30:
        world.illness.on_day();
        cases += world.illness.ill_count();
        for q in world.pawns:
            q.illness = 0.0; q.immune_until = 0.0;
    _expect("at Plague level cases start by themselves (%d)" % cases, cases > 0);
    GameRules.illness = 2;
    var mates:Array[Pawn] = [world.pawns[1], world.pawns[2], world.pawns[3]];
    var house:Building = world.place_building(&"house", TestSite.spot(world, Vector2i(3, 3), Vector2i(0, 12)), Vector2i(3, 3), true);
    for m in mates:
        m.home = house;
        house.residents.append(m);
        m.illness = 0.0; m.immune_until = 0.0;
    mates[0].illness = 0.9;
    for i in 80:
        world.illness.on_hour();
    var caught:int = 0;
    for m in mates:
        if m.illness > 0.0:
            caught += 1;
    _expect("housemates catch it (%d of 3 ill)" % caught, caught >= 2);
    for q in world.pawns:
        q.illness = 0.0; q.immune_until = 0.0;

    # --- the hut and the healer
    var o:Vector2i = TestSite.spot(world, Vector2i(3, 3), Vector2i(-6, -9));
    _hut = world.place_building(&"herbalist", o, Vector2i(3, 3), true);
    _healer = world.pawns[4];
    _healer.profession = JobManager.Profession.HEALER;
    world.jobs.sync_targets();
    _patient = world.pawns[5];
    _patient.home = null;
    _patient.illness = 0.6;
    _hut.add_input(&"herbs", 3);
    for q in world.pawns:
        if q != _healer and q != _patient:
            q.profession = JobManager.Profession.LABORER;
    GameRules.illness = 0;          # (so the patient does not pass it on)
    GameClock.set_speed(3);
    Engine.time_scale = 4.0;
    _start = GameClock.total_hours;
    _phase = 1;

func _control_ids(id:StringName) -> Array:
    return (Defs.BUILDINGS[id]["controls"] as Array).map(func(c:Dictionary) -> String: return c["id"]);

func _make_sick(sev:float, indoors:bool, cared:bool, quality:float) -> Pawn:
    var p:Pawn = world.pawns[0];
    p.hunger = 1.0; p.warmth = 1.0; p.health = 1.0;
    p.illness = sev;
    p.indoors = indoors;
    p.age = 25.0;
    p.care_until = GameClock.total_hours + 1000.0 if cared else 0.0;
    p.care_quality = quality;
    return p;

func _hours_to_recover(sev:float, indoors:bool, cared:bool, quality:float) -> float:
    var p:Pawn = _make_sick(sev, indoors, cared, quality);
    var h:float = 0.0;
    while p.illness > 0.0 and h < 1000.0:
        Illness.tick(p, 1.0);
        h += 1.0;
    p.indoors = false;
    p.immune_until = 0.0;
    return h;

func _health_lost(sev:float, indoors:bool, cared:bool, quality:float) -> float:
    var p:Pawn = _make_sick(sev, indoors, cared, quality);
    var lost:float = 0.0;
    var h:float = 0.0;
    while p.illness > 0.0 and h < 1000.0:
        lost += Illness.tick(p, 1.0);
        h += 1.0;
    p.indoors = false;
    p.immune_until = 0.0;
    return lost;

func _process(_delta:float) -> void:
    if _phase != 1:
        return;
    for p in world.pawns:
        p.hunger = 1.0; p.thirst = 1.0; p.energy = 1.0; p.warmth = 1.0; p.health = 1.0;
    var hours:float = GameClock.total_hours - _start;
    if _patient.care_until > GameClock.total_hours or hours > 60.0:
        _expect("the healer tended the patient (%.0f h)" % hours, _patient.care_until > GameClock.total_hours);
        _expect("with herbs from the hut (quality %.1f, %d left)" % [_patient.care_quality, _hut.input_amount(&"herbs")], _patient.care_quality >= 0.5 and _hut.input_amount(&"herbs") == 2);
        print("ILLNESS %s" % ("PASS" if _fails == 0 else "FAIL"));
        get_tree().quit(1 if _fails > 0 else 0);
        _phase = 2;

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
