# ----------------------------------------------------------------
# Hunting lodge
#     Hunters bring deer from the limited game of the woods (meat and
#     leather into the lodge's own store), skinning is slow without an
#     iron or steel tool, the game runs out and breeds back, and the
#     Snares upgrade fills the store with rabbits by itself.
#     godot --headless --path . --fixed-fps 60 res://tests/hunting_lodge.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;
var world:World;
var _lodge:HuntingLodge;
var _hunter:Pawn;
var _start:float = 0.0;
var _phase:int = 0;
var _set:bool = false;

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
    var def:Dictionary = Defs.BUILDINGS[&"hunting_lodge"];
    _expect("it is in the Food menu", Defs.BUILD_MENU.has(&"hunting_lodge") and (Defs.BUILD_CATEGORIES[2][1] as Array).has(&"hunting_lodge"));
    _expect("Hunter is a profession", JobManager.PROFESSION_NAMES.has("Hunter") and JobManager.Profession.HUNTER == JobManager.PROFESSION_NAMES.find("Hunter") and def["profession"] == "HUNTER");
    _expect("the lodge is a small store for meat and leather only", def["storage"] and (def["accepts_items"] as Array).has(&"meat") and (def["accepts_items"] as Array).has(&"leather") and not (def["accepts_items"] as Array).has(&"wheat"));
    _expect("a deer gives more than a sheep and less than a cow", HuntingLodge.DEER_MEAT > Defs.ANIMALS[&"sheep"]["meat"] and HuntingLodge.DEER_MEAT < Defs.ANIMALS[&"cow"]["meat"] and HuntingLodge.DEER_LEATHER > Defs.ANIMALS[&"sheep"]["leather"] and HuntingLodge.DEER_LEATHER < Defs.ANIMALS[&"cow"]["leather"]);
    _expect("skinning is faster with an iron tool, and steel or wood do as stated", HuntingLodge.skin_speed(0.25) == 1.0 and HuntingLodge.skin_speed(0.5) == 1.0 and HuntingLodge.skin_speed(0.1) < 1.0 and HuntingLodge.skin_speed(0.0) < 1.0);
    _expect("every climate has a game share", [0.0, 1.0].has(0.0) and Climate.game_share() > 0.0);
    for b in world.buildings.duplicate():
        if b.def_id == &"cart":
            world.remove_building(b, false);
    var o:Vector2i = TestSite.spot(world, Vector2i(4, 3), Vector2i(-8, 8));
    world.terrain.flatten_rect(Rect2i(o - Vector2i(10, 10), Vector2i(24, 24)));
    var planted:int = 0;
    for z in range(-9, 10):
        for x in range(-9, 13):
            var c:Vector2i = o + Vector2i(x, z);
            if (x * 7 + z * 3) % 5 != 0 or Rect2i(o - Vector2i(1, 1), Vector2i(6, 5)).has_point(c):
                continue;
            if world.terrain.in_bounds(c) and not world.terrain.is_water(c) and world.node_at[world.idx(c)] == null and world.occupant[world.idx(c)] == null:
                var rn:ResourceNode = world.add_node(&"oak", c);
                if rn != null:
                    rn.set_growth(1.0);
                    planted += 1;
    _lodge = world.place_building(&"hunting_lodge", o, Vector2i(4, 3), true) as HuntingLodge;
    _expect("it was built, with %d oaks around" % planted, _lodge != null and _lodge.is_complete() and planted > 30);
    world.wildlife.refresh();
    var cen:Vector2 = _lodge.circle_center();
    var t:Dictionary = world.wildlife.totals(cen, _lodge.work_radius());
    _expect("the woods hold game (%.1f deer of room, %.1f there)" % [t["cap"], t["have"]], t["cap"] >= Wildlife.MIN_CAPACITY and t["have"] > 0.0 and world.wildlife.rating(cen, _lodge.work_radius()) != "None: too few woods");
    _expect("hunting has a rate", _lodge.hunt_rate() > 0.0);
    var rate_full:float = _lodge.hunt_rate();
    # taking deer thins the woods and slows the hunt
    var taken:int = 0;
    while world.wildlife.take(cen, _lodge.work_radius()) and taken < 100:
        taken += 1;
    _expect("the game can be hunted out (%d taken)" % taken, taken >= 1 and _lodge.hunt_rate() < rate_full);
    var before:float = world.wildlife.totals(cen, _lodge.work_radius())["have"];
    for d in 12:
        world.wildlife.on_day();
    var after:float = world.wildlife.totals(cen, _lodge.work_radius())["have"];
    var cap:float = world.wildlife.totals(cen, _lodge.work_radius())["cap"];
    _expect("it breeds back (%.1f to %.1f of %.1f) but not past the room" % [before, after, cap], after > before and after <= cap + 0.001);
    var saved:Array = world.wildlife.to_array();
    var snapshot:float = after;
    world.wildlife.level.fill(0.0);
    world.wildlife.restore(saved);
    _expect("the game level is saved", absf(world.wildlife.totals(cen, _lodge.work_radius())["have"] - snapshot) < 0.01);
    # snares
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON + 3) * GameClock.HOURS_PER_DAY + 9.0;
    Weather.reset();
    Weather._day_offset = 0.0;
    Weather._update_temperature();
    Weather.snow_depth = 0.0;
    _expect("no snares, no rabbits", _lodge.snare_rate() == 0.0);
    _expect("the upgrade can be started", _lodge.upgrade_block_reason(&"snares") == "" and _lodge.start_upgrade(&"snares"));
    for item in _lodge.cost():
        _lodge.receive(item, _lodge.cost()[item]);
    _lodge.add_work(_lodge.work_required());
    _expect("the lodge has snares", _lodge.has_snares() and _lodge.upgrading == &"");
    _expect("and they show (%d decor)" % _lodge._decor.size(), _lodge._decor.size() >= 3);
    _lodge.stored.clear();
    var rate:float = _lodge.snare_rate();
    for d in 6:
        _lodge.on_day();
    _expect("rabbits fill the store by themselves (%.2f a day: %d meat, %d leather)" % [rate, _lodge.amount(&"meat"), _lodge.amount(&"leather")], rate > 0.0 and _lodge.amount(&"meat") >= 5 and _lodge.amount(&"leather") >= 1 and _lodge.amount(&"leather") < _lodge.amount(&"meat"));
    Weather.snow_depth = 1.0;
    _expect("snow buries the snares", _lodge.snare_rate() == 0.0);
    Weather.snow_depth = 0.0;
    var d:Dictionary = _lodge.to_dict();
    _lodge.snare_acc = 0.0;
    _lodge.pelt_acc = 0;
    d["snare_acc"] = 0.4;
    d["pelt_acc"] = 2;
    _lodge.restore_dict(d);
    _expect("the catch so far is saved", is_equal_approx(_lodge.snare_acc, 0.4) and _lodge.pelt_acc == 2);
    _lodge.stored.clear();
    # a live hunt: one hunter with no tool, the deer almost due
    _hunter = world.pawns[0];
    for p in world.pawns:
        p.clear_carry();
        p.end_task(false);
        p.tool = &"";
    _hunter.profession = JobManager.Profession.HUNTER;
    world.jobs.sync_targets();
    world.wildlife.refresh();
    world.wildlife.level.fill(0.0);
    for r in world.wildlife.level.size():
        world.wildlife.level[r] = world.wildlife.cap[r];
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON + 3) * GameClock.HOURS_PER_DAY + 8.0;
    GameClock.set_speed(3);
    Engine.time_scale = 6.0;
    _start = GameClock.total_hours;
    _phase = 1;

func _process(_delta:float) -> void:
    if _phase != 1:
        return;
    for p in world.pawns:
        p.hunger = 1.0; p.thirst = 1.0; p.warmth = 1.0; p.health = 1.0;
        if GameClock.total_hours - _start < 1.0:
            p.energy = 1.0;
    if not _set:                      # (setting the clock ran a few days of the lodge's own snares: start clean, without them)
        _set = true;
        _lodge.upgrades_done.erase(&"snares");
        _lodge.stored.clear();
        _lodge.dig_progress[&"deer"] = 0.98;
        _start = GameClock.total_hours;
        return;
    var meat:int = _lodge.amount(&"meat");
    if meat >= HuntingLodge.DEER_MEAT:
        _expect("the deer came home as meat and leather in the lodge (%d and %d, after %.1f hours)" % [meat, _lodge.amount(&"leather"), GameClock.total_hours - _start], _lodge.amount(&"leather") >= HuntingLodge.DEER_LEATHER);
        _expect("and counts as colony stock", Stock.amount(&"meat") >= meat);
        _expect("the hunter carries nothing", _hunter.carry_amount == 0 or _hunter.carry_item != &"meat");
        print("HUNTING LODGE %s" % ("PASS" if _fails == 0 else "FAIL"));
        _phase = 2;
        get_tree().quit(1 if _fails > 0 else 0);
    elif GameClock.total_hours - _start > 36.0:
        print("FAIL no deer came home in 36 hours (meat %d, progress %s)" % [meat, str(_lodge.dig_progress)]);
        _phase = 2;
        get_tree().quit(1);

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
    else:
        print("ok: " + what);
