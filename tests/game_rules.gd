# ----------------------------------------------------------------
# Game rules test
#     The custom rules and realism mode: the number of settlers and
#     children, the starting supplies, droughts on or off, the merchants'
#     visit chance, slower days and slower ageing in realism mode, and
#     the rules coming back from a save.
#     godot --headless --path . --fixed-fps 60 res://tests/game_rules.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    # the plain rules are what the game always was
    GameRules.reset();
    _expect("default rules: 12 settlers, 3 children, normal supplies", GameRules.settlers == 12 and GameRules.children() == 3 and GameRules.supply_share() == 1.0);
    _expect("default ageing and day length", GameRules.ageing_days() == 4.0 and GameRules.seconds_per_hour() == 7.5);
    GameClock.set_speed(1);
    var plain:float = GameClock.game_hours(1.0);
    GameRules.realism = true;
    _expect("realism: days take twice as long", is_equal_approx(GameClock.game_hours(1.0), plain / 2.0));
    _expect("realism: a citizen year is a game year", GameRules.ageing_days() == float(GameClock.DAYS_PER_YEAR));
    GameRules.reset();

    # droughts: a desert summer has them, unless the rule is off
    Climate.current = Climate.Id.DESERT;
    var seen:Dictionary = {};
    for on in [true, false]:
        GameRules.droughts = 2 if on else 0;
        Weather.drought_days = 0;
        Weather.drought_rest = 0;
        var started:int = 0;
        for d in 300:
            GameClock.total_hours = float((GameClock.DAYS_PER_SEASON + 2) * 24);       # a summer day
            Weather._on_day(d);
            if Weather.drought_days > 0:
                started += 1;
                Weather.drought_days = 0;
                Weather.drought_rest = 0;
        seen[on] = started;
    print("droughts in 300 desert summer days: %d on, %d off" % [seen[true], seen[false]]);
    _expect("droughts happen when on", seen[true] > 0);
    _expect("and never when off", seen[false] == 0);
    Climate.current = Climate.Id.TEMPERATE;
    GameRules.reset();

    # the event levels: storms scale with the slider, and old saves hold droughts as on or off
    var chances:Array[float] = [];
    for i in GameRules.EVENT_SHARES.size():
        GameRules.storms = i;
        chances.append(Weather.storm_chance());
    _expect("storm chance follows the slider (%s)" % str(chances), chances[0] == 0.0 and chances[1] < chances[2] and chances[2] < chances[3] and chances[3] < chances[4] and chances[4] <= 1.0);
    GameRules.from_dict({"droughts": false});
    _expect("an old save with droughts off is None", GameRules.droughts == 0 and GameRules.storms == 2);
    GameRules.from_dict({"droughts": true});
    _expect("an old save with droughts on is Normal", GameRules.droughts == 2);
    GameRules.droughts = 3;
    GameRules.storms = 1;
    var saved:Dictionary = GameRules.to_dict();
    GameRules.reset();
    GameRules.from_dict(saved);
    _expect("the levels are saved", GameRules.droughts == 3 and GameRules.storms == 1);
    GameRules.reset();

    # heat waves and cold snaps: by season and climate, scaled by their sliders, saved, and they move the temperature
    Weather.drought_enabled = true;
    var snaps:Dictionary = {};
    for kind in [["heat", 1, GameClock.DAYS_PER_SEASON + 2, Climate.Id.DESERT], ["cold", -1, GameClock.DAYS_PER_SEASON * 3 + 2, Climate.Id.TEMPERATE], ["cold_tropical", -1, GameClock.DAYS_PER_SEASON * 3 + 2, Climate.Id.TROPICAL]]:
        Climate.current = kind[3];
        for level in [0, 2, 4]:
            GameRules.heat = level;
            GameRules.cold = level;
            var started:int = 0;
            for d in 600:
                Weather.snap_days = 0;
                Weather.snap_rest = 0;
                GameClock.total_hours = float(kind[2] * 24);
                Weather._on_day(d);
                if Weather.snap_days > 0 and Weather.snap_dir == kind[1]:
                    started += 1;
            snaps["%s %d" % [kind[0], level]] = started;
    Weather.snap_days = 0;
    Weather.snap_rest = 0;
    print("snaps in 600 days: %s" % str(snaps));
    _expect("heat waves in a desert summer, none at None, more at Extreme", snaps["heat 0"] == 0 and snaps["heat 2"] > 0 and snaps["heat 4"] > snaps["heat 2"]);
    _expect("cold snaps in a temperate winter, none at None, more at Extreme", snaps["cold 0"] == 0 and snaps["cold 2"] > 0 and snaps["cold 4"] > snaps["cold 2"]);
    _expect("never a cold snap in the tropics", snaps["cold_tropical 4"] == 0);
    Climate.current = Climate.Id.TEMPERATE;
    GameRules.reset();
    Weather.drought_enabled = false;
    GameClock.total_hours = float((GameClock.DAYS_PER_SEASON + 2) * 24 + 12);
    Weather.reset();
    Weather._day_offset = 0.0;
    Weather._update_temperature();
    var plain_t:float = Weather.temperature;
    Weather.snap_days = 4;
    Weather.snap_dir = 1;
    Weather._update_temperature();
    _expect("a heat wave is hotter (%.1f against %.1f)" % [Weather.temperature, plain_t], is_equal_approx(Weather.temperature, plain_t + Weather.HEAT_DELTA) and Weather.description() == "Heat wave");
    Weather.snap_dir = -1;
    Weather._update_temperature();
    _expect("a cold snap is colder and named", is_equal_approx(Weather.temperature, plain_t + Weather.COLD_DELTA) and Weather.description() == "Cold snap");
    var saved_snap:Dictionary = Weather.save_state();
    Weather.reset();
    _expect("a new game has none", Weather.snap_days == 0 and Weather.snap_offset() == 0.0);
    Weather.restore_state(saved_snap);
    _expect("a spell is saved", Weather.snap_days == 4 and Weather.snap_dir == -1);
    Weather.reset();

    # rainfall: the slider scales how many spells start
    var spells:Dictionary = {};
    for level in [0, 2, 4]:
        GameRules.rain = level;
        Weather.reset();
        GameClock.total_hours = float((GameClock.DAYS_PER_SEASON + 2) * 24 + 12);
        var n:int = 0;
        for i in 8000:
            var was:bool = Weather.is_raining;
            Weather._on_hour(0);
            if Weather.is_raining and not was:
                n += 1;
        spells[level] = n;
    print("rain spells in 8000 summer hours: %s" % str(spells));
    _expect("rain: none at None, more at Torrential than Normal", spells[0] == 0 and spells[2] > 20 and spells[4] > spells[2] * 1.5);
    GameRules.reset();
    Weather.reset();
    GameRules.from_dict({});
    _expect("an older save gets normal events", GameRules.heat == 2 and GameRules.cold == 2 and GameRules.pests == 2 and GameRules.rain == 2);
    GameRules.heat = 1; GameRules.cold = 3; GameRules.pests = 0; GameRules.rain = 4;
    var rules:Dictionary = GameRules.to_dict();
    GameRules.reset();
    GameRules.from_dict(rules);
    _expect("the new levels are saved", GameRules.heat == 1 and GameRules.cold == 3 and GameRules.pests == 0 and GameRules.rain == 4);
    GameRules.reset();

    # a small, lean, realistic colony
    GameRules.start = GameRules.Start.NOTHING;
    GameRules.settlers = 6;
    GameRules.supplies = 0;
    GameRules.merchants = 0;
    GameRules.realism = true;
    Defs.difficulty = &"easy";
    GameClock.reset();
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    await get_tree().process_frame;
    var kids:int = world.pawns.filter(func(p:Pawn) -> bool: return p.age < 18.0).size();
    _expect("6 settlers, 1 of them a child (%d, %d)" % [world.pawns.size(), kids], world.pawns.size() == 6 and kids == 1);
    _expect("half the starting wheat (%d)" % Stock.amount(&"wheat"), Stock.amount(&"wheat") == roundi(World.START_STOCK[&"wheat"] * 0.5));
    _expect("realism ageing is set (%.0f days a year)" % Defs.ageing_days_per_year, Defs.ageing_days_per_year == 32.0);
    _expect("no merchant ever comes", world.traders.daily_chance() == 0.0);
    GameRules.merchants = 3;
    _expect("frequent merchants come twice as often", is_equal_approx(world.traders.daily_chance(), Traders.VISITS_PER_SEASON / GameClock.DAYS_PER_SEASON * 2.0));

    GameRules.merchants = 0;
    # the rules survive a save
    var data:Dictionary = world.serialize();
    world.queue_free();
    await get_tree().process_frame;
    GameRules.reset();
    World.pending_load = data;
    var loaded:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(loaded);
    await get_tree().process_frame;
    _expect("a loaded game keeps its rules", GameRules.settlers == 6 and GameRules.supplies == 0 and GameRules.realism and GameRules.merchants == 0 and GameRules.start == GameRules.Start.NOTHING);
    GameRules.reset();
    print("GAME RULES %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    print("%s: %s" % ["PASS" if ok else "FAIL", what]);
    if not ok:
        _fails += 1;
