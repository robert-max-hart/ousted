# ----------------------------------------------------------------
# Fire probe (not a pass/fail test): how a big forest fire goes with and
# without people fighting it, in normal weather and in a drought, to
# tune the spread rates and the strength of a bucket. Prints a table.
#     godot --headless --path . --fixed-fps 60 res://tests/fire_probe.tscn
# ----------------------------------------------------------------
extends Node;

const RUNS:Array = [
    {"name": "normal weather, nobody fights", "drought": false, "fighters": 0, "rule": 2},
    {"name": "normal weather, 8 fight", "drought": false, "fighters": 8, "rule": 2},
    {"name": "drought, nobody fights", "drought": true, "fighters": 0, "rule": 2},
    {"name": "drought, 8 fight", "drought": true, "fighters": 8, "rule": 2},
    {"name": "drought, Extreme, nobody fights", "drought": true, "fighters": 0, "rule": 4},
    {"name": "drought, Extreme, 8 fight", "drought": true, "fighters": 8, "rule": 4},
];

var world:World;
var _run:int = -1;
var _start:float = 0.0;
var _grove:Array[ResourceNode] = [];
var _peak:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    Weather.drought_enabled = false;
    GameRules.reset();
    GameRules.illness = 0;
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    await get_tree().process_frame;
    for b in world.buildings.duplicate():
        if b.def_id == &"cart":
            world.remove_building(b, false);
    GameClock.hour_changed.disconnect(Weather._on_hour);
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON + 3) * GameClock.HOURS_PER_DAY + 9.0;
    await get_tree().process_frame;
    await get_tree().process_frame;
    Engine.time_scale = 4.0;
    _next();

func _next() -> void:
    _run += 1;
    if _run >= RUNS.size():
        Engine.time_scale = 1.0;
        get_tree().quit();
        return;
    var r:Dictionary = RUNS[_run];
    GameClock.set_speed(0);
    for e in world.fires.cells.keys():
        world.fires.cells.erase(e);
    world.fires.fighters.clear();
    world.fires.scorch.clear();
    world.fires.buckets = 0;
    Weather.reset();
    Weather._day_offset = 0.0;
    Weather._update_temperature();
    Weather.drought_days = 5 if r["drought"] else 0;
    world.wetness = 0.12 if r["drought"] else 0.45;
    GameRules.fires = r["rule"];
    world.fire_tasks.max_fighters = r["fighters"];
    var o:Vector2i = TestSite.near(world, Vector2i(14, 6), Vector2i(20, 18));
    world.terrain.flatten_rect(Rect2i(o - Vector2i(1, 1), Vector2i(22, 20)));
    for rn in world.nodes.duplicate():
        if Rect2i(o - Vector2i(2, 2), Vector2i(24, 22)).has_point(rn.cell):
            world.remove_node(rn);
    _grove.clear();
    var rng:RandomNumberGenerator = RandomNumberGenerator.new();
    rng.seed = 100 + _run;
    for dz in 14:
        for dx in 14:
            if rng.randf() < 0.55:
                _grove.append(world.add_node(&"tree", o + Vector2i(3 + dx, 2 + dz)));
    var well_at:Vector2i = TestSite.spot(world, Vector2i(2, 2), o - TestSite.anchor(world) + Vector2i(0, 18));
    world.place_building(&"well", well_at, Vector2i(2, 2), true);
    for p in world.pawns:
        p.clear_carry();
        p.end_task(false);
    var mid:ResourceNode = _grove[_grove.size() / 2];
    world.fires.ignite(mid.cell);
    _peak = 0;
    _start = GameClock.total_hours;
    GameClock.set_speed(3);

func _process(_delta:float) -> void:
    if _run < 0 or _run >= RUNS.size():
        return;
    for p in world.pawns:
        p.hunger = 1.0; p.thirst = 1.0; p.energy = 1.0; p.warmth = 1.0;
    _peak = maxi(_peak, world.fires.wild_cell_count());
    var elapsed:float = GameClock.total_hours - _start;
    if not world.fires.wild_burning() or elapsed > 48.0:
        var gone:int = _grove.filter(func(rn:ResourceNode) -> bool: return rn.removed).size();
        print("PROBE %-34s: %2d of %d trees burned, peak %2d cells, %.1f h, %2d buckets" % [RUNS[_run]["name"], gone, _grove.size(), _peak, elapsed, world.fires.buckets]);
        _next();
