# ----------------------------------------------------------------
# Trade polish
#     Empty pastures count for any animal a merchant offers and take up
#     the animal led to them; waiting animals with no room are warned of;
#     every merchant brings one small off-type item; the Trading Post's
#     keep-for-trade level holds honey and spirits back from citizens;
#     the top bar shows the merchant; a merchant about to leave with an
#     open order says so; the barter window shows the usual price.
#     godot --headless --path . --fixed-fps 60 res://tests/trade_polish.tscn
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
    var t:Traders = world.traders;
    var o:Vector2i = world.town_hall.origin + Vector2i(5, -8);
    for rn in world.nodes.duplicate():
        if Rect2i(o - Vector2i(3, 3), Vector2i(26, 18)).has_point(rn.cell):
            world.remove_node(rn);
    world.terrain.flatten_rect(Rect2i(o - Vector2i(2, 2), Vector2i(28, 20)));
    var post:TradingPost = world.place_building(&"trading_post", o + Vector2i(0, 9), Vector2i(4, 3), true) as TradingPost;
    # --- empty pastures and merchants
    _expect("no pasture: no animals offered", _animals_offered(t, 100).is_empty());
    var pen:Pasture = world.place_building(&"pasture", o, Vector2i(5, 5), true) as Pasture;
    var offered:Dictionary = _animals_offered(t, 300);
    _expect("an empty pasture has room for every kind (%s)" % [offered.keys()], offered.has(Defs.animal_key(&"cow")) and offered.has(Defs.animal_key(&"sheep")) and offered.has(Defs.animal_key(&"chicken")));
    _expect("room is counted for the kind asked about (cows: %d, 5x5 / 6)" % pen.room_for(&"cow"), pen.room_for(&"cow") == 4 and pen.room_for(&"chicken") == 16);
    var counts:Dictionary = {};
    for i in 200:
        var stock:Dictionary = {};
        t._offer_animals(stock, 1.0);
        counts[stock.size()] = counts.get(stock.size(), 0) + 1;
    _expect("but one empty pasture is offered to one kind at a time (%s)" % [counts], not counts.has(2) and not counts.has(3));
    pen.add_animals(2);
    _expect("a pasture with animals only takes its own", pen.room_for(&"cow") == 0 and pen.room_for(&"chicken") > 0 and not pen.can_host(&"sheep"));
    pen.animals = 0;
    # --- leading an animal to an empty pasture of another kind
    pen.set_kind(&"chicken");
    post.animals_waiting[&"cow"] = 2;
    var tasks:TradeTasks = world.jobs.trade;
    var pawn:Pawn = world.pawns[0];
    var led:Task = tasks._guide_animals(pawn, post);
    _expect("a citizen is sent to lead the cows to the empty chicken pasture", led != null and pen.kind == &"cow" and pen.incoming_animals == 1);       # a citizen leads one cow at a time
    _expect("which became a cow pasture", pen.display_name() == "Cow Pasture");
    led.on_cancel.call(pawn);
    pen.incoming_animals = 0;
    post.animals_waiting.clear();
    # --- the warning
    var other:Pasture = world.place_building(&"pasture", o + Vector2i(8, 0), Vector2i(5, 5), true) as Pasture;
    other.set_kind(&"sheep");
    other.add_animals(8);
    pen.set_kind(&"chicken");
    pen.add_animals(1);
    post.animals_waiting[&"cow"] = 2;
    _expect("with every pasture occupied, there is no room", not post.has_pasture_room(&"cow"));
    _expect("the post says so", post.info_text().contains("no pasture has room"));
    var before:int = world.ledger.events.size();
    post.on_day();
    _expect("and the log warns (%s)" % [world.ledger.events.back()["text"]], world.ledger.events.size() > before and "no pasture has room" in world.ledger.events.back()["text"]);
    var after:int = world.ledger.events.size();
    post.on_day();
    _expect("only once in a few days", world.ledger.events.size() == after);
    pen.animals = 0;
    _expect("with an empty pasture there is room again", post.has_pasture_room(&"cow") and not post.info_text().contains("no pasture has room"));
    post.animals_waiting.clear();
    # --- one off-type item
    var ok:bool = true;
    var small:bool = true;
    for i in 300:
        var v:Dictionary = t._make_visit();
        var type:Dictionary = Traders.TYPES[v["type"]];
        var off:int = 0;
        for item in v["stock"]:
            if Defs.is_seed_key(item) or Defs.is_animal_key(item):
                continue;
            if not (type["brings"] as Array).has(item):
                off += 1;
                small = small and v["stock"][item] * Defs.trade_value(item) <= Traders.OFF_TYPE_BUDGET + Defs.trade_value(item);
                ok = ok and not v["wants"].has(item);
        ok = ok and off == 1;
    _expect("every merchant brings exactly one off-type item, and asks for nothing they sell", ok);
    _expect("in a small amount", small);
    var kinds:Dictionary = {};
    for i in 300:
        var v2:Dictionary = t._make_visit();
        for item in v2["stock"]:
            if not Defs.is_seed_key(item) and not Defs.is_animal_key(item) and not (Traders.TYPES[v2["type"]]["brings"] as Array).has(item):
                kinds[item] = true;
    _expect("and it varies (%d different goods, firewood among them: %s)" % [kinds.size(), kinds.has(&"firewood")], kinds.size() > 8 and kinds.has(&"firewood"));
    # --- keep for trade
    world.town_hall.store(&"honey", 6);
    world.town_hall.store(&"spirits", 3);
    _expect("with no level citizens can use it all", Stock.best_treat() == &"spirits");
    post.settings["keep_spirits"] = 3;
    _expect("a level holds that many back (spirits are kept, honey is drunk)", Stock.best_treat() == &"honey");
    post.settings["keep_honey"] = 6;
    _expect("nothing is drunk while both are at their levels", Stock.best_treat() == &"");
    post.settings["keep_honey"] = 4;
    _expect("only the stock above the level is used", Stock.best_treat() == &"honey" and Stock.reserve(&"honey") == 4);
    _expect("the setting is in the post's controls and the stock can still be sold", post.def["controls"].size() == 2 and Stock.available(&"honey") == 6);
    post.settings["keep_honey"] = 0;
    post.settings["keep_spirits"] = 0;
    # --- the top bar and the leaving warning
    _expect("no merchant, no note", t.top_text() == "");
    t.last_visit_day = -99;
    t.start_visit();
    _expect("on the way", t.top_text() == "Merchant on the way");
    t.merchant.state = Merchant.State.TRADING;
    t.merchant.path = [];
    t.visit = {"stock": {&"iron": 6}, "wants": {&"wheat": 1.5}, "days_left": 3, "arrived": true, "type": &"metal", "season": 0, "deals": 0};
    _expect("here, with the days left", t.top_text() == "Merchant here (3d)");
    world.town_hall.store(&"wheat", 20);
    var err:String = post.place_order({&"wheat": 6}, {&"iron": 2});
    _expect("an order is open (%s)" % err, err == "" and post.has_order());
    var events:int = world.ledger.events.size();
    t.on_day();
    _expect("two days left: no warning yet", world.ledger.events.size() == events);
    t.on_day();
    _expect("one day left with an order open: a warning (%s)" % [world.ledger.events.back()["text"]], world.ledger.events.size() == events + 1 and "leaves tomorrow" in world.ledger.events.back()["text"]);
    post.order = {};
    t.visit["days_left"] = 2;
    events = world.ledger.events.size();
    t.on_day();
    _expect("with no order open, no warning", world.ledger.events.size() == events);
    t.depart();
    _expect("leaving", t.top_text() == "Merchant leaving");
    # --- the usual price in the barter window
    var panel:TradePanel = TradePanel.new();
    world.hud.add_child(panel);
    panel.setup();
    t.visit = {"stock": {&"wheat": 5}, "wants": {&"firewood": 1.0}, "season": 0, "days_left": 3, "arrived": true, "type": &"grain", "deals": 0};
    t.merchant.state = Merchant.State.TRADING;
    panel.open(post);
    var text:String = "";
    var color:Color = Color.WHITE;
    for row in panel._buy_list.get_children():
        var ui:Dictionary = row.get_meta("ui");
        text += (ui["price"] as Label).tooltip_text;
        color = (ui["price"] as Label).get_theme_color("font_color");
    _expect("an item's tooltip shows its usual price (%s)" % text, text.contains("Usual price 2.50"));
    _expect("a dear item the colony buys is red, not green", color.r > color.g);
    print("TRADE POLISH %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _animals_offered(t:Traders, n:int) -> Dictionary:
    var seen:Dictionary = {};
    for i in n:
        var stock:Dictionary = {};
        t._offer_animals(stock, 1.0);
        for key in stock:
            seen[key] = true;
    return seen;

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
