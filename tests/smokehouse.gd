# ----------------------------------------------------------------
# Smokehouse
#     An artisan smokes 4 fish or 4 meat and a firewood into 3 smoked
#     food (a quarter lost) that keeps for two months. It only runs
#     while the food stock is over its setting and under its cap, each
#     recipe has a switch, and the chimney smokes while it works.
#     godot --headless --path . --fixed-fps 60 res://tests/smokehouse.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;
var world:World;
var _house:Building;
var _cook:Pawn;
var _start:float = 0.0;
var _phase:int = 0;
var _smoked:bool = false;
var _fish0:int = 0;
var _wood0:int = 0;
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
    var def:Dictionary = Defs.BUILDINGS[&"smokehouse"];
    var fish:Dictionary = Defs.ITEMS[&"fish"];
    var meat:Dictionary = Defs.ITEMS[&"meat"];
    var smoked:Dictionary = Defs.ITEMS[&"smoked_food"];
    _expect("it is in the Industry menu", Defs.BUILD_MENU.has(&"smokehouse") and (Defs.BUILD_CATEGORIES[3][1] as Array).has(&"smokehouse"));
    _expect("smoked food is a food that keeps far longer than fish or meat (%.0f days)" % smoked["spoil_days"], Defs.is_food(&"smoked_food") and smoked["spoil_days"] >= fish["spoil_days"] * 10.0 and smoked["spoil_days"] > meat["spoil_days"] * 5.0);
    _expect("and trades better than either, which merchants ask for", Defs.trade_value(&"smoked_food") > Defs.trade_value(&"meat") and Traders.WANTS.has(&"smoked_food"));
    for id in [&"smoked_fish", &"smoked_meat"]:
        var r:Dictionary = def["recipes"][id];
        _expect("%s: a quarter is lost (4 in, %d out)" % [id, r["yield"]], r["yield"] == 3 and r["output"] == &"smoked_food" and r["inputs"].has(&"firewood"));
    _expect("the smokehouse stores smoked food only and has an artisan", def["accepts_items"] == [&"smoked_food"] and def["profession"] == "ARTISAN");
    for b in world.buildings.duplicate():
        if b.def_id == &"cart":
            world.remove_building(b, false);
    var o:Vector2i = TestSite.spot(world, Vector2i(3, 3), Vector2i(-8, 8));
    _house = world.place_building(&"smokehouse", o, Vector2i(3, 3), true);
    _expect("it was built, with a chimney that can smoke", _house != null and _house.is_complete() and _house._smoke != null);
    # the settings: reserve, cap, switches
    _stock_hall();
    _house.settings["keep_food"] = 0;
    _house.settings["cap_smoked_food"] = 60;
    _expect("it wants fish, meat and firewood (%s)" % str(_house.inputs_wanted()), _house.inputs_wanted().has(&"fish") and _house.inputs_wanted().has(&"meat") and _house.inputs_wanted().has(&"firewood"));
    _house.settings["keep_food"] = 500;
    _expect("not while the food stock is under its setting", _house.inputs_wanted().is_empty() and not _house.recipe_enabled(&"smoked_fish"));
    _house.settings["keep_food"] = 0;
    _house.settings["cap_smoked_food"] = 0;
    _expect("off at a cap of zero", not _house.recipe_enabled(&"smoked_meat"));
    _house.settings["cap_smoked_food"] = 60;
    _house.settings["make_smoked_meat"] = false;
    _expect("each recipe has a switch", not _house.recipe_enabled(&"smoked_meat") and _house.recipe_enabled(&"smoked_fish") and not _house.inputs_wanted().has(&"meat"));
    _house.settings["make_smoked_meat"] = true;
    # a live batch
    for p in world.pawns:
        p.clear_carry();
        p.end_task(false);
    _cook = world.pawns[0];
    _cook.profession = JobManager.Profession.ARTISAN;
    world.jobs.sync_targets();
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON + 3) * GameClock.HOURS_PER_DAY + 8.0;
    Weather.reset();
    Weather._day_offset = 0.0;
    Weather._update_temperature();
    GameClock.set_speed(3);
    Engine.time_scale = 6.0;
    _start = GameClock.total_hours;
    _phase = 1;

func _stock_hall() -> void:
    world.town_hall.stored.clear();
    world.town_hall.store(&"fish", 12);
    world.town_hall.store(&"meat", 8);
    world.town_hall.store(&"firewood", 20);

func _process(_delta:float) -> void:
    if _phase != 1:
        return;
    if not _set:                      # (the jump of the clock let the stock spoil: stock it again)
        _set = true;
        _stock_hall();
        _fish0 = Stock.amount(&"fish");
        _start = GameClock.total_hours;
        return;
    for p in world.pawns:
        p.hunger = 1.0; p.thirst = 1.0; p.warmth = 1.0; p.health = 1.0;
        if GameClock.total_hours - _start < 1.0:
            p.energy = 1.0;
    if _house._smoke != null and _house._smoke.emitting:
        _smoked = true;
    var got:int = _house.amount(&"smoked_food");
    if got >= 3:
        _expect("a batch came out smoked (%d smoked food after %.1f hours)" % [got, GameClock.total_hours - _start], got % 3 == 0);
        _expect("the chimney smoked while it worked", _smoked);
        var fish_used:int = _fish0 - Stock.amount(&"fish");
        _expect("and it counts as colony stock", Stock.amount(&"smoked_food") == got);
        _expect("the fresh food was fetched and used (%d fish and %d meat left in storage)" % [Stock.amount(&"fish"), Stock.amount(&"meat")], fish_used + (8 - Stock.amount(&"meat")) >= 4);
        _expect("the smoke clears after the batch", _house.busy_until == 0.0 or GameClock.total_hours >= _house.busy_until);
        print("SMOKEHOUSE %s" % ("PASS" if _fails == 0 else "FAIL"));
        _phase = 2;
        get_tree().quit(1 if _fails > 0 else 0);
    elif GameClock.total_hours - _start > 40.0:
        print("FAIL nothing was smoked in 40 hours (inputs %s, task %s)" % [str(_house.inputs), _cook.task.kind if _cook.task != null else "-"]);
        _phase = 2;
        get_tree().quit(1);

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
    else:
        print("ok: " + what);
