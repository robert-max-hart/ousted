# ----------------------------------------------------------------
# Trade orders (M6 step 2)
#     An order is checked against the merchant's stock and prices;
#     citizens haul the sold goods to the post, and only when they have
#     all arrived does the merchant take them and hand over the
#     purchases, which citizens carry to storage. An order the merchant
#     leaves unfinished lapses and the goods are carried back.
#     godot --headless --path . --fixed-fps 60 res://tests/trade.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;
var world:World;
var _post:TradingPost;
var _phase:int = 0;
var _start:float = 0.0;
var _wheat0:int = 0;
var _iron0:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    Weather.drought_enabled = false;
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    GameClock.total_hours = 10.0;
    var o:Vector2i = TestSite.near(world, Vector2i(8, -10));
    for rn in world.nodes.duplicate():
        if Rect2i(o - Vector2i(3, 3), Vector2i(16, 12)).has_point(rn.cell):
            world.remove_node(rn);
    _post = world.place_building(&"trading_post", o, Vector2i(4, 3), true) as TradingPost;
    _expect("the post is a TradingPost", _post != null);
    world.traders.last_visit_day = -99;
    world.traders.start_visit();
    var m:Merchant = world.traders.merchant;
    m.state = Merchant.State.TRADING;       # skip the walk
    m.path = [];
    world.traders.visit = {"stock": {&"iron": 6, &"coal": 4}, "wants": {&"wheat": 1.0, &"barley": 1.5}, "days_left": 4, "arrived": true};
    world.town_hall.store(&"wheat", 40);
    world.town_hall.store(&"barley", 10);
    # prices
    var t:Traders = world.traders;
    _expect("they sell at 1.25 times the value (iron %s)" % t.buy_price(&"iron"), is_equal_approx(t.buy_price(&"iron"), 7.5));
    _expect("they pay value times the multiplier for what they want (barley %s)" % t.sell_price(&"barley"), is_equal_approx(t.sell_price(&"barley"), 3.0));
    _expect("and half for the rest (stone %s)" % t.sell_price(&"stone"), is_equal_approx(t.sell_price(&"stone"), 1.5));
    # validation
    _expect("an empty order is refused", _post.place_order({}, {}) != "");
    _expect("asking for more than they have is refused", _post.place_order({&"wheat": 30}, {&"iron": 9}) != "");
    _expect("offering more than the colony can spare is refused", _post.place_order({&"wheat": 500}, {&"iron": 2}) != "");
    _expect("an unbalanced order is refused (offer 4 wheat worth 8, ask 2 iron costing 15)", _post.place_order({&"wheat": 4}, {&"iron": 2}) != "");
    _expect("none of those left an order", not _post.has_order());
    # a good one: 10 wheat at 2 = 20, for 2 iron at 7.5 = 15
    _wheat0 = Stock.amount(&"wheat");
    _iron0 = Stock.amount(&"iron");
    var err:String = _post.place_order({&"wheat": 10}, {&"iron": 2});
    _expect("a balanced order is accepted (%s)" % err, err == "" and _post.has_order());
    _expect("a second order waits for the first", _post.place_order({&"wheat": 10}, {&"iron": 2}) != "");
    _expect("nothing has moved yet", Stock.amount(&"wheat") == _wheat0 and _post.pickup.is_empty());
    _expect("the inspector shows the order", _post.info_text().contains("Order in progress"));
    # save the order and bring it back
    var d:Dictionary = _post.to_dict();
    _expect("the order is saved", d["order"]["sell"][&"wheat"] == 10);
    GameClock.set_speed(3);
    Engine.time_scale = 4.0;
    _start = GameClock.total_hours;
    _phase = 1;

func _process(_delta:float) -> void:
    for p in world.pawns:
        p.hunger = 1.0; p.thirst = 1.0; p.energy = 1.0; p.warmth = 1.0;
    var hours:float = GameClock.total_hours - _start;
    if _phase == 1 and not _post.has_order():
        _expect("the sold goods were hauled and the deal settled (%.1f hours)" % hours, true);
        _expect("the merchant's stock went down", world.traders.visit["stock"].get(&"iron", 0) == 4);
        _expect("the purchases wait at the post or are on their way", _post.pickup.get(&"iron", 0) > 0 or Stock.amount(&"iron") > _iron0);
        _phase = 2;
    elif _phase == 2 and _post.pickup.is_empty() and not _carrying():
        _expect("citizens carried the iron to storage (+%d)" % (Stock.amount(&"iron") - _iron0), Stock.amount(&"iron") == _iron0 + 2);
        _expect("and the wheat is gone from storage (-%d)" % (_wheat0 - Stock.amount(&"wheat")), Stock.amount(&"wheat") == _wheat0 - 10);
        _lapse();
    elif _phase == 4:
        if _post.pickup.is_empty() and _post.excess().is_empty() and not _carrying() and not _post.has_order():
            _expect("an order the merchant left unfinished lapsed and the goods came home (wheat %d, was %d)" % [Stock.amount(&"wheat"), _wheat0 - 10], Stock.amount(&"wheat") == _wheat0 - 10);
            _expect("with no purchase made", Stock.amount(&"coal") == _coal0);
            print("TRADE %s" % ("PASS" if _fails == 0 else "FAIL"));
            get_tree().quit(1 if _fails > 0 else 0);
    if hours > 80.0:
        print("FAIL timed out in phase %d" % _phase);
        print("TRADE FAIL");
        get_tree().quit(1);

var _coal0:int = 0;

# A second order whose goods are only partly delivered when the merchant goes.
func _lapse() -> void:
    _coal0 = Stock.amount(&"coal");
    world.traders.visit["stock"] = {&"iron": 4, &"coal": 4};
    var err:String = _post.place_order({&"wheat": 13}, {&"coal": 4});        # 13 wheat is worth 26, 4 coal cost 25
    _expect("a second order is accepted (%s)" % err, err == "");
    _post.deliver(&"wheat", 5);        # five of the twelve are here
    world.town_hall.take(&"wheat", 5);
    _expect("it is not complete", _post.has_order() and not _post.order_complete());
    world.traders.depart();
    _expect("when the merchant leaves the order lapses", not _post.has_order());
    _expect("and what was brought stays at the post, over its level (%s)" % [_post.inputs], _post.held(&"wheat") == 5 and _post.excess().get(&"wheat", 0) == 5);
    _phase = 4;

func _carrying() -> bool:
    for p in world.pawns:
        if p.carry_amount > 0:
            return true;
    return false;

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
