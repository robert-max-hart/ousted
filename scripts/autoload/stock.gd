# ----------------------------------------------------------------
# Stock (autoload)
#     Colony-wide inventory. Pawns still physically carry goods to and
#     from storage buildings; this just tracks the totals. Reservations
#     keep two pawns from claiming the same units.
# ----------------------------------------------------------------
extends Node;

signal changed;

var _items      :Dictionary = {};   # StringName -> int
var _reserved   :Dictionary = {};   # StringName -> int

func reset(start:Dictionary) -> void:
    _items = start.duplicate();
    _reserved.clear();
    changed.emit();

func amount(item:StringName) -> int:
    return _items.get(item, 0);

func available(item:StringName) -> int:
    return amount(item) - _reserved.get(item, 0);

func add(item:StringName, n:int) -> void:
    if n <= 0:
        return;
    _items[item] = amount(item) + n;
    changed.emit();

# Removes up to n units, returns how many were taken.
func take(item:StringName, n:int) -> int:
    var t:int = mini(n, amount(item));
    _items[item] = amount(item) - t;
    changed.emit();
    return t;

# Reserves up to n available units, returns how many were reserved.
func reserve(item:StringName, n:int) -> int:
    var r:int = clampi(n, 0, available(item));
    _reserved[item] = _reserved.get(item, 0) + r;
    return r;

func unreserve(item:StringName, n:int) -> void:
    _reserved[item] = maxi(0, _reserved.get(item, 0) - n);

func take_reserved(item:StringName, n:int) -> int:
    unreserve(item, n);
    return take(item, n);

# --------------------------------
# Food helpers

func food_total() -> int:
    var total:int = 0;
    for item in Defs.ITEMS:
        if Defs.ITEMS[item].get("food", false):
            total += amount(item);
    return total;

# The most plentiful food item with available units, or &"" if none.
func best_food() -> StringName:
    var best:StringName = &"";
    var best_n:int = 0;
    for item in Defs.ITEMS:
        if Defs.ITEMS[item].get("food", false) and available(item) > best_n:
            best = item;
            best_n = available(item);
    return best;
