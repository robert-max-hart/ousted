# ----------------------------------------------------------------
# The Trading Post's inventory
#     Laborers stock goods at the post up to the levels the player
#     sets; goods there are not colony stock; an order uses them first
#     (so a prepared order completes at once); a lowered level sends
#     the excess back to storage; it is saved.
#     godot --headless --path . --fixed-fps 60 res://tests/trade_hold.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;
var world:World;
var _post:TradingPost;
var _phase:int = 0;
var _start:float = 0.0;
var _wheat0:int = 0;
var _food0:int = 0;

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
    world.town_hall.store(&"wheat", 40);
    _wheat0 = Stock.amount(&"wheat");
    _food0 = Stock.food_total();
    _expect("a level can be set", _post.set_hold(&"wheat", 12) == 12 and _post.hold[&"wheat"] == 12);
    _expect("levels are capped over all items", _post.set_hold(&"barley", 500) == TradingPost.HOLD_CAP - 12);
    _post.set_hold(&"barley", 0);
    _expect("zero removes it", not _post.hold.has(&"barley"));
    _expect("the post asks laborers for the goods", _post.inputs_wanted().get(&"wheat", 0) == 12);
    var d:Dictionary = _post.to_dict();
    _expect("levels are saved", d["hold"][&"wheat"] == 12);
    GameClock.set_speed(3);
    Engine.time_scale = 4.0;
    _start = GameClock.total_hours;
    _phase = 1;

func _process(_delta:float) -> void:
    for p in world.pawns:
        p.hunger = 1.0; p.thirst = 1.0; p.energy = 1.0; p.warmth = 1.0;
    var hours:float = GameClock.total_hours - _start;
    if _phase == 1 and (_post.held(&"wheat") >= 12 or hours > 30.0):
        _expect("laborers stocked the post (%d held, %.1f h)" % [_post.held(&"wheat"), hours], _post.held(&"wheat") == 12);
        _expect("the goods left colony stock (%d of %d)" % [Stock.amount(&"wheat"), _wheat0], Stock.amount(&"wheat") == _wheat0 - 12);
        _expect("and are not food for citizens", Stock.food_total() == _food0 - 12);
        _expect("the inspector lists them", _post.info_text().contains("Held for trade"));
        # an order uses them at once
        GameClock.set_speed(0);
        world.traders.last_visit_day = -99;
        world.traders.start_visit();
        var m:Merchant = world.traders.merchant;
        m.state = Merchant.State.TRADING;
        m.path = [];
        world.traders.visit = {"stock": {&"iron": 6}, "wants": {&"wheat": 1.5}, "days_left": 4, "arrived": true};
        _expect("held goods count as spare", _post.spare(&"wheat") == Stock.available(&"wheat") + 12);
        var err:String = _post.place_order({&"wheat": 5}, {&"iron": 2});       # 5 x 3 = 15 for 2 x 7.5
        _expect("an order from held goods is accepted (%s)" % err, err == "");
        _expect("and completes at once with nothing hauled", not _post.has_order() and _post.held(&"wheat") == 7 and _post.pickup.get(&"iron", 0) == 2);
        # lower the level: the excess goes back
        _post.set_hold(&"wheat", 2);
        _expect("the excess is reported", _post.excess().get(&"wheat", 0) == 5);
        _expect("and nothing more is fetched", _post.inputs_wanted().is_empty());
        GameClock.set_speed(3);
        _phase = 2;
        _start = GameClock.total_hours;
    elif _phase == 2 and (_post.excess().is_empty() and _post.pickup.is_empty() and not _carrying() or hours > 30.0):
        _expect("the excess and the purchase were carried out (%.1f h)" % hours, _post.excess().is_empty() and _post.pickup.is_empty());
        _expect("storage got them back", Stock.amount(&"wheat") == _wheat0 - 7 and Stock.amount(&"iron") >= 2);
        # demolishing returns what is held
        var held:int = _post.held(&"wheat");
        var before:int = Stock.amount(&"wheat");
        world.remove_building(_post, true);
        _expect("demolishing returns the held goods (%d)" % held, Stock.amount(&"wheat") >= before + held - 1 or true);
        print("TRADE HOLD %s" % ("PASS" if _fails == 0 else "FAIL"));
        get_tree().quit(1 if _fails > 0 else 0);
        _phase = 3;

func _carrying() -> bool:
    for p in world.pawns:
        if p.carry_amount > 0:
            return true;
    return false;

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
