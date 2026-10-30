# ----------------------------------------------------------------
# Trade window screenshots (M6 step 2): the window with a deal being
# set up, then with the order open and goods on their way.
#     godot --path . res://tests/trade_shot.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

var world:World;
var _out:String = "user://";
var _frame:int = 0;
var _post:TradingPost;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Weather.drought_enabled = false;
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0:
        _out = args[0];
    Defs.difficulty = &"easy";
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    var o:Vector2i = TestSite.near(world, Vector2i(8, -10));
    for rn in world.nodes.duplicate():
        if Rect2i(o - Vector2i(3, 3), Vector2i(16, 12)).has_point(rn.cell):
            world.remove_node(rn);
    _post = world.place_building(&"trading_post", o, Vector2i(4, 3), true) as TradingPost;
    world.traders.last_visit_day = -99;
    world.traders.start_visit();
    world.traders.merchant.state = Merchant.State.TRADING;
    world.traders.merchant.path = [];
    world.traders.visit = {"stock": {&"iron": 6, &"coal": 4, &"tool_iron": 2, &"apples": 20}, "wants": {&"wheat": 1.2, &"barley": 1.5, &"firewood": 0.9, &"eggs": 1.1}, "days_left": 3, "arrived": true, "type": &"grain", "season": 0, "deals": 0};
    world.town_hall.store(&"barley", 15);
    world.town_hall.store(&"eggs", 8);
    world.camera_rig.focus_on(Vector3(o.x + 2, 0, o.y + 2));
    world.camera_rig._distance = 18.0;
    world.camera_rig._target_distance = 18.0;
    world.tools.select(_post);

func _process(_delta:float) -> void:
    _frame += 1;
    match _frame:
        10:
            world.hud._trade_btn.pressed.emit();
            var p:TradePanel = world.hud._trade_panel;
            p._change(&"iron", true, 3);
            p._change(&"apples", true, 4);
            p._change(&"wheat", false, 20);
            p._change(&"barley", false, 6);
            p._change(&"eggs", false, 4);
        40:
            get_viewport().get_texture().get_image().save_png(_out.path_join("trade_a.png"));
            world.hud._trade_panel._on_place();
            GameClock.set_speed(2);
            world.hud._trade_panel.visible = false;
            _post.set_hold(&"barley", 10);
            _post.set_hold(&"eggs", 4);
            world.hud._hold_btn.pressed.emit();
        200:
            get_viewport().get_texture().get_image().save_png(_out.path_join("trade_b.png"));
            world.hud._hold_panel.visible = false;
            world.ledger.record_deal("grain merchant", {&"wheat": 14, &"barley": 5}, {&"iron": 3}, 61.0, 22.5);
            world.ledger.record_deal("herder", {&"tool_wood": 2}, {Defs.animal_key(&"chicken"): 4}, 16.0, 15.0);
            world.ledger.record_visit("herder", 1);
            world.ledger.on_day(world);
            world.hud._ledger_panel.open();
            (world.hud._ledger_panel.find_children("*", "TabContainer", true, false)[0] as TabContainer).current_tab = 2;
        210:
            get_viewport().get_texture().get_image().save_png(_out.path_join("trade_c.png"));
            get_tree().quit();
