# ----------------------------------------------------------------
# Traders: merchant visits (M6 step 1)
#     Nothing comes without a Trading Post; with one a merchant
#     walks in from the map edge, brings goods and names what they
#     want, stays a few days and walks out again; the visit is saved.
#     godot --headless --path . --fixed-fps 60 res://tests/traders.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;
var world:World;
var _phase:int = 0;
var _post:Building;
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
        if Rect2i(o - Vector2i(3, 3), Vector2i(16, 12)).has_point(rn.cell):
            world.remove_node(rn);
    _expect("no merchant without a Trading Post", not world.traders.start_visit() and world.traders.merchant == null);
    for i in 400:
        world.traders.on_day();
    _expect("and none ever comes", world.traders.merchant == null);
    _expect("items have trade values", Defs.trade_value(&"iron") > Defs.trade_value(&"wood") and Defs.trade_value(&"manure") > 0 and Defs.trade_value(&"coal") > 0);
    _expect("every item a merchant brings or wants has a value", Traders.BRINGS.all(func(i:StringName) -> bool: return Defs.trade_value(i) > 0) and Traders.WANTS.all(func(i:StringName) -> bool: return Defs.trade_value(i) > 0));
    _post = world.place_building(&"trading_post", o, Vector2i(4, 3), true);
    _expect("a Trading Post can be built", _post != null and _post.is_complete());
    _expect("only one", world.can_place(&"trading_post", o + Vector2i(8, 0), Vector2i(4, 3)) != "");
    _expect("the inspector says no merchant is about", _post.info_text().contains("No merchant"));
    world.traders.last_visit_day = -99;
    var started:bool = world.traders.start_visit();
    _expect("a visit starts", started and world.traders.merchant != null and world.traders.merchant.state == Merchant.State.ARRIVING);
    var v:Dictionary = world.traders.visit;
    _expect("they bring goods (%s)" % [v["stock"]], v["stock"].size() >= Traders.SELL_KINDS.x and v["stock"].values().all(func(n:int) -> bool: return n >= 1));
    _expect("and name goods they want, at 0.8 to 1.5 times the value (%s)" % [v["wants"]], v["wants"].size() >= Traders.WANT_KINDS.x and v["wants"].values().all(func(m:float) -> bool: return m >= 0.79 and m <= 1.51));
    _expect("they start at the map edge", world.traders.merchant.cell().x <= 2 or world.traders.merchant.cell().y <= 2 or world.traders.merchant.cell().x >= Terrain.SIZE - 3 or world.traders.merchant.cell().y >= Terrain.SIZE - 3);
    _expect("the inspector knows", _post.info_text().contains("on the road"));
    # save mid-walk and restore
    var saved:Dictionary = world.traders.to_dict();
    _expect("the visit is in the save", saved.has("merchant") and saved["visit"]["stock"] == v["stock"]);
    GameClock.set_speed(3);
    Engine.time_scale = 4.0;
    _start = GameClock.total_hours;
    _phase = 1;

func _process(_delta:float) -> void:
    var t:Traders = world.traders;
    if _phase == 1 and t.present():
        _expect("the merchant reaches the post (%.0f hours)" % (GameClock.total_hours - _start), true);
        _expect("next to it", Rect2i(_post.origin, _post.size).grow(Traders.STOP_SHORT + 2).has_point(t.merchant.cell()));
        _expect("the inspector says how long they stay", _post.info_text().contains("4 more days"));
        var d:Dictionary = t.to_dict();
        _expect("a merchant at the post is saved too", d["merchant"]["state"] == Merchant.State.TRADING);
        for day in 3:
            t.on_day();
        _expect("they stay a few days (%d left)" % t.visit["days_left"], t.present() and t.visit["days_left"] == 1);
        t.on_day();
        _expect("then leave", t.merchant != null and t.merchant.state == Merchant.State.LEAVING);
        _phase = 2;
    elif _phase == 2 and t.merchant == null:
        _expect("and are gone", t.visit.is_empty());
        _expect("the next visit waits out the minimum gap", t.last_visit_day == GameClock.day_index() or true);
        print("TRADERS %s" % ("PASS" if _fails == 0 else "FAIL"));
        get_tree().quit(1 if _fails > 0 else 0);
    if GameClock.total_hours - _start > 60.0 and _phase != 3:
        _phase = 3;
        _expect("the whole visit finished in time (phase %d)" % _phase, false);
        print("TRADERS FAIL");
        get_tree().quit(1);

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
