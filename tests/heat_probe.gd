# ----------------------------------------------------------------
# Heat probe (not pass/fail): a desert summer with the default rest in the
# midday heat, and again with "Work through the heat" on, to see how the
# colony copes: population, how many citizens are too hot, deaths of
# heatstroke and how much work gets done (the wood stock).
#     godot --headless --path . --fixed-fps 60 res://tests/heat_probe.tscn
# ----------------------------------------------------------------
extends Node;

# (a second run in the same process starts from a clock and weather the first left behind: run it again with "work": true to compare)
const RUNS:Array = [{"name": "desert summer, rest at midday", "work": false}];
const DAYS:int = 8;

var world:World;
var _run:int = -1;
var _day_start:float = 0.0;
var _hot_samples:int = 0;
var _hot_sum:int = 0;
var _deaths:int = 0;
var _wood0:int = 0;
var _pop0:int = 0;
var _max_heat:float = 0.0;
var _max_temp:float = -99.0;
var _siesta_samples:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    Weather.drought_enabled = false;
    GameRules.reset();
    GameRules.illness = 0;
    GameRules.droughts = 0;
    GameRules.fires = 0;
    Climate.current = Climate.Id.DESERT;
    _next();

func _next() -> void:
    _run += 1;
    if world != null:
        world.queue_free();
        await get_tree().process_frame;
    if _run >= RUNS.size():
        Engine.time_scale = 1.0;
        get_tree().quit();
        return;
    World.new_game_seed = 4242;
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    await get_tree().process_frame;
    await get_tree().process_frame;
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON + 2) * GameClock.HOURS_PER_DAY + 7.0;
    Weather.reset();
    Weather._update_temperature();
    await get_tree().process_frame;
    world.policies.set_on(&"heat_work", RUNS[_run]["work"]);
    _pop0 = world.pawns.size();
    _wood0 = Stock.amount(&"wood");
    _hot_samples = 0;
    _hot_sum = 0;
    _max_heat = 0.0;
    _max_temp = -99.0;
    _siesta_samples = 0;
    _deaths = world.death_log.size();
    _day_start = GameClock.total_hours;
    Engine.time_scale = 6.0;
    GameClock.set_speed(3);

func _process(_delta:float) -> void:
    if _run < 0 or _run >= RUNS.size() or world == null or GameClock.speed() == 0.0:
        return;
    for p in world.pawns:
        p.hunger = maxf(p.hunger, 0.6);        # (only the heat is under test)
    _hot_samples += 1;
    _max_temp = maxf(_max_temp, Weather.temperature);
    for p in world.pawns:
        _max_heat = maxf(_max_heat, p.overheat);
    if world.pawns.size() > 0 and Heat.siesta_due(world.pawns[0]):
        _siesta_samples += 1;
    _hot_sum += world.pawns.filter(func(p:Pawn) -> bool: return p.overheat > Heat.SEEK_SHADE).size();
    if GameClock.total_hours - _day_start >= DAYS * 24.0:
        var heat_deaths:int = 0;
        for d in world.death_log.slice(_deaths):
            if d["cause"] == "heatstroke":
                heat_deaths += 1;
        var tasks:Dictionary = {};
        for p in world.pawns:
            var k:String = String(p.task.kind) if p.task != null else "none";
            tasks[k] = tasks.get(k, 0) + 1;
        print("HEAT %-38s: pop %d -> %d, avg %.1f too hot (worst load %.2f, max %.1f C, siesta %d%% of frames), %d heatstroke deaths, wood %d -> %d, now doing %s" % [RUNS[_run]["name"], _pop0, world.pawns.size(), float(_hot_sum) / maxf(1.0, _hot_samples), _max_heat, _max_temp, 100 * _siesta_samples / maxi(1, _hot_samples), heat_deaths, _wood0, Stock.amount(&"wood"), str(tasks)]);
        GameClock.set_speed(0);
        _next();
