# ----------------------------------------------------------------
# Fire life
#     Citizens and fire in a running world: a cold citizen with no warm
#     place lights a campfire (using firewood from storage) and warms
#     up beside it, and when a wildfire breaks out the citizens run from
#     it, the able ones fetch water and fight it, and it is put out.
#     godot --headless --path . --fixed-fps 60 res://tests/fire_life.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;
var world:World;
var _phase:int = 0;
var _start:float = 0.0;
var _cold:Pawn;
var _grove:Array[ResourceNode] = [];
var _wood_before:int = 0;

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
    # a cold morning: -3 C, nothing falling, nobody has a home, firewood in the Town Hall
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON * 3 + 3) * GameClock.HOURS_PER_DAY + 9.0;
    Weather.reset();
    Weather._day_offset = 0.0;
    Weather._update_temperature();
    world.town_hall.upgrades_done.erase(&"heating");        # (no heated place for anyone)
    world.town_hall.store(&"firewood", 30);
    _wood_before = world.town_hall.amount(&"firewood");
    _cold = world.pawns[0];
    _cold.warmth = 0.2;
    for p in world.pawns:
        p.clear_carry();
        p.end_task(false);
        p.hunger = 1.0; p.thirst = 1.0; p.energy = 1.0;
    var camp_task:Task = world.jobs.needs.warm_task(_cold);
    _expect("a cold citizen with no warm place gets a campfire task (%s)" % (camp_task.label if camp_task != null else "none"), camp_task != null and camp_task.kind == &"camp");
    _expect("it fetches firewood first", camp_task != null and camp_task.label == "Fetching firewood");
    _cold.task = null;
    for b in world.buildings:
        if b.def.get("storage", false):
            pass;
    _cold.end_task(false);
    Engine.time_scale = 4.0;
    GameClock.set_speed(3);
    _start = GameClock.total_hours;
    _phase = 1;

func _process(_delta:float) -> void:
    if _phase == 0:
        return;
    for p in world.pawns:
        p.hunger = 1.0; p.thirst = 1.0; p.energy = 1.0;
        if p != _cold or _phase >= 2:
            p.warmth = 1.0;
    var elapsed:float = GameClock.total_hours - _start;
    if _phase == 1:
        if world.fires.camp_count() > 0 and _cold.warmth > 0.6:
            _expect("a campfire was lit and the citizen warmed up beside it (warmth %.2f)" % _cold.warmth, true);
            _expect("it used a unit of firewood from the Town Hall (%d left)" % world.town_hall.amount(&"firewood"), world.town_hall.amount(&"firewood") < _wood_before);
            _begin_wildfire();
        elif elapsed > 12.0:
            _expect("a campfire was lit and warmed the citizen within 12 hours (camps %d, warmth %.2f, task %s)" % [world.fires.camp_count(), _cold.warmth, _cold.task.kind if _cold.task != null else "none"], false);
            _finish();
    elif _phase == 2:
        if not world.fires.wild_burning():
            var gone:int = _grove.filter(func(rn:ResourceNode) -> bool: return rn.removed).size();
            print("wildfire over after %.1f h: %d of %d trees gone, %d buckets thrown, %d fighters" % [elapsed, gone, _grove.size(), world.fires.buckets, world.fires.fighters.size()]);
            _expect("citizens fought it: buckets were thrown (%d)" % world.fires.buckets, world.fires.buckets >= 3);
            _expect("and not everything burned (%d of %d trees)" % [gone, _grove.size()], gone < _grove.size());
            _expect("nobody died", world.pawns.size() >= 12);
            _finish();
        elif elapsed > 30.0:
            _expect("the fire was put out within 30 hours (%d cells, %d buckets)" % [world.fires.wild_cell_count(), world.fires.buckets], false);
            _finish();

func _begin_wildfire() -> void:
    for e in world.fires.cells.keys():
        world.fires.cells.erase(e);
    Weather.snow_depth = 0.0;
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON + 3) * GameClock.HOURS_PER_DAY + 9.0;      # a summer morning
    Weather.reset();
    Weather._update_temperature();
    world.wetness = 0.15;
    GameRules.fires = 4;
    Weather.drought_days = 3;
    var o:Vector2i = TestSite.near(world, Vector2i(12, 8), Vector2i(14, 12));
    world.terrain.flatten_rect(Rect2i(o - Vector2i(1, 1), Vector2i(16, 14)));
    for rn in world.nodes.duplicate():
        if Rect2i(o - Vector2i(2, 2), Vector2i(18, 16)).has_point(rn.cell):
            world.remove_node(rn);
    for dz in 6:
        for dx in 6:
            _grove.append(world.add_node(&"tree", o + Vector2i(4 + dx, 2 + dz)));
    var well_at:Vector2i = TestSite.spot(world, Vector2i(2, 2), o - TestSite.anchor(world) + Vector2i(0, 8));
    world.place_building(&"well", well_at, Vector2i(2, 2), true);
    for k in [2, 9, 14, 21, 28, 33]:
        world.fires.ignite(_grove[k].cell);
    for p in world.pawns:
        p.end_task(false);
    _start = GameClock.total_hours;
    _phase = 2;

func _finish() -> void:
    print("FIRE LIFE %s" % ("PASS" if _fails == 0 else "FAIL"));
    Engine.time_scale = 1.0;
    get_tree().quit(1 if _fails > 0 else 0);
    _phase = 3;

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
