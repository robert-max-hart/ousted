# ----------------------------------------------------------------
# Thunderstorm
#     A warm rain spell is sometimes a storm (never in the cold); a
#     storm builds up, flashes, is saved, is named in the weather and
#     the log, and sends citizens with a home indoors until it passes.
#     godot --headless --path . --fixed-fps 60 res://tests/thunderstorm.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;
var world:World;
var _phase:int = 0;
var _start:float = 0.0;
var _homed:Array[Pawn] = [];
var _flashes:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    Weather.drought_enabled = false;
    GameRules.reset();
    GameRules.illness = 0;
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    GameClock.hour_changed.disconnect(Weather._on_hour);        # the test steps the weather itself
    # the rule: spells that start warm are storms now and then, cold ones never
    var summer:float = (GameClock.DAYS_PER_SEASON * 1 + 3) * GameClock.HOURS_PER_DAY + 15.0;
    var winter:float = (GameClock.DAYS_PER_SEASON * 3 + 3) * GameClock.HOURS_PER_DAY + 15.0;
    var warm:Vector2i = _count_spells(summer);
    var cold:Vector2i = _count_spells(winter);
    _expect("some warm spells are storms (%d of %d)" % [warm.x, warm.y], warm.y > 100 and float(warm.x) / warm.y > 0.15 and float(warm.x) / warm.y < 0.45);
    _expect("no cold spell is a storm (%d of %d)" % [cold.x, cold.y], cold.y > 30 and cold.x == 0);
    # climates: more in the tropics, fewer in the desert and the north
    var shares:Dictionary = {};
    for id in [Climate.Id.TEMPERATE, Climate.Id.TROPICAL, Climate.Id.DESERT, Climate.Id.ARCTIC]:
        Climate.current = id;
        shares[id] = Weather.storm_chance();
    Climate.current = Climate.Id.TEMPERATE;
    _expect("tropical maps storm more, desert and arctic less (%s)" % str(shares), shares[Climate.Id.TROPICAL] > shares[Climate.Id.TEMPERATE] * 1.5 and shares[Climate.Id.DESERT] < shares[Climate.Id.TEMPERATE] * 0.6 and shares[Climate.Id.ARCTIC] < shares[Climate.Id.DESERT]);
    Climate.current = Climate.Id.TROPICAL;
    var trop:Vector2i = _count_spells(summer);
    Climate.current = Climate.Id.TEMPERATE;
    _expect("and they do (%d of %d)" % [trop.x, trop.y], trop.y > 100 and float(trop.x) / trop.y > 0.45);
    _expect("the work policy is off by default", not world.policies.is_on(&"storm_work"));
    # the build-up, flashes and the name
    Weather.reset();
    GameClock.total_hours = summer;
    GameClock.set_speed(1);
    Weather.is_raining = true;
    Weather.intensity = 1.0;
    Weather._set_storm(true);
    Weather.lightning.connect(func(s:float) -> void:
        _flashes += 1;
        _expect("a flash has a strength (%.2f)" % s, s >= 0.5 and s <= 1.0));
    _expect("it starts calm", Weather.storm_level == 0.0 and not Weather.is_storming());
    for i in range(200):
        Weather._update_storm(1.0);
    _expect("it builds to full (%.2f)" % Weather.storm_level, is_equal_approx(Weather.storm_level, 1.0) and Weather.is_storming());
    _expect("with flashes (%d in 200 s)" % _flashes, _flashes >= 8 and _flashes <= 45);
    _expect("it is called a thunderstorm", Weather.description() == "Thunderstorm");
    var saved:Dictionary = Weather.save_state();
    Weather.reset();
    _expect("a new game is calm", not Weather.storm and Weather.storm_level == 0.0);
    Weather.restore_state(saved);
    _expect("it is saved", Weather.storm and Weather.is_raining and is_equal_approx(Weather.storm_level, 1.0));
    Weather.is_raining = false;
    var before:int = _flashes;
    for i in range(30):
        Weather._update_storm(1.0);
    _expect("it dies with the rain (%.2f, %d new flashes after the first seconds)" % [Weather.storm_level, _flashes - before], Weather.storm_level < 0.01);
    Weather.restore_state({"is_raining": false, "intensity": 0.0, "day_offset": 0.0, "storm": true, "storm_level": 1.0});
    _expect("a saved storm without rain is dropped", not Weather.storm);
    _expect("the thunder sounds exist", Sfx.has(&"thunder"));
    # citizens go home
    GameClock.set_speed(0);
    for b in world.buildings.duplicate():
        if b.def_id == &"cart":
            world.remove_building(b, false);
    var k:int = 0;
    for p in world.pawns:
        if not p.is_adult():
            continue;
        var at:Vector2i = TestSite.spot(world, Vector2i(3, 3), Vector2i(-10 + k * 4, 10));
        var h:Building = world.place_building(&"house", at, Vector2i(3, 3), true);
        if h != null:
            world.families.move_home(p, h);
            _homed.append(p);
        k += 1;
        if k >= 4:
            break;
    _expect("some citizens have homes", _homed.size() >= 3);
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON * 1 + 3) * GameClock.HOURS_PER_DAY + 9.0;
    Weather.is_raining = true;
    Weather.intensity = 1.0;
    Weather.storm = true;
    Weather.storm_level = 1.0;
    for p in world.pawns:
        p.clear_carry();
        p.end_task(false);
    GameClock.set_speed(3);
    Engine.time_scale = 4.0;
    _start = GameClock.total_hours;
    _phase = 1;

# Starts many spells at the given time: (how many were storms, how many spells).
func _count_spells(at_hours:float) -> Vector2i:
    Weather.reset();
    GameClock.total_hours = at_hours;
    var spells:int = 0;
    var tally:Array[int] = [0];          # (a lambda copies plain numbers, so the count lives in an array)
    var cb:Callable = func(on:bool) -> void:
        if on:
            tally[0] += 1;
    Weather.storm_changed.connect(cb);
    for i in range(30000):
        var was:bool = Weather.is_raining;
        Weather._on_hour(0);
        if Weather.is_raining and not was:
            spells += 1;
    Weather.storm_changed.disconnect(cb);
    return Vector2i(tally[0], spells);

func _process(_delta:float) -> void:
    if _phase == 0:
        return;
    for p in world.pawns:
        p.hunger = 1.0; p.thirst = 1.0; p.warmth = 1.0; p.health = 1.0; p.energy = 1.0;
    var elapsed:float = GameClock.total_hours - _start;
    if _phase == 1 and elapsed >= 3.0:
        var inside:int = 0;
        for p in _homed:
            if p.indoors and is_same(p.shelter, p.home):
                inside += 1;
        _expect("in the storm they are all at home (%d of %d)" % [inside, _homed.size()], inside == _homed.size());
        Weather.storm = false;
        Weather.is_raining = false;
        Weather.intensity = 0.0;
        _start = GameClock.total_hours;
        _phase = 2;
    elif _phase == 2 and elapsed >= 3.0:
        var out:int = 0;
        for p in _homed:
            if not p.indoors:
                out += 1;
        var kinds:Array = _homed.map(func(p:Pawn) -> String: return "%s/%s/%s" % [p.task.kind if p.task != null else "-", p.indoors, Weather.storm_level]);
        _expect("%s" % "the work policy has a rule", Defs.POLICIES.has(&"storm_work"));
        _expect("when it has passed some are out working again (%d of %d: %s)" % [out, _homed.size(), kinds], out >= 1);
        world.policies.set_on(&"storm_work", true);
        for p in _homed:
            p.go_inside(p.home, false);
            p.end_task(false);
        Weather.is_raining = true;
        Weather.intensity = 1.0;
        Weather.storm = true;
        Weather.storm_level = 1.0;
        _start = GameClock.total_hours;
        _phase = 3;
    elif _phase == 3 and elapsed >= 2.0:
        var working:int = 0;
        for p in _homed:
            if not p.indoors:
                working += 1;
        _expect("with the policy on they work through the storm (%d of %d out)" % [working, _homed.size()], working >= 1);
        print("THUNDERSTORM %s" % ("PASS" if _fails == 0 else "FAIL"));
        Engine.time_scale = 1.0;
        get_tree().quit(1 if _fails > 0 else 0);
        _phase = 4;

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
