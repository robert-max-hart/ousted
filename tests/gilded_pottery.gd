# ----------------------------------------------------------------
# Gilded pottery
#     The Potter's Workshop's Gilding upgrade unlocks gilded pottery
#     made with gold (1 gold + 6 stone -> 3 pieces) or silver (2 silver
#     + 4 stone -> 2 pieces): worth several times plain pottery, asked
#     for by fine-goods merchants, made before plain pottery, switched
#     and capped separately. Without the upgrade nothing changes.
#     godot --headless --path . --fixed-fps 60 res://tests/gilded_pottery.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;
var world:World;
var _shop:Building;
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
    var o:Vector2i = TestSite.spot(world, Vector2i(3, 3), Vector2i(5, -7));
    for rn in world.nodes.duplicate():
        if Rect2i(o - Vector2i(3, 3), Vector2i(16, 12)).has_point(rn.cell):
            world.remove_node(rn);
    world.terrain.flatten_rect(Rect2i(o - Vector2i(2, 2), Vector2i(18, 14)));
    _shop = world.place_building(&"pottery", o, Vector2i(3, 3), true);
    var def:Dictionary = Defs.BUILDINGS[&"pottery"];
    var gold:Dictionary = def["recipes"][&"gilded_gold"];
    var silver:Dictionary = def["recipes"][&"gilded_silver"];
    var plain_value:int = Defs.trade_value(&"pottery");
    var gilded_value:int = Defs.trade_value(&"gilded_pottery");
    _expect("gilded pottery is worth several times plain (%d against %d)" % [gilded_value, plain_value], gilded_value >= plain_value * 3 and not Defs.is_food(&"gilded_pottery"));
    _expect("it is a luxury the fine-goods caravan asks for", Traders.LUXURIES.has(&"gilded_pottery") and Traders.WANTS.has(&"gilded_pottery") and (Traders.TYPES[&"luxury"]["wants"] as Array).has(&"gilded_pottery"));
    _expect("each recipe is worth making: pieces are worth more than the gold or silver and stone used", gold["yield"] * gilded_value > Defs.trade_value(&"gold") + 6 * Defs.trade_value(&"stone") and silver["yield"] * gilded_value > 2 * Defs.trade_value(&"silver") + 4 * Defs.trade_value(&"stone"));
    _expect("the upgrade is cheap in precious metal and costs iron", def["upgrades"][&"gilding"]["cost"].has(&"iron") and not def["upgrades"][&"gilding"]["cost"].has(&"gold"));
    _expect("a Potter's Workshop holds gilded pottery too", (def["accepts_items"] as Array).has(&"gilded_pottery"));
    # without the upgrade
    _shop.settings["cap_gilded_pottery"] = 10;
    world.town_hall.store(&"gold", 3);
    world.town_hall.store(&"silver", 4);
    world.town_hall.store(&"stone", 20);
    _expect("no gilding without the upgrade", not _shop.recipe_enabled(&"gilded_gold") and not _shop.recipe_enabled(&"gilded_silver") and not _shop.inputs_wanted().has(&"gold") and not _shop.inputs_wanted().has(&"silver"));
    _expect("plain pottery still runs", _shop.recipe_enabled(&"pottery"));
    _expect("the upgrade can be started", _shop.upgrade_block_reason(&"gilding") == "" and _shop.start_upgrade(&"gilding"));
    for item in _shop.cost():
        _shop.receive(item, _shop.cost()[item]);
    _shop.add_work(_shop.work_required());
    _expect("the workshop has the gilding", _shop.has_upgrade(&"gilding") and _shop.upgrading == &"");
    _expect("the recipes are on, and want gold, silver and stone (%s)" % str(_shop.inputs_wanted()), _shop.recipe_enabled(&"gilded_gold") and _shop.recipe_enabled(&"gilded_silver") and _shop.inputs_wanted().has(&"gold") and _shop.inputs_wanted().has(&"silver"));
    _shop.settings["make_gilded_silver"] = false;
    _expect("each metal has a switch", _shop.recipe_enabled(&"gilded_gold") and not _shop.recipe_enabled(&"gilded_silver") and not _shop.inputs_wanted().has(&"silver"));
    _shop.settings["make_gilded_silver"] = true;
    _shop.settings["cap_gilded_pottery"] = 0;
    _expect("off at a cap of zero", not _shop.recipe_enabled(&"gilded_gold"));
    _shop.settings["cap_gilded_pottery"] = 10;
    var order:Array = def["recipes"].keys();
    _expect("gilded pieces come before plain ones", order.find(&"gilded_gold") < order.find(&"pottery") and order.find(&"gilded_silver") < order.find(&"pottery"));
    # a live batch
    for p in world.pawns:
        p.clear_carry();
        p.end_task(false);
    var artisan:Pawn = world.pawns[0];
    artisan.profession = JobManager.Profession.ARTISAN;
    world.jobs.sync_targets();
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON + 3) * GameClock.HOURS_PER_DAY + 8.0;
    GameClock.set_speed(3);
    Engine.time_scale = 4.0;
    _phase = 1;

func _process(_delta:float) -> void:
    if _phase != 1:
        return;
    if not _set:                      # (the jump of the clock let the stock spoil and wear: stock it again)
        _set = true;
        world.town_hall.stored.erase(&"gold");
        world.town_hall.stored.erase(&"silver");
        world.town_hall.stored.erase(&"stone");
        world.town_hall.store(&"gold", 3);
        world.town_hall.store(&"silver", 4);
        world.town_hall.store(&"stone", 20);
        _start = GameClock.total_hours;
        return;
    for p in world.pawns:
        p.hunger = 1.0; p.thirst = 1.0; p.energy = 1.0; p.warmth = 1.0; p.health = 1.0;
    var hours:float = GameClock.total_hours - _start;
    var got:int = Stock.amount(&"gilded_pottery");
    if got >= 3 or hours > 70.0:
        _expect("gilded pottery was made (%d, %.1f h) and counts as colony stock" % [got, hours], got >= 3);
        _expect("it was gilded before any plain pottery (%d plain)" % Stock.amount(&"pottery"), Stock.amount(&"pottery") == 0 or got >= 3);
        print("GILDED POTTERY %s" % ("PASS" if _fails == 0 else "FAIL"));
        _phase = 2;
        get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
    else:
        print("ok: " + what);
