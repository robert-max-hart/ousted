# ----------------------------------------------------------------
# TradingPost
#     Where the merchant's deals are carried out. An order says what
#     the colony sells and what it buys. Citizens haul the sold goods
#     from storage into the post's yard (`delivered`); only when every
#     sold unit has arrived does the merchant take them, hand over the
#     purchases (`pickup`, carried to storage by citizens) and the deal
#     is settled. An order the merchant leaves before it is complete
#     lapses and the delivered goods go back to `pickup`.
# ----------------------------------------------------------------
class_name TradingPost extends Building;

var order     :Dictionary = {};        # {sell: item -> units, buy: item -> units, delivered: item -> units, sold_value: float}
var en_route  :Dictionary = {};        # item -> units citizens are carrying to the yard now (not saved)
var pickup    :Dictionary = {};        # item -> units waiting at the post for citizens to carry to storage

func has_order() -> bool:
    return not order.is_empty();

func idle() -> bool:
    return order.is_empty() and pickup.is_empty();

# --------------------------------
# Placing an order

# "" when the order was placed, else why not. Sell and buy are item -> units.
func place_order(sell:Dictionary, buy:Dictionary) -> String:
    var traders:Traders = world.traders;
    if not traders.present():
        return "There is no merchant here.";
    if has_order():
        return "An order is already being carried out.";
    if buy.is_empty():
        return "Choose something to buy.";
    var stock:Dictionary = traders.visit["stock"];
    var cost:float = 0.0;
    for item in buy:
        if buy[item] <= 0 or buy[item] > stock.get(item, 0):
            return "The merchant does not have that much %s." % Defs.item_name(item).to_lower();
        cost += buy[item] * traders.buy_price(item);
    var income:float = 0.0;
    for item in sell:
        if sell[item] <= 0 or sell[item] > Stock.available(item):
            return "The colony does not have that much %s to spare." % Defs.item_name(item).to_lower();
        income += sell[item] * traders.sell_price(item);
    if income + 0.0001 < cost:
        return "What you offer is worth %.1f, what you ask for costs %.1f." % [income, cost];
    order = {"sell": sell.duplicate(), "buy": buy.duplicate(), "delivered": {}, "sold_value": income};
    if sell.is_empty():
        settle();       # nothing to haul: a gift is only possible at zero cost, so this never happens
    return "";

# Units of a sold item still to be carried here (not counting what is on the way).
func owed(item:StringName) -> int:
    if not has_order():
        return 0;
    return maxi(0, order["sell"].get(item, 0) - order["delivered"].get(item, 0) - en_route.get(item, 0));

func owed_items() -> Array[StringName]:
    var out:Array[StringName] = [];
    if has_order():
        for item in order["sell"]:
            if owed(item) > 0:
                out.append(item);
    return out;

# A citizen drops sold goods in the yard.
func deliver(item:StringName, n:int) -> void:
    if not has_order():
        pickup[item] = pickup.get(item, 0) + n;       # the order ended on the way: take it back
        return;
    order["delivered"][item] = order["delivered"].get(item, 0) + n;
    en_route[item] = maxi(0, en_route.get(item, 0) - n);
    if order_complete():
        settle();

func order_complete() -> bool:
    for item in order["sell"]:
        if order["delivered"].get(item, 0) < order["sell"][item]:
            return false;
    return true;

# Every sold unit is here: the merchant takes them and hands over the purchases.
func settle() -> void:
    var stock:Dictionary = world.traders.visit.get("stock", {});
    for item in order["buy"]:
        stock[item] = stock.get(item, 0) - order["buy"][item];
        if stock[item] <= 0:
            stock.erase(item);
        pickup[item] = pickup.get(item, 0) + order["buy"][item];
    world.notify("Trade done: %s. The goods are ready to be carried from the Trading Post." % _summary(order["sell"], order["buy"]));
    order = {};

# The merchant has gone with the order unfinished: what was delivered goes back to storage.
func lapse() -> void:
    if not has_order():
        return;
    for item in order["delivered"]:
        pickup[item] = pickup.get(item, 0) + order["delivered"][item];
    world.notify("The merchant left before the deal was done. The goods already brought are being carried back.");
    order = {};
    en_route.clear();

func _summary(sell:Dictionary, buy:Dictionary) -> String:
    var out:Array[String] = [];
    for item in sell:
        out.append("%d %s" % [sell[item], Defs.item_name(item).to_lower()]);
    var gave:String = ", ".join(out) if not out.is_empty() else "nothing";
    out.clear();
    for item in buy:
        out.append("%d %s" % [buy[item], Defs.item_name(item).to_lower()]);
    return "sold %s for %s" % [gave, ", ".join(out)];

# --------------------------------
# Pickup (citizens carry it to storage)

func take_pickup(item:StringName, n:int) -> int:
    var t:int = mini(n, pickup.get(item, 0));
    pickup[item] = pickup.get(item, 0) - t;
    if pickup[item] <= 0:
        pickup.erase(item);
    return t;

# Everything still here goes back into storage (the post is being demolished).
func dump_goods() -> void:
    for item in order.get("delivered", {}):
        pickup[item] = pickup.get(item, 0) + order["delivered"][item];
    order = {};
    for item in pickup:
        world.deposit(item, pickup[item], position);
    pickup.clear();

# --------------------------------
# Saving, info

func to_dict() -> Dictionary:
    var d:Dictionary = super.to_dict();
    d["order"] = order.duplicate(true);
    d["pickup"] = pickup.duplicate();
    return d;

func restore_dict(d:Dictionary) -> void:
    super.restore_dict(d);
    order = d.get("order", {});
    pickup = d.get("pickup", {});

func info_text() -> String:
    var s:String = super.info_text();
    if state != State.COMPLETE:
        return s;
    if has_order():
        s += "Order in progress:\n";
        for item in order["sell"]:
            s += "  %s: %d of %d delivered\n" % [Defs.item_name(item), order["delivered"].get(item, 0), order["sell"][item]];
    if not pickup.is_empty():
        var parts:PackedStringArray = [];
        for item in pickup:
            parts.append("%d %s" % [pickup[item], Defs.item_name(item).to_lower()]);
        s += "Waiting to be carried to storage: %s\n" % ", ".join(parts);
    return s;
