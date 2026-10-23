# ----------------------------------------------------------------
# Defs
#     Static game data: items, buildings, crops and resource nodes.
#     Kept as dictionaries while iterating; move to .tres resources
#     once the shapes settle.
# ----------------------------------------------------------------
class_name Defs extends RefCounted;

const ITEMS:Dictionary = {
    &"wood":    {"name": "Wood",    "color": Color(0.55, 0.38, 0.22)},
    &"stone":   {"name": "Stone",   "color": Color(0.6, 0.6, 0.6)},
    &"iron":    {"name": "Iron",    "color": Color(0.55, 0.35, 0.3)},
    &"berries": {"name": "Berries", "color": Color(0.7, 0.15, 0.25), "food": true, "nutrition": 0.3},
    &"wheat":   {"name": "Wheat",   "color": Color(0.9, 0.78, 0.35), "food": true, "nutrition": 0.45},
    &"beans":   {"name": "Beans",   "color": Color(0.45, 0.6, 0.3),  "food": true, "nutrition": 0.4},
};

# shape:    visual style used by Building
# work:     labor-hours to construct
# storage:  goods can be stored here
# water:    citizens can drink here
# beds:     shelter capacity
# walkable: pawns can walk through the footprint
const BUILDINGS:Dictionary = {
    &"town_hall": {
        "name": "Town Hall", "size": Vector2i(4, 4), "cost": {}, "work": 0.0,
        "shape": "house", "height": 3.0, "color": Color(0.62, 0.48, 0.34), "roof": Color(0.42, 0.22, 0.16),
        "storage": true, "water": true, "beds": 10,
        "desc": "The heart of the colony. Stores goods, has a well and shelters the homeless.",
    },
    &"house": {
        "name": "Wooden House", "size": Vector2i(3, 3), "cost": {&"wood": 16, &"stone": 4}, "work": 24.0,
        "shape": "house", "height": 2.2, "color": Color(0.6, 0.45, 0.3), "roof": Color(0.5, 0.3, 0.18),
        "beds": 5,
        "desc": "Shelter for up to 5 citizens. Keeps them warm at night.",
    },
    &"well": {
        "name": "Well", "size": Vector2i(2, 2), "cost": {&"stone": 10, &"wood": 2}, "work": 12.0,
        "shape": "well", "height": 1.0, "color": Color(0.55, 0.55, 0.55), "roof": Color(0.45, 0.3, 0.2),
        "water": true,
        "desc": "Fresh water close to home.",
    },
    &"stockpile": {
        "name": "Stockpile", "size": Vector2i(4, 4), "cost": {&"wood": 4}, "work": 3.0,
        "shape": "pile", "height": 0.15, "color": Color(0.5, 0.42, 0.3),
        "storage": true, "walkable": true,
        "desc": "An open area where citizens drop off goods. Shortens hauling trips.",
    },
    &"field": {
        "name": "Crop Field", "size": Vector2i(6, 6), "cost": {}, "work": 6.0,
        "shape": "field", "height": 0.0, "color": Color(0.4, 0.28, 0.18),
        "field": true, "walkable": true,
        "desc": "Farmers plant, tend and harvest crops here. Choose the crop in the inspector.",
    },
};

const BUILD_MENU:Array[StringName] = [&"house", &"well", &"stockpile", &"field"];

# grow_days:  days to ripen at ideal conditions
# min_temp:   no growth below this; also the planting threshold
# frost_temp: unripe crops die below this
# fertility:  soil fertility change per harvest (negative = depletes)
const CROPS:Dictionary = {
    &"wheat": {
        "name": "Wheat", "item": &"wheat", "grow_days": 9.0, "min_temp": 4.0, "frost_temp": -2.0,
        "yield": 3, "fertility": -0.15, "color": Color(0.88, 0.75, 0.3),
    },
    &"beans": {
        "name": "Beans", "item": &"beans", "grow_days": 7.0, "min_temp": 8.0, "frost_temp": 0.5,
        "yield": 2, "fertility": 0.1, "color": Color(0.35, 0.55, 0.25),
    },
};

# solid:    blocks walking (pawns work from an adjacent cell)
# auto:     gathered without player designation (foraging)
# regrows:  not removed when empty; refills in the growing season
const RESOURCE_NODES:Dictionary = {
    &"tree": {"name": "Pine Tree",    "item": &"wood",    "amount": 4,  "work": 0.8,  "solid": false, "verb": "Chopping"},
    &"rock": {"name": "Rock",         "item": &"stone",   "amount": 8,  "work": 0.6,  "solid": true,  "verb": "Quarrying"},
    &"ore":  {"name": "Iron Deposit", "item": &"iron",    "amount": 6,  "work": 1.2,  "solid": true,  "verb": "Mining"},
    &"bush": {"name": "Berry Bush",   "item": &"berries", "amount": 5,  "work": 0.3,  "solid": false, "verb": "Foraging", "auto": true, "regrows": true},
};

static func item_name(item:StringName) -> String:
    return ITEMS[item]["name"] if ITEMS.has(item) else String(item);

static func cost_string(cost:Dictionary) -> String:
    if cost.is_empty():
        return "Free";
    var parts:PackedStringArray = [];
    for item in cost:
        parts.append("%d %s" % [cost[item], item_name(item)]);
    return ", ".join(parts);
