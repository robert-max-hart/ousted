# ----------------------------------------------------------------
# Homelessness test
#     The Town Hall shelters no one, homeless adults put up shacks (or
#     take a house or an empty shack first), the policy turns that off,
#     shack dwellers move into a house with room, demolishing a shack
#     refunds nothing, the mood, warmth and sleep penalties, and any adult
#     caring for a homeless baby.
#     godot --headless --path . --fixed-fps 60 res://tests/homeless.tscn
# ----------------------------------------------------------------
extends Node;

var world:World;
var baby:Pawn;
var shack:Building;
var _stage:int = 0;
var _start:float = 0.0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    Engine.time_scale = 4.0;
    Defs.ageing_days_per_year = 400.0;
    for p in world.pawns:
        p.profession = JobManager.Profession.LABORER;
        p.age = 30.0;
    world.jobs.sync_targets();
    _expect("the Town Hall has no beds", not world.town_hall.def.has("beds"));
    var a:Pawn = world.pawns[0];
    var b:Pawn = world.pawns[1];
    var c:Pawn = world.pawns[2];
    _expect("everyone starts homeless", world.pawns.all(func(p:Pawn) -> bool: return p.home == null));
    _expect("a homeless citizen has nowhere to sleep", world.shelter_for(a) == null);
    _expect("the HUD count sees them", world.families.homeless_count() == World.START_PAWNS);
    # too soon
    world.families._build_shacks();
    _expect("no shack before %d hours homeless" % Defs.SHACK_AFTER_HOURS, world.buildings.all(func(x:Building) -> bool: return not x.def.get("shack", false)));
    a.homeless_hours = 100.0;
    world.families._build_shacks();
    _expect("a homeless citizen gets a shack", a.home != null and a.home.def.get("shack", false) and a.home.residents == [a]);
    shack = a.home;
    _expect("it is a 2x2 shack costing 3 wood and 1 work-hour", shack.size == Vector2i(2, 2) and shack.cost() == {&"wood": 3} and is_equal_approx(shack.work_required(), 1.0));
    _expect("it is under construction", not shack.is_complete());
    _expect("two beds", shack.def["beds"] == 2);
    b.homeless_hours = 100.0;
    world.families._build_shacks();
    _expect("the next citizen shares it", b.home == shack and shack.residents.size() == 2);
    # a third needs a new shack, and a shack with room is reused before a new one is put up
    c.homeless_hours = 100.0;
    world.families._build_shacks();
    _expect("the third gets a new shack", c.home != null and c.home != shack and c.home.def.get("shack", false));
    world.families.move_home(a, null);
    a.homeless_hours = 100.0;
    var count:int = world.buildings.size();
    world.families._build_shacks();
    _expect("a shack with room is reused", a.home != null and a.home.residents.size() == 2 and world.buildings.size() == count);
    world.families.move_home(a, null);
    a.homeless_hours = 0.0;
    c.homeless_hours = 0.0;
    # a house with room beats a shack
    var th:Building = world.town_hall;
    var house:Building = world.place_building(&"house", th.origin + Vector2i(-8, 2), Vector2i(3, 3), true);
    _expect("completing a house moved people out of homelessness", house.residents.size() > 0 and house.residents.size() <= 6);
    var shack_dwellers:int = 0;
    for p in world.pawns:
        if world.families.lives_in_shack(p):
            shack_dwellers += 1;
    _expect("nobody stays in a shack while a house has room (%d left)" % shack_dwellers, shack_dwellers == 0 or house.residents.size() == 6);
    # the real shack and its refund
    var done:Building = world.place_building(&"shack", th.origin + Vector2i(10, 8), Vector2i(2, 2));
    done.delivered = {&"wood": 3};
    done.complete();
    var wood:int = Stock.amount(&"wood");
    _expect("a finished shack holds 3 wood of materials", done.all_delivered() == {&"wood": 3});
    world.remove_building(done, true);
    _expect("demolishing a shack refunds nothing (wood %d -> %d)" % [wood, Stock.amount(&"wood")], Stock.amount(&"wood") == wood);
    _check_penalties();
    # a homeless baby is looked after by any adult
    baby = Pawn.new();
    baby.setup(world, world.nav.nearest_walkable(th.origin + Vector2i(0, 6), 6), world.rng);
    baby.age = 1.0;
    world.add_pawn(baby);
    baby.hunger = 0.3;
    baby.thirst = 0.3;
    for p in world.pawns:
        if p != baby:
            p.hunger = 1.0; p.thirst = 1.0; p.energy = 1.0; p.homeless_hours = 0.0;
    _start = GameClock.total_hours;
    GameClock.set_speed(3);
    _stage = 1;

func _factor(p:Pawn, label:String) -> float:
    for f in p.happiness_factors():
        if f[0] == label:
            return f[1];
    return 0.0;

func _check_penalties() -> void:
    var p:Pawn = world.pawns[3];
    world.families.move_home(p, null);
    p.homeless_hours = 0.0;
    var fresh:float = _factor(p, "No home");
    p.homeless_hours = Defs.HOMELESS_MOOD_DAYS * 24.0;
    var long:float = _factor(p, "No home");
    _expect("being homeless costs %d%% at first (%.2f)" % [Defs.HOMELESS_MOOD.x * 100.0, fresh], is_equal_approx(fresh, -Defs.HOMELESS_MOOD.x));
    _expect("and %d%% after %d days (%.2f)" % [Defs.HOMELESS_MOOD.y * 100.0, Defs.HOMELESS_MOOD_DAYS, long], is_equal_approx(long, -Defs.HOMELESS_MOOD.y));
    Weather.temperature = 0.0;
    _expect("sleeping out in the cold costs more", _factor(p, "Sleeping in the cold") < 0.0);
    Weather.temperature = 20.0;
    _expect("not in warm weather", _factor(p, "Sleeping in the cold") == 0.0);
    var s:Building = world.place_building(&"shack", world.town_hall.origin + Vector2i(10, 12), Vector2i(2, 2), true);
    world.families.move_home(p, s);
    _expect("a shack dweller has the shack penalty, not the homeless one", _factor(p, "Lives in a shack") == -Defs.SHACK_MOOD and _factor(p, "No home") == 0.0);
    # warmth at 0 C: outside falls fast, a shack slowly, a heated house rises
    Weather.temperature = 0.0;
    var outside:float = _warmth_change(p, null);
    var in_shack:float = _warmth_change(p, s);
    _expect("outside at 0 C warmth falls (%.3f)" % outside, outside < 0.0);
    _expect("a shack falls less or rises (%.3f vs %.3f)" % [in_shack, outside], in_shack > outside);
    Weather.temperature = -8.0;
    _expect("a shack at -8 C still loses warmth, slower than outside (%.3f)" % _warmth_change(p, s), _warmth_change(p, s) < 0.0 and _warmth_change(p, s) > _warmth_change(p, null));
    Weather.temperature = 5.0;
    _expect("a shack at 5 C gives some warmth", _warmth_change(p, s) > 0.0);
    # sleeping outside restores half as fast
    p.energy = 0.2;
    p.sleeping = true;
    p.indoors = false;
    p._update_needs(1.0);
    var outdoors:float = p.energy;
    p.energy = 0.2;
    p.indoors = true;
    p.shelter = s;
    p._update_needs(1.0);
    var bed:float = p.energy;
    p.indoors = false;
    p.shelter = null;
    p.sleeping = false;
    _expect("sleeping outside recovers half as much (%.3f vs %.3f)" % [outdoors - 0.2, bed - 0.2], absf((outdoors - 0.2) * 2.0 - (bed - 0.2)) < 0.005);
    world.families.move_home(p, null);

func _warmth_change(p:Pawn, in_shack:Building) -> float:
    p.warmth = 0.5;
    p.indoors = in_shack != null;
    p.shelter = in_shack;
    p._update_needs(1.0);
    p.indoors = false;
    p.shelter = null;
    return p.warmth - 0.5;

func _process(_delta:float) -> void:
    if _stage != 1:
        return;
    for p in world.pawns:
        if p != baby:
            p.hunger = maxf(p.hunger, 0.8); p.thirst = maxf(p.thirst, 0.8); p.energy = maxf(p.energy, 0.5);
    var hours:float = GameClock.total_hours - _start;
    if baby.hunger > 0.7 and baby.thirst > 0.7:
        _expect("an adult fed and watered the homeless baby within %.1f hours" % hours, true);
        _stage = 2;
        quit_later();
    elif hours > 14.0:
        _expect("the homeless baby was looked after (hunger %.2f, thirst %.2f)" % [baby.hunger, baby.thirst], false);
        _stage = 2;
        quit_later();

func quit_later() -> void:
    get_tree().quit();

func _expect(what:String, ok:bool) -> void:
    print("%s: %s" % ["PASS" if ok else "FAIL", what]);
