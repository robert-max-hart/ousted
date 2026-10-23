# ----------------------------------------------------------------
# Defs
#     Static game data: items, buildings, crops and resource nodes.
#     Kept as dictionaries while iterating; move to .tres resources
#     once the shapes settle.
# ----------------------------------------------------------------
class_name Defs extends RefCounted;

# outside_only: only spoils when lying on the ground, never inside a storage building (firewood)
# spoil_days: spoilage time constant. A steady fraction of the stock spoils each hour, so after this
#             many days at the reference temperature (10 C) in ordinary storage about 63% is gone.
#             The temperature and the storage building scale it (see Defs.spoil_temp_factor).
const ITEMS:Dictionary = {
    &"wood":    {"name": "Wood",    "color": Color(0.55, 0.38, 0.22)},
    &"stone":   {"name": "Stone",   "color": Color(0.6, 0.6, 0.6)},
    &"iron":    {"name": "Iron",    "color": Color(0.55, 0.35, 0.3)},
    &"berries": {"name": "Berries", "color": Color(0.7, 0.15, 0.25), "food": true, "nutrition": 0.3, "spoil_days": 8.0},
    &"wheat":   {"name": "Wheat",   "color": Color(0.9, 0.78, 0.35), "food": true, "nutrition": 0.45, "spoil_days": 120.0},
    &"firewood": {"name": "Firewood", "color": Color(0.72, 0.5, 0.26), "spoil_days": 60.0, "outside_only": true},
    &"beans":   {"name": "Beans",   "color": Color(0.45, 0.6, 0.3),  "food": true, "nutrition": 0.4, "spoil_days": 90.0},
};

# shape:    visual style used by Building
# work:     labor-hours to construct
# storage:  goods can be stored here
# accepts_items: storage that only takes these items (woodcutter: wood and firewood)
# radius:   work radius in cells (shown when placing and selecting)
# worker_slots, profession: how many citizens of that profession work here
# controls: player settings shown in the inspector (type: choice, toggle or cap), stored in Building.settings
#           A "cap" control is a production cap on an output item: 0 means no cap
# fuel_capacity: housing that burns firewood to stay warm; this is how much it can hold
# spoil_mult: multiplies how fast stored food spoils here (default 1.0; lower is better)
# capacity: total units a storage building holds
# food_only: storage that only accepts food items
# water:    citizens can drink here
# beds:     shelter capacity
# walkable: pawns can walk through the footprint
const BUILDINGS:Dictionary = {
    &"town_hall": {
        "name": "Town Hall", "size": Vector2i(4, 4), "cost": {}, "work": 0.0,
        "shape": "house", "height": 3.0, "color": Color(0.62, 0.48, 0.34), "roof": Color(0.42, 0.22, 0.16),
        "storage": true, "capacity": 300, "water": true, "beds": 10,
        "desc": "The heart of the colony. Stores goods, has a well and shelters the homeless.",
    },
    &"house": {
        "name": "Wooden House", "size": Vector2i(3, 3), "cost": {&"wood": 16, &"stone": 4}, "work": 24.0,
        "shape": "house", "height": 2.2, "color": Color(0.6, 0.45, 0.3), "roof": Color(0.5, 0.3, 0.18),
        "beds": 5, "fuel_capacity": 40,
        "controls": [
            {"id": "heating", "type": "toggle", "label": "Heating", "default": true},
            {"id": "fuel_target", "type": "cap", "label": "Keep firewood stocked", "default": 20, "step": 5},
        ],
        "desc": "Shelter for up to 5 citizens. Burns firewood to keep them warm when it is cold.",
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
        "storage": true, "capacity": 150, "walkable": true,
        "desc": "An open area where citizens drop off goods. Holds 150 units. Item filters can be set in the inspector.",
    },
    &"granary": {
        "name": "Granary", "size": Vector2i(3, 3), "cost": {&"wood": 14, &"stone": 2}, "work": 14.0,
        "shape": "house", "height": 1.8, "color": Color(0.66, 0.55, 0.36), "roof": Color(0.45, 0.32, 0.2),
        "storage": true, "capacity": 300, "food_only": true, "spoil_mult": 0.5,
        "desc": "Stores food only. Holds 300 units. Item filters can be set in the inspector.",
    },
    &"woodcutter": {
        "name": "Woodcutter", "size": Vector2i(3, 3), "cost": {&"wood": 10, &"stone": 2}, "work": 10.0,
        "shape": "house", "height": 1.8, "color": Color(0.5, 0.38, 0.26), "roof": Color(0.3, 0.36, 0.2),
        "storage": true, "capacity": 120, "accepts_items": [&"wood", &"firewood"],
        "radius": 15.0, "worker_slots": 2, "profession": "WOODCUTTER",
        "produces": [&"firewood"],
        "controls": [
            {"id": "chop", "type": "choice", "label": "Chop trees", "options": ["Off", "Mature only", "All"], "default": 2},
            {"id": "plant", "type": "toggle", "label": "Plant trees", "default": true},
            {"id": "convert", "type": "toggle", "label": "Make firewood", "default": true},
            {"id": "cap_firewood", "type": "cap", "label": "Firewood cap", "item": &"firewood", "default": 100, "step": 20},
        ],
        "desc": "Fells and plants trees in a radius and splits wood into firewood. Also stores wood and firewood.",
    },
    &"field": {
        "name": "Crop Field", "size": Vector2i(6, 6), "cost": {}, "work": 6.0,
        "shape": "field", "height": 0.0, "color": Color(0.4, 0.28, 0.18),
        "field": true, "walkable": true,
        "desc": "Farmers plant, tend and harvest crops here. Choose the crop in the inspector.",
    },
};

const BUILD_MENU:Array[StringName] = [&"house", &"well", &"stockpile", &"granary", &"woodcutter", &"field"];

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
    &"tree": {"name": "Pine Tree",    "item": &"wood",    "amount": 4,  "work": 0.8,  "solid": false, "verb": "Chopping", "grow_hours": 1150.0},
    &"rock": {"name": "Rock",         "item": &"stone",   "amount": 8,  "work": 0.6,  "solid": true,  "verb": "Quarrying"},
    &"ore":  {"name": "Iron Deposit", "item": &"iron",    "amount": 6,  "work": 1.2,  "solid": true,  "verb": "Mining"},
    &"bush": {"name": "Berry Bush",   "item": &"berries", "amount": 5,  "work": 0.3,  "solid": false, "verb": "Foraging", "auto": true, "regrows": true},
};

# How much faster or slower things spoil at an air temperature (1.0 at 10 C). Doubles for every
# 10 C of warmth, and drops sharply as it nears freezing, where spoilage nearly stops.
static func spoil_temp_factor(temp:float) -> float:
    const FROZEN:float = 0.08;
    const THAW_TEMP:float = 4.0;
    var warm:float = clampf(pow(2.0, (temp - 10.0) / 10.0), 0.0, 3.0);
    if temp <= 0.0:
        return FROZEN;
    if temp < THAW_TEMP:
        return lerpf(FROZEN, pow(2.0, (THAW_TEMP - 10.0) / 10.0), temp / THAW_TEMP);
    return warm;

static func spoil_per_hour(item:StringName) -> float:
    var days:float = ITEMS[item].get("spoil_days", 0.0) if ITEMS.has(item) else 0.0;
    return 0.0 if days <= 0.0 else 1.0 / (days * GameClock.HOURS_PER_DAY);

const FIREWOOD_PER_WOOD :int = 5;       # one wood splits into this many firewood (confirmed 2026-10-23)
const HEATING_BELOW      :float = 15.0;   # C: houses burn firewood below this
const FIREWOOD_PER_DAY_AT_0C:float = 2.0;   # burn rate at 0 C; scales linearly with how far below HEATING_BELOW it is
const SPLIT_BATCH       :int = 2;       # wood split per task
const SPLIT_HOURS_PER_WOOD:float = 0.5;  # labor hours to split one wood

static func is_food(item:StringName) -> bool:
    return ITEMS.has(item) and ITEMS[item].get("food", false);

static func item_name(item:StringName) -> String:
    return ITEMS[item]["name"] if ITEMS.has(item) else String(item);

static func cost_string(cost:Dictionary) -> String:
    if cost.is_empty():
        return "Free";
    var parts:PackedStringArray = [];
    for item in cost:
        parts.append("%d %s" % [cost[item], item_name(item)]);
    return ", ".join(parts);
