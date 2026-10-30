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
const STOP_SHORT       :int = 4;                         # cells before the post the caravan halts
const SEED_OFFERS      :Vector2i = Vector2i(1, 3);       # how many seeds or saplings a visit offers, at most (from what is not known yet)
const IN_SEASON_WEIGHT :float = 3.0;                     # a crop that can be sown now is this much likelier to be offered
const ANIMAL_CHANCE    :float = 0.7;                     # a kind of animal is offered with this chance, when a pasture for it has room
const SELL_BUDGET      :int = 90;                        # about this much trade value of each kind
const OFF_TYPE_BUDGET  :int = 30;                        # about this much trade value of the one thing every merchant brings that is not their line
const OTHER_PAYS       :float = 0.5;                     # ... and for goods they did not ask for
const OWN_MARGIN       :float = 1.25;                    # what they charge for their own goods, times the value

const LUXURY_MULT      :Vector2 = Vector2(1.4, 2.2);     # what any merchant pays for a luxury they ask for, times the value
const LUXURIES:Array[StringName] = [&"honey", &"spirits", &"pottery", &"clothes_fine", &"silver", &"gold"];

# The kinds of merchant. Each draws what it brings and what it asks for from its own lists (the same item is never in
# both on one visit, so nobody can buy from a merchant and sell straight back), has a weight for how often it calls
# (the same in every season), the share of its visits that offer seeds and saplings (`seeds`) and animals (`animals`,
# times ANIMAL_CHANCE), how many kinds it brings and asks for, the price multipliers for what it asks for (luxuries
# always use LUXURY_MULT or better), and the colours of its cart: [stripe, stripe, trader's coat].
const TYPES:Dictionary = {
    &"grain": {
        "name": "grain merchant", "weight": 3.0, "seeds": 1.0, "animals": 0.3, "sells": Vector2i(3, 5), "asks": Vector2i(3, 5), "mult": Vector2(0.8, 1.5),
        "brings": [&"wheat", &"barley", &"beans", &"potato", &"cabbage", &"pumpkin", &"apples", &"pears", &"hazelnuts", &"eggs", &"honey", &"radish", &"lettuce"],
        "wants": [&"tool_wood", &"tool_iron", &"wood", &"stone", &"iron", &"firewood", &"wool", &"clothes_wool", &"clothes_leather", &"pottery", &"manure", &"spirits"],
        "colors": [Color(0.78, 0.62, 0.2), Color(0.93, 0.87, 0.7), Color(0.5, 0.42, 0.2)],
    },
    &"metal": {
        "name": "metal trader", "weight": 2.0, "seeds": 0.15, "animals": 0.0, "sells": Vector2i(3, 5), "asks": Vector2i(3, 5), "mult": Vector2(0.8, 1.5),
        "brings": [&"wood", &"stone", &"iron", &"coal", &"tool_wood", &"tool_iron", &"tool_steel", &"silver", &"gold"],
        "wants": [&"wheat", &"barley", &"beans", &"potato", &"cabbage", &"pumpkin", &"apples", &"pears", &"hazelnuts", &"eggs", &"meat", &"honey", &"spirits", &"clothes_wool", &"clothes_leather", &"firewood", &"leather"],
        "colors": [Color(0.38, 0.4, 0.46), Color(0.82, 0.8, 0.76), Color(0.3, 0.32, 0.38)],
    },
    &"herder": {
        "name": "herder", "weight": 2.0, "seeds": 0.5, "animals": 1.0, "sells": Vector2i(2, 4), "asks": Vector2i(3, 5), "mult": Vector2(0.9, 1.6),
        "brings": [&"wool", &"leather", &"meat", &"eggs", &"clothes_wool", &"clothes_leather", &"honey"],
        "wants": [&"wheat", &"barley", &"beans", &"manure", &"firewood", &"wood", &"tool_wood", &"tool_iron", &"pottery", &"spirits", &"coal"],
        "colors": [Color(0.3, 0.5, 0.3), Color(0.93, 0.87, 0.7), Color(0.4, 0.3, 0.2)],
    },
    &"luxury": {
        "name": "fine goods caravan", "weight": 1.5, "seeds": 0.15, "animals": 0.0, "sells": Vector2i(3, 4), "asks": Vector2i(4, 6), "mult": Vector2(1.0, 1.6),
        "brings": [&"honey", &"spirits", &"pottery", &"clothes_fine", &"clothes_wool", &"clothes_leather", &"silver", &"gold"],
        "wants": [&"honey", &"spirits", &"pottery", &"clothes_fine", &"silver", &"gold", &"wool", &"leather", &"clothes_wool", &"clothes_leather"],
        "colors": [Color(0.5, 0.22, 0.5), Color(0.9, 0.78, 0.35), Color(0.34, 0.16, 0.38)],
    },
};

# Seasonal price: what an item is worth against its trade value in spring, summer, autumn and winter (fixed for a visit).
# Availability is not seasonal, only the price. An item not listed is worth the same all year.
const SEASON_PRICE:Dictionary = {
    &"wheat": [1.3, 1.1, 0.75, 1.0], &"barley": [1.3, 1.1, 0.75, 1.0], &"beans": [1.3, 1.1, 0.75, 1.0],
    &"potato": [1.3, 1.1, 0.75, 1.0], &"cabbage": [1.3, 1.1, 0.75, 1.0], &"pumpkin": [1.3, 1.1, 0.7, 1.0],
    &"radish": [1.1, 0.9, 0.85, 1.2], &"lettuce": [1.0, 0.8, 0.9, 1.4],
    &"apples": [1.3, 1.1, 0.7, 1.0], &"pears": [1.3, 1.1, 0.7, 1.0], &"hazelnuts": [1.2, 1.2, 0.8, 1.0],
    &"eggs": [0.9, 0.9, 1.1, 1.3], &"meat": [1.0, 1.0, 0.85, 1.25], &"honey": [1.1, 0.9, 0.9, 1.15],
    &"firewood": [0.9, 0.7, 1.0, 1.5], &"coal": [1.0, 0.8, 1.1, 1.4],
    &"wool": [1.0, 0.9, 1.0, 1.2], &"leather": [1.0, 0.95, 1.0, 1.15],
    &"clothes_wool": [1.0, 0.8, 1.2, 1.4], &"clothes_leather": [1.0, 0.8, 1.2, 1.4], &"clothes_fine": [1.0, 0.85, 1.2, 1.3],
    &"spirits": [0.9, 0.9, 1.0, 1.3], &"manure": [1.4, 1.0, 1.0, 0.8],
};
const PRICE_NOTE:float = 0.1;       # the barter window marks an item as dear or cheap when its season moves it this far from normal

# What merchants bring, and what they ask for: all of the types' lists together (trade values are in Defs.TRADE_VALUE).
const BRINGS:Array[StringName] = [&"wood", &"stone", &"iron", &"coal", &"silver", &"gold", &"wheat", &"barley", &"beans", &"potato", &"cabbage", &"pumpkin", &"apples", &"pears", &"eggs", &"hazelnuts", &"radish", &"lettuce", &"honey", &"spirits", &"pottery", &"wool", &"leather", &"clothes_wool", &"clothes_leather", &"clothes_fine", &"meat", &"tool_wood", &"tool_iron", &"tool_steel"];
const WANTS:Array[StringName] = [&"wheat", &"barley", &"beans", &"potato", &"cabbage", &"pumpkin", &"apples", &"pears", &"hazelnuts", &"eggs", &"honey", &"spirits", &"pottery", &"clothes_wool", &"clothes_leather", &"clothes_fine", &"leather", &"wool", &"firewood", &"wood", &"stone", &"iron", &"coal", &"silver", &"gold", &"tool_wood", &"tool_iron", &"manure"];

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
    return snappedf(Defs.trade_value(item) * OWN_MARGIN * season_factor(item), 0.01);

func sell_price(item:StringName) -> float:
    var wants:Dictionary = visit.get("wants", {});
    return snappedf(Defs.trade_value(item) * wants.get(item, OTHER_PAYS) * season_factor(item), 0.01);

# The season's effect on an item's worth, in the season the merchant arrived (1 with no visit or for items with no season).
func season_factor(item:StringName) -> float:
    var s:int = visit.get("season", -1);
    if s < 0 or not SEASON_PRICE.has(item):
        return 1.0;
    return SEASON_PRICE[item][s];

func type_id() -> StringName:
    return visit.get("type", &"grain");

# "grain merchant", "herder" and so on, for messages.
func type_name() -> String:
    return TYPES[type_id()]["name"];

func present() -> bool:
    return merchant != null and merchant.state == Merchant.State.TRADING;

func on_day() -> void:
    if merchant != null:
        if present():
            visit["days_left"] -= 1;
            if visit["days_left"] <= 0 or trading_post() == null:
                depart();
            elif visit["days_left"] == 1:
                var post:Building = trading_post();
                if post is TradingPost and (post as TradingPost).has_order():
                    world.notify("The %s leaves tomorrow and the order at the Trading Post is not finished: the goods still to be carried there will not make it unless citizens hurry." % type_name());
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
    world.notify("A %s is on the road to the Trading Post." % type_name());
    return true;

func depart() -> void:
    if merchant == null:
        return;
    var post:Building = trading_post();
    if post is TradingPost:
        (post as TradingPost).lapse();
    world.ledger.record_visit(type_name(), visit.get("deals", 0));
    var back:Array[Vector2i] = _route_from(merchant.cell(), _entry);
    if back.is_empty():
        _clear();         # no way out is as good as gone
        world.notify("The %s has gone." % type_name());
        return;
    merchant.leave(back);
    world.notify("The %s leaves the Trading Post." % type_name());

func _clear() -> void:
    if merchant != null and is_instance_valid(merchant):
        merchant.queue_free();
    merchant = null;
    visit = {};

func _spawn(from:Vector2i, route:Array[Vector2i], st:int) -> void:
    merchant = Merchant.new();
    merchant.palette = TYPES[type_id()]["colors"];
    world.add_merchant(merchant);
    merchant.setup(world, from, route, st);
    merchant.arrived = _on_arrived;
    merchant.gone = _on_gone;

func _on_arrived() -> void:
    visit["arrived"] = true;
    world.notify("The %s has reached the Trading Post. They will stay %d days." % [type_name(), visit["days_left"]]);

func _on_gone() -> void:
    merchant = null;
    visit = {};

# --------------------------------
# What a visit offers

func _make_visit() -> Dictionary:
    var kind:StringName = _pick_type();
    var type:Dictionary = TYPES[kind];
    var stock:Dictionary = {};
    var kinds:Array[StringName] = [];
    kinds.assign(type["brings"]);
    _shuffle(kinds);
    var sells:Vector2i = type["sells"];
    for i in mini(world.rng.randi_range(sells.x, sells.y), kinds.size()):
        var item:StringName = kinds[i];
        stock[item] = maxi(1, roundi(SELL_BUDGET * world.rng.randf_range(0.5, 1.0) / float(Defs.trade_value(item))));
    _add_off_type(stock, type);
    var wants:Dictionary = {};
    var asks:Array[StringName] = [];
    for item in type["wants"]:
        if not stock.has(item):       # never both: they would sell what they buy back at a profit
            asks.append(item);
    _shuffle(asks);
    var count:Vector2i = type["asks"];
    var mult:Vector2 = type["mult"];
    for i in mini(world.rng.randi_range(count.x, count.y), asks.size()):
        var m:float = world.rng.randf_range(mult.x, mult.y);
        if LUXURIES.has(asks[i]):
            m = maxf(m, world.rng.randf_range(LUXURY_MULT.x, LUXURY_MULT.y));
        wants[asks[i]] = snappedf(m, 0.05);
    if world.rng.randf() < type["seeds"]:
        _offer_seeds(stock);
    _offer_animals(stock, type["animals"]);
    return {"stock": stock, "wants": wants, "days_left": STAY_DAYS, "arrived": false, "type": kind, "season": GameClock.season(), "deals": 0};

# Every merchant also has a small amount of one thing that is not their line: a random tradeable item they do not
# otherwise bring.
func _add_off_type(stock:Dictionary, type:Dictionary) -> void:
    var pool:Array[StringName] = [];
    for item in Defs.TRADE_VALUE:
        if not stock.has(item) and not (type["brings"] as Array).has(item):
            pool.append(item);
    if pool.is_empty():
        return;
    var item:StringName = pool[world.rng.randi_range(0, pool.size() - 1)];
    stock[item] = maxi(1, roundi(OFF_TYPE_BUDGET * world.rng.randf_range(0.5, 1.0) / float(Defs.trade_value(item))));

# A kind of merchant by weight (the same all year round).
func _pick_type() -> StringName:
    var total:float = 0.0;
    for id in TYPES:
        total += TYPES[id]["weight"];
    var roll:float = world.rng.randf() * total;
    for id in TYPES:
        roll -= TYPES[id]["weight"];
        if roll <= 0.0:
            return id;
    return &"grain";

# Seeds and saplings the colony does not have yet (any crop, those that can be sown now likelier). One of each.
func _offer_seeds(stock:Dictionary) -> void:
    var locked:Array[StringName] = world.seeds.locked();
    var n:int = mini(world.rng.randi_range(SEED_OFFERS.x, SEED_OFFERS.y), locked.size());
    for i in n:
        var total:float = 0.0;
        var weights:Array[float] = [];
        for crop in locked:
            var w:float = IN_SEASON_WEIGHT if Weather.can_sow(Defs.CROPS[crop]) else 1.0;
            weights.append(w);
            total += w;
        var roll:float = world.rng.randf() * total;
        var pick:int = locked.size() - 1;
        for k in locked.size():
            roll -= weights[k];
            if roll <= 0.0:
                pick = k;
                break;
        stock[Defs.seed_key(locked[pick])] = 1;
        locked.remove_at(pick);

# Animals, for the kinds the colony has a pasture with room for (an empty pasture has room for any kind, but only
# for one of them: once it is counted for an offer it is not counted for another).
func _offer_animals(stock:Dictionary, share:float = 1.0) -> void:
    if share <= 0.0:
        return;
    var used:Dictionary = {};
    for kind in Defs.ANIMALS:
        var room:int = 0;
        var counted:Array[Pasture] = [];
        for b in world.buildings:
            if b is Pasture and b.is_complete() and not used.has(b):
                var pen:Pasture = b as Pasture;
                var r:int = pen.room_for(kind);
                room += r;
                if r > 0 and pen.can_change_kind():
                    counted.append(pen);
        var post:Building = trading_post();
        if post is TradingPost:
            room -= (post as TradingPost).animals_waiting.get(kind, 0);
        if room > 0 and world.rng.randf() < ANIMAL_CHANCE * share:
            stock[Defs.animal_key(kind)] = mini(room, world.rng.randi_range(1, Defs.ANIMALS[kind]["start"]));
            for pen in counted:
                used[pen] = true;

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

# A short note for the top bar: empty when no merchant is about.
func top_text() -> String:
    if merchant == null:
        return "";
    if merchant.state == Merchant.State.ARRIVING:
        return "Merchant on the way";
    if merchant.state == Merchant.State.LEAVING:
        return "Merchant leaving";
    return "Merchant here (%dd)" % visit.get("days_left", 0);

func status_text() -> String:
    if merchant == null:
        return "No merchant is about. Merchants come a few times a season.";
    if merchant.state == Merchant.State.ARRIVING:
        return "A %s is on the road." % type_name();
    if merchant.state == Merchant.State.LEAVING:
        return "The %s is leaving." % type_name();
    return "A %s is here for %d more day%s." % [type_name(), visit["days_left"], "" if visit["days_left"] == 1 else "s"];

func to_dict() -> Dictionary:
    var d:Dictionary = {"last_visit_day": last_visit_day};
    if merchant != null:
        var stock:Dictionary = (visit.get("stock", {}) as Dictionary).duplicate();
        var wants:Dictionary = (visit.get("wants", {}) as Dictionary).duplicate();
        d["visit"] = {"stock": stock, "wants": wants, "days_left": visit.get("days_left", 0), "arrived": visit.get("arrived", false), "type": type_id(), "season": visit.get("season", -1), "deals": visit.get("deals", 0)};
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
