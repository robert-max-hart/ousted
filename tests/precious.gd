# ----------------------------------------------------------------
# Silver and gold
#     The Mine's Deep Veins upgrade (after Deep Shafts) unlocks silver
#     and gold: slow to dig, capped like the other ores, trade goods.
#     godot --headless --path . --fixed-fps 60 res://tests/precious.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;
var world:World;
var _mine:Building;
var _phase:int = 0;
var _start:float = 0.0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    Weather.drought_enabled = false;
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    var o:Vector2i = world.town_hall.origin + Vector2i(8, -10);
    for rn in world.nodes.duplicate():
        if Rect2i(o - Vector2i(3, 3), Vector2i(16, 14)).has_point(rn.cell):
            world.remove_node(rn);
    world.terrain.flatten_rect(Rect2i(o - Vector2i(2, 2), Vector2i(18, 16)));
    _mine = world.place_building(&"mine", o, Vector2i(5, 5), true);
    _expect("silver and gold are trade goods worth far more than iron", Defs.trade_value(&"gold") > Defs.trade_value(&"silver") and Defs.trade_value(&"silver") > Defs.trade_value(&"iron") * 3 and not Defs.is_food(&"gold"));
    _expect("merchants bring and ask for them", Traders.BRINGS.has(&"gold") and Traders.BRINGS.has(&"silver") and Traders.WANTS.has(&"gold") and Traders.WANTS.has(&"silver"));
    _expect("both are locked at first", not _mine.item_unlocked(&"silver") and not _mine.item_unlocked(&"gold"));
    var ups:Dictionary = _mine.def["upgrades"];
    _expect("Deep Veins needs Deep Shafts", ups[&"deep_veins"]["requires"] == [&"deep_shafts"]);
    _expect("it cannot be built before the shafts", _mine.upgrade_block_reason(&"deep_veins") != "");
    _mine.upgrades_done[&"deep_shafts"] = true;
    _expect("it can after them", _mine.upgrade_block_reason(&"deep_veins") == "");
    _mine.upgrades_done[&"deep_veins"] = true;
    _expect("the upgrade unlocks silver and gold", _mine.item_unlocked(&"silver") and _mine.item_unlocked(&"gold"));
    _expect("gold takes longest to dig (%s h)" % _mine.def["mine_hours"][&"gold"], _mine.def["mine_hours"][&"gold"] > _mine.def["mine_hours"][&"silver"] and _mine.def["mine_hours"][&"silver"] > _mine.def["mine_hours"][&"coal"]);
    _expect("caps start at silver %d and gold %d" % [_mine.settings["cap_silver"], _mine.settings["cap_gold"]], _mine.settings["cap_silver"] == 10 and _mine.settings["cap_gold"] == 6);
    # the miners dig everything else first, then precious metals up to their caps
    _mine.settings["cap_iron"] = 1;
    _mine.settings["cap_coal"] = 1;
    _mine.settings["cap_silver"] = 2;
    _mine.settings["cap_gold"] = 1;
    world.town_hall.store(&"iron", 1);
    world.town_hall.store(&"coal", 1);
    world.town_hall.store(&"tool_iron", 4);
    var miner:Pawn = world.pawns[0];
    miner.profession = JobManager.Profession.MINER;
    world.jobs.change_profession(JobManager.Profession.MINER, 1);
    miner.equip(&"tool_iron");
    GameClock.set_speed(3);
    Engine.time_scale = 6.0;
    _start = GameClock.total_hours;
    _phase = 1;

func _process(_delta:float) -> void:
    if _phase != 1:
        return;
    for p in world.pawns:
        p.hunger = 1.0; p.thirst = 1.0; p.energy = 1.0; p.warmth = 1.0;
    var hours:float = GameClock.total_hours - _start;
    if (Stock.amount(&"silver") >= 2 and Stock.amount(&"gold") >= 1) or hours > 100.0:
        _expect("silver was dug up to its cap (%d, %.0f h)" % [Stock.amount(&"silver"), hours], Stock.amount(&"silver") >= 2);
        _expect("and gold (%d)" % Stock.amount(&"gold"), Stock.amount(&"gold") >= 1);
        print("PRECIOUS %s" % ("PASS" if _fails == 0 else "FAIL"));
        get_tree().quit(1 if _fails > 0 else 0);
        _phase = 2;

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
