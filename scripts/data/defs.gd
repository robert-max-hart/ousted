# ----------------------------------------------------------------
# Defs
#     Static game data: items, buildings, crops and resource nodes.
#     Kept as dictionaries while iterating; move to .tres resources
#     once the shapes settle.
# ----------------------------------------------------------------
class_name Defs extends RefCounted;

# heat:     burns as house fuel; how many firewood-equivalents one unit is worth (coal burns twice as long)
# tool:     an item citizens equip. bonus: extra work speed (0.10 = 10% faster). uses: game hours of work
#           before it breaks. A citizen carries one tool and keeps it until it breaks.
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
    &"firewood": {"name": "Firewood", "color": Color(0.72, 0.5, 0.26), "spoil_days": 60.0, "outside_only": true, "heat": 1},
    &"beans":   {"name": "Beans",   "color": Color(0.45, 0.6, 0.3),  "food": true, "nutrition": 0.4, "spoil_days": 90.0},
    &"coal":    {"name": "Coal",    "color": Color(0.16, 0.16, 0.18), "heat": 2},
    &"tool_wood":  {"name": "Wooden Tool", "color": Color(0.7, 0.55, 0.35), "tool": {"bonus": 0.10, "uses": 100.0}},
    &"tool_iron":  {"name": "Iron Tool",   "color": Color(0.6, 0.6, 0.65),  "tool": {"bonus": 0.25, "uses": 200.0}},
    &"tool_steel": {"name": "Steel Tool",  "color": Color(0.75, 0.82, 0.9), "tool": {"bonus": 0.50, "uses": 500.0}},
};

# shape:    visual style used by Building
# work:     labor-hours to construct
# storage:  goods can be stored here
# accepts_items: storage that only takes these items (woodcutter: wood and firewood)
# upgrades: id -> {name, cost, work, desc, excludes: [ids], requires: [ids]}. Paid for and built like a
#           building (materials hauled in, then labor), one at a time, while the building keeps working.
#           "excludes" makes upgrades mutually exclusive; a building may have any number of them.
# locked_until: item -> upgrade id that must be built before the building handles that item (mine: coal)
# inputs:   production buildings keep their own input inventory: item -> how many to keep stocked.
#           Inputs are not part of the colony stock. Citizens fetch them from storage.
# recipes:  output item -> {inputs: item -> n per craft, hours: labor-hours per craft, yield: units made per craft
#           (default 1), batch: crafts per task (default 1), toggle: id of the on/off control (default "make_<item>")}.
#           Recipes are tried in the order written, so list the preferred one first.
# needs_tool: item -> minimum tool bonus to dig it at full speed; weaker or no tools dig it at HARD_ORE_UNTOOLED_SPEED
# mine_hours: labor-hours to dig one unit of each item (a surface rock or deposit is 2.5x quicker)
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
            {"id": "fuel_type", "type": "choice", "label": "Burn", "options": ["Firewood", "Coal", "Either"], "default": 0},
            {"id": "fuel_target", "type": "cap", "label": "Keep fuel stocked", "default": 20, "step": 5},
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
        "storage": true, "capacity": 120, "accepts_items": [&"firewood"],
        "radius": 15.0, "worker_slots": 2, "profession": "WOODCUTTER",
        "produces": [&"firewood"],
        "inputs": {&"wood": 6},
        "recipes": {
            &"firewood": {"inputs": {&"wood": 1}, "yield": 5, "hours": 0.5, "batch": 2, "toggle": "convert"},
        },
        "controls": [
            {"id": "chop", "type": "choice", "label": "Chop trees", "options": ["Off", "Mature only", "All"], "default": 2},
            {"id": "plant", "type": "toggle", "label": "Plant trees", "default": true},
            {"id": "convert", "type": "toggle", "label": "Make firewood", "default": true},
            {"id": "cap_firewood", "type": "cap", "label": "Firewood cap", "item": &"firewood", "default": 100, "step": 20},
        ],
        "desc": "Fells and plants trees in a radius, and splits wood fetched from storage into firewood (1 wood makes 5). Stores the firewood.",
    },
    &"mine": {
        "name": "Mine", "size": Vector2i(5, 5), "cost": {&"wood": 30, &"stone": 8}, "work": 30.0,
        "shape": "mine", "height": 1.6, "color": Color(0.5, 0.48, 0.45), "roof": Color(0.36, 0.28, 0.2),
        "worker_slots": 3, "profession": "MINER",
        "produces": [&"iron", &"stone"],
        "mine_hours": {&"stone": 1.5, &"iron": 3.0, &"coal": 6.0},
        "needs_tool": {&"coal": 0.25},
        "locked_until": {&"coal": &"deep_shafts"},
        "upgrades": {
            &"deep_shafts": {
                "name": "Deep Shafts", "cost": {&"wood": 20, &"stone": 12, &"iron": 6}, "work": 24.0,
                "desc": "Sinks shafts down to the coal seams. Unlocks mining coal here.",
            },
        },
        "controls": [
            {"id": "cap_iron", "type": "cap", "label": "Iron cap", "item": &"iron", "default": 40, "step": 10},
            {"id": "cap_coal", "type": "cap", "label": "Coal cap", "item": &"coal", "default": 30, "step": 10, "requires_upgrade": &"deep_shafts"},
            {"id": "cap_stone", "type": "cap", "label": "Stone cap", "item": &"stone", "default": 100, "step": 20},
        ],
        "desc": "Digs iron, coal and stone without running out, but 2.5 times slower than gathering at the surface, and coal takes twice as long as iron (miners without an iron or steel tool dig it at a quarter of the speed). Iron comes first, then coal, then stone, each until its cap is reached. Coal needs the Deep Shafts upgrade. No storage. Miners carry the ore to a storage building, and work the surface if there is no mine to work at.",
    },
    &"blacksmith": {
        "name": "Blacksmith", "size": Vector2i(3, 3), "cost": {&"wood": 14, &"stone": 6}, "work": 16.0,
        "shape": "house", "height": 1.9, "color": Color(0.38, 0.36, 0.36), "roof": Color(0.25, 0.22, 0.22),
        "storage": true, "capacity": 60, "accepts_items": [&"tool_wood", &"tool_iron", &"tool_steel"],
        "worker_slots": 2, "profession": "BLACKSMITH",
        "produces": [&"tool_steel", &"tool_iron", &"tool_wood"],
        "inputs": {&"wood": 4, &"iron": 3, &"coal": 3},
        "recipes": {
            &"tool_steel": {"inputs": {&"wood": 1, &"iron": 1, &"coal": 1}, "hours": 2.0},
            &"tool_iron":  {"inputs": {&"wood": 1, &"iron": 1}, "hours": 1.0},
            &"tool_wood":  {"inputs": {&"wood": 1}, "hours": 0.5},
        },
        "controls": [
            {"id": "make_tool_steel", "type": "toggle", "label": "Make steel tools", "default": true},
            {"id": "cap_tool_steel", "type": "cap", "label": "Steel tool cap", "item": &"tool_steel", "default": 5, "step": 5},
            {"id": "make_tool_iron", "type": "toggle", "label": "Make iron tools", "default": true},
            {"id": "cap_tool_iron", "type": "cap", "label": "Iron tool cap", "item": &"tool_iron", "default": 5, "step": 5},
            {"id": "make_tool_wood", "type": "toggle", "label": "Make wooden tools", "default": true},
            {"id": "cap_tool_wood", "type": "cap", "label": "Wooden tool cap", "item": &"tool_wood", "default": 5, "step": 5},
        ],
        "desc": "Makes tools that speed up work: steel first, then iron, then wooden, whichever it has the materials for. Tiers can be switched off. Stores finished tools; citizens pick them up and equip them.",
    },
    &"school": {
        "name": "School", "size": Vector2i(4, 4), "cost": {&"wood": 24, &"stone": 8}, "work": 24.0,
        "shape": "house", "height": 2.2, "color": Color(0.72, 0.64, 0.46), "roof": Color(0.34, 0.3, 0.42),
        "worker_slots": 1, "profession": "TEACHER", "school_capacity": 12,
        "desc": "Children from 5 to 17 study here while a teacher is present (8:00 to 16:00), which builds general experience and makes them faster at every job. Holds 12 children and needs a teacher.",
    },
    &"field": {
        "name": "Crop Field", "size": Vector2i(6, 6), "cost": {}, "work": 6.0,
        "shape": "field", "height": 0.0, "color": Color(0.4, 0.28, 0.18),
        "field": true, "walkable": true,
        "desc": "Farmers plant, tend and harvest crops here. Choose the crop in the inspector.",
    },
};

const BUILD_MENU:Array[StringName] = [&"house", &"well", &"stockpile", &"granary", &"woodcutter", &"mine", &"blacksmith", &"school", &"field"];

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

# --------------------------------
# Life stages (decided 2026-10-23): baby under 5, child 5 to 17, adult from 18. Citizens age faster than the
# calendar; ageing_days_per_year is the adjustable rate (calendar days per citizen year; saved with the game).
const BABY_UNTIL        :float = 5.0;
const ADULT_AT          :float = 18.0;
const CHILD_EFFICIENCY  :float = 0.5;     # placeholder until schools exist: children do light general work
# [age, work efficiency] points, linear between them: a few points lost through old age, then a steep fall
const OLD_AGE_EFFICIENCY:Array = [[60.0, 1.0], [75.0, 0.95], [90.0, 0.4]];
# [age, chance of dying per citizen year] points, linear between them, 0 below the first: gentler than the fall in efficiency
const OLD_AGE_DEATH_PER_YEAR:Array = [[59.99, 0.0], [60.0, 0.02], [70.0, 0.05], [75.0, 0.10], [85.0, 0.20], [90.0, 0.35], [100.0, 0.60]];
static var ageing_days_per_year:float = 4.0;

# Schooling (decided 2026-10-23): children study 8:00 to 16:00 with a teacher present. School builds general
# experience, which speeds up all work. Gains get harder as the value rises: a child at school for every school
# hour from 5 to 17 ends up about 23% faster.
const SCHOOL_START      :float = 8.0;
const SCHOOL_END        :float = 16.0;
const GENERAL_XP_RATE   :float = 0.0012;  # experience (as a work speed bonus) per school hour at zero
const GENERAL_XP_HALF   :float = 0.1;     # the rate halves when experience reaches this

static func general_xp_gain(xp:float, hours:float) -> float:
    return GENERAL_XP_RATE * hours / (1.0 + xp / GENERAL_XP_HALF);

# Linear interpolation through [x, y] points sorted by x, flat beyond the ends.
static func curve(points:Array, x:float) -> float:
    if x <= points[0][0]:
        return points[0][1];
    for i in range(1, points.size()):
        if x <= points[i][0]:
            var a:Array = points[i - 1];
            var b:Array = points[i];
            return lerpf(a[1], b[1], (x - a[0]) / (b[0] - a[0]));
    return points[points.size() - 1][1];

static func age_efficiency(age:float) -> float:
    return curve(OLD_AGE_EFFICIENCY, age);

# Chance per game hour that a citizen of this age dies of old age.
static func old_age_death_per_hour(age:float) -> float:
    var per_year:float = curve(OLD_AGE_DEATH_PER_YEAR, age);
    if per_year <= 0.0:
        return 0.0;
    return 1.0 - pow(1.0 - per_year, 1.0 / (ageing_days_per_year * GameClock.HOURS_PER_DAY));

const HEATING_BELOW      :float = 15.0;   # C: houses burn firewood below this
const FIREWOOD_PER_DAY_AT_0C:float = 2.0;   # burn rate at 0 C; scales linearly with how far below HEATING_BELOW it is
const TOOL_PRIORITY:Array[StringName] = [&"tool_steel", &"tool_iron", &"tool_wood"];   # best first, for equipping
const HARD_ORE_UNTOOLED_SPEED:float = 0.25;
const MINE_BATCH        :int = 4;       # units dug per task

static func is_food(item:StringName) -> bool:
    return ITEMS.has(item) and ITEMS[item].get("food", false);

static func is_tool(item:StringName) -> bool:
    return ITEMS.has(item) and ITEMS[item].has("tool");

static func item_name(item:StringName) -> String:
    return ITEMS[item]["name"] if ITEMS.has(item) else String(item);

static func cost_string(cost:Dictionary) -> String:
    if cost.is_empty():
        return "Free";
    var parts:PackedStringArray = [];
    for item in cost:
        parts.append("%d %s" % [cost[item], item_name(item)]);
    return ", ".join(parts);
