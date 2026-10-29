# ----------------------------------------------------------------
# Traders
#     Merchant visits. With a finished Trading Post and no merchant
#     about, each day has a chance (about VISITS_PER_SEASON a season,
#     at least MIN_GAP_DAYS apart) of a merchant walking in from the
#     map edge. They bring goods to sell and name goods they want to
#     buy (`visit`), stay STAY_DAYS days at the post, then leave. The
#     barter itself is step 2 of M6.
# ----------------------------------------------------------------
class_name Traders extends RefCounted;

const VISITS_PER_SEASON:float = 3.0;
const MIN_GAP_DAYS     :int = 5;
const STAY_DAYS        :int = 4;
const SELL_KINDS       :Vector2i = Vector2i(3, 5);       # how many kinds of goods a merchant brings
const STOP_SHORT       :int = 4;                         # cells before the post the caravan halts
const WANT_KINDS       :Vector2i = Vector2i(3, 5);       # and how many kinds they will buy
const SELL_BUDGET      :int = 90;                        # about this much trade value of each kind
const WANT_MULT        :Vector2 = Vector2(0.8, 1.5);     # what a merchant pays for goods they want, times the value
const OTHER_PAYS       :float = 0.5;                     # ... and for goods they did not ask for
const OWN_MARGIN       :float = 1.25;                    # what they charge for their own goods, times the value

# What merchants bring, and what they ask for (trade values are in Defs.TRADE_VALUE).
const BRINGS:Array[StringName] = [&"wood", &"stone", &"iron", &"coal", &"wheat", &"barley", &"beans", &"potato", &"cabbage", &"pumpkin", &"apples", &"pears", &"eggs", &"hazelnuts", &"tool_wood", &"tool_iron", &"tool_steel"];
const WANTS:Array[StringName] = [&"wheat", &"barley", &"beans", &"potato", &"cabbage", &"pumpkin", &"apples", &"pears", &"hazelnuts", &"eggs", &"firewood", &"wood", &"stone", &"iron", &"coal", &"tool_wood", &"tool_iron", &"manure"];

var world     :World;
var merchant  :Merchant = null;
var visit     :Dictionary = {};        # {stock: item -> units, wants: item -> price multiplier, days_left: int, arrived: bool}
var last_visit_day:int = -99;
var _entry    :Vector2i = Vector2i(-1, -1);     # the edge cell they came in by (they leave the same way)

func _init(w:World) -> void:
    world = w;

func trading_post() -> Building:
    for b in world.buildings:
        if b.def.get("trade_post", false) and b.is_complete():
            return b;
    return null;

# What the colony pays for one unit of the merchant's goods, and what the merchant pays for one of ours (value units).
func buy_price(item:StringName) -> float:
    return snappedf(Defs.trade_value(item) * OWN_MARGIN, 0.01);

func sell_price(item:StringName) -> float:
    var wants:Dictionary = visit.get("wants", {});
    return snappedf(Defs.trade_value(item) * wants.get(item, OTHER_PAYS), 0.01);

func present() -> bool:
    return merchant != null and merchant.state == Merchant.State.TRADING;

func on_day() -> void:
    if merchant != null:
        if present():
            visit["days_left"] -= 1;
            if visit["days_left"] <= 0 or trading_post() == null:
                depart();
        return;
    if trading_post() == null or GameClock.day_index() - last_visit_day < MIN_GAP_DAYS:
        return;
    if world.rng.randf() < VISITS_PER_SEASON / GameClock.DAYS_PER_SEASON:
        start_visit();

# A merchant sets off for the Trading Post. Returns false when there is no post or no way in from the edge.
func start_visit() -> bool:
    var post:Building = trading_post();
    if post == null or merchant != null:
        return false;
    var route:Array[Vector2i] = [];
    var entry:Vector2i = Vector2i(-1, -1);
    for i in 60:
        var edge:Vector2i = _random_edge_cell();
        if not world.nav.is_walkable(edge):
            continue;
        route = _route(edge, post);
        if not route.is_empty():
            entry = edge;
            break;
    if route.is_empty():
        return false;
    _entry = entry;
    visit = _make_visit();
    last_visit_day = GameClock.day_index();
    _spawn(entry, route, Merchant.State.ARRIVING);
    world.notify("A merchant caravan is on the road to the Trading Post.");
    return true;

func depart() -> void:
    if merchant == null:
        return;
    var post:Building = trading_post();
    if post is TradingPost:
        (post as TradingPost).lapse();
    var back:Array[Vector2i] = _route_from(merchant.cell(), _entry);
    if back.is_empty():
        _clear();         # no way out is as good as gone
        world.notify("The merchant has gone.");
        return;
    merchant.leave(back);
    world.notify("The merchant leaves the Trading Post.");

func _clear() -> void:
    if merchant != null and is_instance_valid(merchant):
        merchant.queue_free();
    merchant = null;
    visit = {};

func _spawn(from:Vector2i, route:Array[Vector2i], st:int) -> void:
    merchant = Merchant.new();
    world.add_merchant(merchant);
    merchant.setup(world, from, route, st);
    merchant.arrived = _on_arrived;
    merchant.gone = _on_gone;

func _on_arrived() -> void:
    visit["arrived"] = true;
    world.notify("The merchant has reached the Trading Post. They will stay %d days." % visit["days_left"]);

func _on_gone() -> void:
    merchant = null;
    visit = {};

# --------------------------------
# What a visit offers

func _make_visit() -> Dictionary:
    var stock:Dictionary = {};
    var kinds:Array[StringName] = BRINGS.duplicate();
    _shuffle(kinds);
    for i in world.rng.randi_range(SELL_KINDS.x, SELL_KINDS.y):
        var item:StringName = kinds[i];
        stock[item] = maxi(1, roundi(SELL_BUDGET * world.rng.randf_range(0.5, 1.0) / float(Defs.trade_value(item))));
    var wants:Dictionary = {};
    var asks:Array[StringName] = WANTS.duplicate();
    _shuffle(asks);
    for i in world.rng.randi_range(WANT_KINDS.x, WANT_KINDS.y):
        wants[asks[i]] = snappedf(world.rng.randf_range(WANT_MULT.x, WANT_MULT.y), 0.05);
    return {"stock": stock, "wants": wants, "days_left": STAY_DAYS, "arrived": false};

func _shuffle(a:Array) -> void:
    for i in range(a.size() - 1, 0, -1):
        var j:int = world.rng.randi_range(0, i);
        var t:Variant = a[i];
        a[i] = a[j];
        a[j] = t;

# --------------------------------
# Routes

func _random_edge_cell() -> Vector2i:
    var side:int = world.rng.randi_range(0, 3);
    var t:int = world.rng.randi_range(2, Terrain.SIZE - 3);
    match side:
        0:
            return Vector2i(t, 1);
        1:
            return Vector2i(t, Terrain.SIZE - 2);
        2:
            return Vector2i(1, t);
    return Vector2i(Terrain.SIZE - 2, t);

func _route(edge:Vector2i, post:Building) -> Array[Vector2i]:
    var goals:Array[Vector2i] = world.access_cells(post.rect(), false);
    goals.sort_custom(func(a:Vector2i, b:Vector2i) -> bool: return (a - edge).length_squared() < (b - edge).length_squared());
    for i in mini(goals.size(), 4):
        var path:Array[Vector2i] = world.nav.find_path(edge, goals[i]);
        if not path.is_empty():
            for k in mini(STOP_SHORT, maxi(0, path.size() - 2)):
                path.remove_at(path.size() - 1);       # the cart and donkey are long: stop a few cells short of the stall
            return path;
    return [];

func _route_from(cell:Vector2i, edge:Vector2i) -> Array[Vector2i]:
    var start:Vector2i = world.nav.nearest_walkable(cell, 6);
    if start == NavGrid.NO_CELL or edge.x < 0:
        return [];
    return world.nav.find_path(start, edge);

# --------------------------------
# Inspector, saving

func status_text() -> String:
    if merchant == null:
        return "No merchant is about. Merchants come a few times a season.";
    if merchant.state == Merchant.State.ARRIVING:
        return "A merchant is on the road.";
    if merchant.state == Merchant.State.LEAVING:
        return "The merchant is leaving.";
    return "A merchant is here for %d more day%s." % [visit["days_left"], "" if visit["days_left"] == 1 else "s"];

func to_dict() -> Dictionary:
    var d:Dictionary = {"last_visit_day": last_visit_day};
    if merchant != null:
        var stock:Dictionary = (visit.get("stock", {}) as Dictionary).duplicate();
        var wants:Dictionary = (visit.get("wants", {}) as Dictionary).duplicate();
        d["visit"] = {"stock": stock, "wants": wants, "days_left": visit.get("days_left", 0), "arrived": visit.get("arrived", false)};
        d["merchant"] = {"state": merchant.state, "cell": merchant.cell(), "route": merchant.remaining_route(), "entry": _entry};
    return d;

func restore(d:Dictionary) -> void:
    last_visit_day = d.get("last_visit_day", -99);
    if not d.has("merchant"):
        return;
    visit = d["visit"];
    var m:Dictionary = d["merchant"];
    _entry = m["entry"];
    var route:Array[Vector2i] = [];
    for c in m["route"]:
        route.append(c);
    _spawn(m["cell"], route, m["state"]);
