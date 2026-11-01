# ----------------------------------------------------------------
# Crab pots
#     A Fishing Hut upgrade that costs mostly iron and fills pots with
#     crabs by itself (a new, rich, fast-spoiling food): a few a day by
#     the same water rules as the catch, nothing when the water freezes,
#     collected by a farmer like honey, saved with the hut, and drawn as
#     three pots on the pier.
#     godot --headless --path . --fixed-fps 60 res://tests/crab_pots.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;
var world:World;

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
    GameClock.hour_changed.disconnect(Weather._on_hour);
    var up:Dictionary = Defs.BUILDINGS[&"fishing_hut"]["upgrades"][&"crab_pots"];
    var iron:int = up["cost"][&"iron"];
    var total:int = 0;
    for k in up["cost"]:
        total += up["cost"][k];
    _expect("the upgrade costs mostly iron (%d of %d)" % [iron, total], float(iron) / total > 0.7);
    var crab:Dictionary = Defs.ITEMS[&"crabs"];
    _expect("crabs are a food, richer than fish and spoiling at least as fast", crab["food"] and crab["nutrition"] >= Defs.ITEMS[&"fish"]["nutrition"] and crab["spoil_days"] <= Defs.ITEMS[&"fish"]["spoil_days"]);
    _expect("and worth more than fish in trade, which merchants ask for", Defs.trade_value(&"crabs") > Defs.trade_value(&"fish") and Traders.WANTS.has(&"crabs"));
    var spot:Array = _shore();
    _expect("found a shore", not spot.is_empty());
    if spot.is_empty():
        _finish();
        return;
    var hut:FishingHut = world.place_building(&"fishing_hut", spot[0], spot[2], true, false, spot[3]) as FishingHut;
    _hut = hut;
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON + 3) * GameClock.HOURS_PER_DAY + 9.0;       # a summer morning
    Weather.reset();
    Weather._day_offset = 0.0;
    Weather._update_temperature();
    _expect("no crabs without the pots (%.2f a day)" % hut.crab_rate(), hut.crab_rate() == 0.0 and hut.collectable().is_empty());
    for d in 6:
        hut.on_day();
    _expect("and none stored", hut.ready_crabs == 0);
    # build the upgrade the normal way
    _expect("the upgrade can be started", hut.upgrade_block_reason(&"crab_pots") == "" and hut.start_upgrade(&"crab_pots"));
    for item in hut.cost():
        hut.receive(item, hut.cost()[item]);
    hut.add_work(hut.work_required());
    _expect("it is built and the hut has pots", hut.has_upgrade(&"crab_pots") and hut.has_pots() and hut.upgrading == &"");
    var decor_n:int = hut._decor.size();
    _expect("three pots appear on the pier (%d)" % decor_n, decor_n >= 3);
    # the passive harvest
    var rate:float = hut.crab_rate();
    print("crab rate %.2f a day at %.0f%% water" % [rate, hut.water_share() * 100.0]);
    _expect("a day brings crabs by the water rules (%.2f a day, below the %.1f of a full circle)" % [rate, FishingHut.CRAB_BASE], rate > 0.1 and rate <= FishingHut.CRAB_BASE);
    for d in 10:
        hut.on_day();
    var ready:int = hut.ready_crabs;
    _expect("crabs pile up by themselves (%d in 10 days)" % ready, ready >= int(rate * 10.0) - 1 and ready <= int(rate * 10.0) + 1);
    var quiet:Dictionary = hut.collectable();
    _expect("with enough ready, a farmer is called (%s)" % str(quiet), (ready >= FishingHut.CRAB_COLLECT_AT) == (not quiet.is_empty()) and (quiet.is_empty() or quiet["item"] == &"crabs"));
    for d in 80:
        hut.on_day();
    _expect("they stop at the cap (%d)" % hut.ready_crabs, hut.ready_crabs == FishingHut.CRAB_CAP);
    # a second hut sharing the water
    hut.ready_crabs = 10;
    var second:FishingHut = world.place_building(&"fishing_hut", spot[1], spot[2], true, false, spot[3]) as FishingHut;
    _expect("a hut sharing the water brings fewer (%.2f against %.2f)" % [hut.crab_rate(), rate], hut.crab_rate() < rate);
    world.remove_building(second, false);
    # frozen water
    var warm:float = hut.crab_rate();
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON * 3 + 3) * GameClock.HOURS_PER_DAY + 9.0;
    Weather.reset();
    Weather._day_offset = 0.0;
    Weather._update_temperature();
    var before:int = hut.ready_crabs;
    hut.on_day();
    _expect("nothing in a freezing winter (rate %.2f)" % hut.crab_rate(), hut.crab_rate() == 0.0 and hut.ready_crabs == before);
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON + 3) * GameClock.HOURS_PER_DAY + 9.0;
    Weather.reset();
    Weather._update_temperature();
    # a farmer collects them and carries them off
    var farmer:Pawn = world.pawns[0];
    farmer.clear_carry();
    farmer.end_task(false);
    farmer.profession = JobManager.Profession.FARMER;
    hut.ready_crabs = 12;
    var task:Task = world.jobs.herd.collect_task(farmer);
    _expect("a farmer is given the job of collecting crabs (%s)" % (task.label if task != null else "none"), task != null and task.label.to_lower().contains("crabs") and hut.claimed);
    var task2:Task = world.jobs.herd.collect_task(world.pawns[1]);
    _expect("and nobody else is sent for the same pots", task2 == null or not is_same(task2.target, hut));
    hut.claimed = false;
    var took:int = hut.take_ready(&"crabs", Pawn.CARRY_CAP);
    _expect("a load is taken (%d, %d left)" % [took, hut.ready_crabs], took == Pawn.CARRY_CAP and hut.ready_crabs == 12 - Pawn.CARRY_CAP);
    # saving
    hut.crab_acc = 0.37;
    var d:Dictionary = hut.to_dict();
    hut.crab_acc = 0.0;
    hut.ready_crabs = 0;
    hut.restore_dict(d);
    _expect("the pots and their crabs are saved (%.2f, %d)" % [hut.crab_acc, hut.ready_crabs], is_equal_approx(hut.crab_acc, 0.37) and hut.ready_crabs == 12 - Pawn.CARRY_CAP and hut.has_pots());
    var info:String = hut.info_text();
    _expect("the inspector says how many are ready", info.contains("Crabs ready"));
    _finish();

var _hut:FishingHut;

func _finish() -> void:
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0 and World.alive(_hut):          # windowed: a picture of the hut with its pots
        GameClock.set_speed(0);
        world.tools.select(_hut);
        world.camera_rig.focus_on(Vector3(_hut.position.x, 0.0, _hut.position.z));
        world.camera_rig._distance = 9.0;
        world.camera_rig._target_distance = 9.0;
        for i in 12:
            await get_tree().process_frame;
        get_viewport().get_texture().get_image().save_png(args[0].path_join("crab_pots.png"));
    print("CRAB POTS %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _shore() -> Array:
    for facing in 4:
        var size:Vector2i = Vector2i(3, 4) if facing % 2 == 0 else Vector2i(4, 3);
        for z in range(10, Terrain.SIZE - 14):
            for x in range(10, Terrain.SIZE - 14):
                var o:Vector2i = Vector2i(x, z);
                if Vector2(o - world.town_hall.origin).length() > 45.0 or world.can_place(&"fishing_hut", o, size, false, facing) != "":
                    continue;
                for dd in [Vector2i(5, 0), Vector2i(0, 5), Vector2i(-5, 0), Vector2i(0, -5)]:
                    if world.can_place(&"fishing_hut", o + dd, size, false, facing) == "" and not Rect2i(o, size).intersects(Rect2i(o + dd, size)):
                        return [o, o + dd, size, facing];
    return [];

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
