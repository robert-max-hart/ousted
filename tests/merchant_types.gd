# ----------------------------------------------------------------
# Merchant types, seasonal prices and the trade record
#     Four kinds of merchant with their own goods, asks, price ranges
#     and cart colours; nobody buys what they sell; luxuries get the best
#     multipliers; prices (not availability or visit rates) follow the
#     season, fixed for a visit; every deal and visit goes in the ledger.
#     godot --headless --path . --fixed-fps 60 res://tests/merchant_types.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;
var world:World;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    Weather.drought_enabled = false;
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    world.seeds.unlock_all();
    world.seeds.known.erase(&"pumpkin");
    var t:Traders = world.traders;
    # the types
    _expect("there are four kinds of merchant", Traders.TYPES.size() == 4);
    var every_item:bool = true;
    for id in Traders.TYPES:
        for item in Traders.TYPES[id]["brings"] + Traders.TYPES[id]["wants"]:
            every_item = every_item and Defs.trade_value(item) > 0 and (Traders.BRINGS.has(item) or Traders.WANTS.has(item));
    _expect("every good they deal in has a value", every_item);
    # many visits
    var counts:Dictionary = {};
    var clash:bool = false;
    var lux_ok:bool = true;
    var inside:bool = true;
    var luxury_seen:int = 0;
    var herders_with_animals:int = 0;
    var herders:int = 0;
    var metal_with_animals:int = 0;
    world.add_child(Node.new());
    var pen:Pasture = world.place_building(&"pasture", world.town_hall.origin + Vector2i(5, -8), Vector2i(5, 5), true) as Pasture;
    pen.set_kind(&"cow");
    for i in 400:
        var v:Dictionary = t._make_visit();
        var type:Dictionary = Traders.TYPES[v["type"]];
        counts[v["type"]] = counts.get(v["type"], 0) + 1;
        var off:int = 0;
        for item in v["stock"]:
            if Defs.is_seed_key(item) or Defs.is_animal_key(item):
                continue;
            if not (type["brings"] as Array).has(item):
                off += 1;       # the one small off-type item every merchant brings
            clash = clash or v["wants"].has(item);
        inside = inside and off == 1;
        for item in v["wants"]:
            inside = inside and (type["wants"] as Array).has(item);
            if Traders.LUXURIES.has(item):
                luxury_seen += 1;
                lux_ok = lux_ok and v["wants"][item] >= Traders.LUXURY_MULT.x - 0.06;
            else:
                lux_ok = lux_ok and v["wants"][item] <= type["mult"].y + 0.03;
        var has_animal:bool = false;
        for key in v["stock"]:
            has_animal = has_animal or Defs.is_animal_key(key);
        if v["type"] == &"herder":
            herders += 1;
            herders_with_animals += 1 if has_animal else 0;
        if v["type"] == &"metal" and has_animal:
            metal_with_animals += 1;
    _expect("all kinds turn up (%s)" % [counts], counts.size() == 4);
    _expect("grain merchants are commonest, fine goods rarest (%s)" % [counts], counts[&"grain"] > counts[&"luxury"]);
    _expect("each deals in its own goods and one small other thing", inside);
    _expect("nobody asks for what they sell", not clash);
    _expect("luxuries are asked for at %s or more, other goods within the type's range (%d luxuries seen)" % [Traders.LUXURY_MULT, luxury_seen], lux_ok and luxury_seen > 0);
    _expect("herders offer animals often, metal traders never (%d of %d, %d)" % [herders_with_animals, herders, metal_with_animals], herders_with_animals > herders / 3 and metal_with_animals == 0);
    # seasons: price only
    t.visit = {"stock": {&"wheat": 5}, "wants": {&"firewood": 1.0}, "season": 0};
    var spring:float = t.buy_price(&"wheat");
    t.visit["season"] = 2;
    var autumn:float = t.buy_price(&"wheat");
    _expect("grain is dearer in spring than at harvest (%s against %s)" % [spring, autumn], spring > autumn * 1.4);
    t.visit["season"] = 0;
    var fire_summer:float = 0.0;
    t.visit["season"] = 1;
    fire_summer = t.sell_price(&"firewood");
    t.visit["season"] = 3;
    _expect("firewood fetches more in winter than summer (%s against %s)" % [t.sell_price(&"firewood"), fire_summer], t.sell_price(&"firewood") > fire_summer * 1.9);
    _expect("iron and gold cost the same all year", is_equal_approx(t.buy_price(&"iron"), Defs.trade_value(&"iron") * Traders.OWN_MARGIN) and t.season_factor(&"gold") == 1.0);
    _expect("goods not asked for are still half price, in season", is_equal_approx(t.sell_price(&"wheat"), Defs.trade_value(&"wheat") * 0.5 * Traders.SEASON_PRICE[&"wheat"][3]));
    t.visit = {};
    _expect("with no visit there is no seasonal effect", t.season_factor(&"wheat") == 1.0);
    var new_visit:Dictionary = t._make_visit();
    _expect("a visit remembers its season, and visits come as often in every season", new_visit["season"] == GameClock.season() and Traders.VISITS_PER_SEASON == 3.0);
    for item in Traders.SEASON_PRICE:
        _expect("%s has four seasons of prices" % item, Traders.SEASON_PRICE[item].size() == 4);
    # the ledger
    var led:Ledger = world.ledger;
    var deals0:int = led.deal_count;
    t.visit = {"stock": {&"iron": 4}, "wants": {&"wheat": 1.5}, "days_left": 3, "arrived": true, "type": &"metal", "season": -1, "deals": 0};
    led.record_deal("metal trader", {&"wheat": 10}, {&"iron": 2}, 30.0, 15.0);
    led.record_visit("metal trader", 1);
    _expect("deals and visits are recorded", led.deal_count == deals0 + 1 and led.visit_count >= 1 and led.trades.size() >= 2);
    _expect("with running totals", is_equal_approx(led.trade_in_total, 30.0) and is_equal_approx(led.trade_out_total, 15.0));
    led.on_day(world);
    var last:Dictionary = led.samples[led.samples.size() - 1];
    _expect("the day's sample has the trade values and they restart", is_equal_approx(last["trade_in"], 30.0) and is_equal_approx(last["trade_out"], 15.0) and led.trade_in_today == 0.0);
    var saved:Dictionary = led.to_dict();
    var other:Ledger = Ledger.new();
    other.restore(saved);
    _expect("the record is saved", other.trades.size() == led.trades.size() and other.deal_count == led.deal_count and is_equal_approx(other.trade_in_total, 30.0));
    var old:Ledger = Ledger.new();
    old.restore({"samples": [], "events": []});
    _expect("an old save has an empty record", old.trades.is_empty() and old.deal_count == 0);
    # a real trade through the post
    var o:Vector2i = world.town_hall.origin + Vector2i(8, -10);
    for rn in world.nodes.duplicate():
        if Rect2i(o - Vector2i(3, 3), Vector2i(16, 12)).has_point(rn.cell):
            world.remove_node(rn);
    var post:TradingPost = world.place_building(&"trading_post", o + Vector2i(0, 8), Vector2i(4, 3), true) as TradingPost;
    t.last_visit_day = -99;
    t.start_visit();
    t.merchant.state = Merchant.State.TRADING;
    t.merchant.path = [];
    t.visit = {"stock": {&"iron": 6}, "wants": {&"wheat": 1.5}, "days_left": 3, "arrived": true, "type": &"metal", "season": -1, "deals": 0};
    world.town_hall.store(&"wheat", 20);
    post.set_hold(&"wheat", 10);
    post.add_input(&"wheat", 10);
    var before:int = led.deal_count;
    var err:String = post.place_order({&"wheat": 6}, {&"iron": 2});
    _expect("a deal from held goods is accepted (%s)" % err, err == "");
    _expect("and the ledger has it with its values", led.deal_count == before + 1 and is_equal_approx(led.trades[led.trades.size() - 1]["in"], 6 * 3.0) and is_equal_approx(led.trades[led.trades.size() - 1]["out"], 2 * 7.5) and led.trades[led.trades.size() - 1]["merchant"] == "metal trader");
    _expect("and the visit counts its deal", t.visit["deals"] == 1);
    t.depart();
    _expect("a visit that ends is recorded", led.trades[led.trades.size() - 1]["kind"] == "visit" and led.trades[led.trades.size() - 1]["deals"] == 1);
    print("MERCHANT TYPES %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
