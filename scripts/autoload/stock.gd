# ----------------------------------------------------------------
# Stock (autoload)
#     Read-only colony totals. The goods themselves live in the
#     inventories of storage buildings (Building.stored); this adds
#     them up for the HUD and for decisions like "is there food?".
# ----------------------------------------------------------------
extends Node;

func _storages() -> Array[Building]:
    var out:Array[Building] = [];
    if World.instance == null:
        return out;
    for b in World.instance.buildings:
        if b.is_storage():
            out.append(b);
    return out;

func amount(item:StringName) -> int:
    var n:int = 0;
    for b in _storages():
        n += b.amount(item);
    return n;

# Units not already promised to someone on the way to collect them.
func available(item:StringName) -> int:
    var n:int = 0;
    for b in _storages():
        n += b.available(item);
    return n;

func capacity() -> int:
    var n:int = 0;
    for b in _storages():
        n += b.capacity();
    return n;

func used() -> int:
    var n:int = 0;
    for b in _storages():
        n += b.used();
    return n;

# Whether any storage building could take at least one unit of the item right now.
func has_room_for(item:StringName) -> bool:
    for b in _storages():
        if b.can_store(item):
            return true;
    return false;

# --------------------------------
# Food helpers

func food_total() -> int:
    var total:int = 0;
    for item in Defs.ITEMS:
        if Defs.is_food(item):
            total += amount(item);
    return total;

# The treat with the biggest mood boost that has units available, or &"" if none.
func best_treat() -> StringName:
    var best:StringName = &"";
    var best_mood:float = 0.0;
    for item in Defs.ITEMS:
        if Defs.is_treat(item) and available(item) > 0 and Defs.ITEMS[item]["treat"]["mood"] > best_mood:
            best = item;
            best_mood = Defs.ITEMS[item]["treat"]["mood"];
    return best;

# The most plentiful food item with available units, or &"" if none.
func best_food() -> StringName:
    var best:StringName = &"";
    var best_n:int = 0;
    for item in Defs.ITEMS:
        if Defs.is_food(item) and available(item) > best_n:
            best = item;
            best_n = available(item);
    return best;
