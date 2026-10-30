# ----------------------------------------------------------------
# Trade window (M6 step 2)
#     The Trading Post inspector offers the window only while a
#     merchant is there; quantities are capped by stock; the balance
#     gates Place order; placing an order locks the window.
#     godot --headless --path . --fixed-fps 60 res://tests/trade_ui.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    Weather.drought_enabled = false;
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    var o:Vector2i = TestSite.near(world, Vector2i(8, -10));
    for rn in world.nodes.duplicate():
        if Rect2i(o - Vector2i(3, 3), Vector2i(16, 12)).has_point(rn.cell):
            world.remove_node(rn);
    var post:TradingPost = world.place_building(&"trading_post", o, Vector2i(4, 3), true) as TradingPost;
    world.tools.select(post);
    world.hud._refresh_info();
    _expect("the button is there but off with no merchant", world.hud._trade_btn.visible and world.hud._trade_btn.disabled and world.hud._trade_btn.text == "No merchant here");
    world.traders.last_visit_day = -99;
    world.traders.start_visit();
    world.traders.merchant.state = Merchant.State.TRADING;
    world.traders.merchant.path = [];
    world.traders.visit = {"stock": {&"iron": 3}, "wants": {&"wheat": 1.0}, "days_left": 3, "arrived": true};
    world.town_hall.store(&"wheat", 30);
    world.hud._refresh_info();
    _expect("with a merchant it opens", not world.hud._trade_btn.disabled and world.hud._trade_btn.text.begins_with("Trade"));
    var panel:TradePanel = world.hud._trade_panel;
    world.hud._trade_btn.pressed.emit();
    _expect("the window is open", panel.visible);
    _expect("it lists the merchant's iron and our wheat", panel._buy_list.get_child_count() == 1 and panel._sell_list.get_child_count() >= 1);
    panel._change(&"iron", true, 1);
    panel._change(&"iron", true, 1);
    panel._change(&"iron", true, 5);
    _expect("you cannot ask for more than they have", panel._buy_qty[&"iron"] == 3);
    _expect("with nothing offered Place order is off (%s)" % panel._balance.text, panel._place.disabled);
    panel._change(&"wheat", false, 5);
    _expect("5 wheat (10) does not cover 3 iron (22.5)", panel._place.disabled and panel._balance.text.contains("Offer more"));
    panel._change(&"wheat", false, 100);
    _expect("you cannot offer more than you have spare (%d)" % panel._sell_qty[&"wheat"], panel._sell_qty[&"wheat"] <= Stock.available(&"wheat"));
    panel._change(&"wheat", false, -(panel._sell_qty[&"wheat"] - 12));
    _expect("12 wheat (24) covers it and Place order lights up (%s)" % panel._balance.text, not panel._place.disabled);
    panel._on_place();
    _expect("placing the order opens one at the post", post.has_order() and post.order["buy"][&"iron"] == 3 and post.order["sell"][&"wheat"] == 12);
    _expect("the window locks and shows progress (%s)" % panel._balance.text, panel._place.disabled and panel._balance.text.contains("Order open"));
    panel._change(&"wheat", false, 1);
    _expect("and the button text says so", panel._place.text == "Order in progress");
    world.traders.depart();
    world.hud._refresh_info();
    _expect("when the merchant leaves the window closes", not panel.visible);
    print("TRADE UI %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
