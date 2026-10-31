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
        GameRules.droughts = on;
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
