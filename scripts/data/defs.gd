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
        "name": "Town Hall", "size": Vector2i(4, 4), "cost": {&"wood": 30, &"stone": 10}, "work": 20.0,
        "shape": "house", "height": 3.0, "color": Color(0.62, 0.48, 0.34), "roof": Color(0.42, 0.22, 0.16),
        "water": true, "unique": true, "heated_by": &"heating",
        "upgrades": {
            &"storage": {
                "name": "Storage", "cost": {&"wood": 20, &"stone": 5}, "work": 10.0, "capacity": 100,
                "desc": "A store room: the Town Hall holds 100 goods.",
            },
            &"storage2": {
                "name": "More storage", "cost": {&"wood": 40, &"stone": 15}, "work": 20.0, "capacity": 200, "requires": [&"storage"],
                "desc": "A bigger store room: 200 more goods (300 in all).",
            },
            &"heating": {
                "name": "Hearth", "cost": {&"wood": 10, &"stone": 15}, "work": 10.0,
                "desc": "A fire that costs nothing to keep. Anyone can warm up here, but nobody sleeps here.",
            },
            &"governance": {
                "name": "Governance", "cost": {&"wood": 30, &"stone": 10}, "work": 15.0,
                "desc": "Unlocks the Policies panel (and later the ledger and history).",
            },
        },
        "desc": "The heart of the colony: a well, and nothing else until it is upgraded. It shelters no one. There is only one, but a new one can be built if it is lost, and it can be moved.",
    },
    &"cart": {
        "name": "Supply Cart", "size": Vector2i(2, 1), "cost": {}, "work": 0.0,
        "shape": "cart", "height": 0.7, "color": Color(0.55, 0.4, 0.25),
        "storage": true, "capacity": 250, "temporary": true, "relocatable": false,
        "desc": "The settlers' starting goods. It takes nothing new and is gone once it is empty.",
    },
    &"house": {
        "name": "Wooden House", "size": Vector2i(3, 3), "cost": {&"wood": 16, &"stone": 4}, "work": 24.0,
        "shape": "house", "height": 2.2, "color": Color(0.6, 0.45, 0.3), "roof": Color(0.5, 0.3, 0.18),
        "beds": 6, "fuel_capacity": 40,
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
    &"shack": {
        "name": "Shack", "size": Vector2i(2, 2), "cost": {&"wood": 3}, "work": 3.0,
        "shape": "house", "height": 1.3, "color": Color(0.5, 0.42, 0.32), "roof": Color(0.36, 0.3, 0.22),
        "beds": 1, "shack": true, "no_refund": true, "relocatable": false,
        "desc": "A bare shelter for one, put up by the homeless. It keeps a little warmth in, counts as being homeless for happiness, and demolishing it returns nothing.",
    },
    &"field": {
        "name": "Crop Field", "size": Vector2i(6, 6), "cost": {}, "work": 6.0,
        "shape": "field", "height": 0.0, "color": Color(0.4, 0.28, 0.18),
        "field": true, "drag_size": true, "walkable": true, "relocatable": false,
        "desc": "Farmers plant, tend and harvest crops here. Choose the crop in the inspector.",
    },
    &"graveyard": {
        "name": "Graveyard", "size": Vector2i(4, 3), "cost": {}, "work": 6.0,
        "shape": "graveyard", "height": 0.06, "color": Color(0.36, 0.42, 0.3),
        "graveyard": true, "drag_size": true, "walkable": true, "relocatable": false,
        "desc": "One grave per square. Citizens bury the dead here, which softens the grief. A grave frees its square after 10 years.",
    },
};

const BUILD_MENU:Array[StringName] = [&"town_hall", &"house", &"well", &"stockpile", &"granary", &"woodcutter", &"mine", &"blacksmith", &"school", &"field", &"graveyard"];

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

# Families (decided 2026-10-25): adults within PAIR_MAX_AGE_GAP years pair up automatically, with no sex tracked. A
# pair has a baby only while it lives in a house with a free slot. The chances are per calendar day; the exact
# numbers are my picks to tune. Babies need half the food and water of anyone else, supplied by a carer.
const PAIR_MAX_AGE_GAP  :float = 10.0;
const PAIR_CHANCE_PER_DAY:float = 0.3;
const WIDOW_WAIT_DAYS   :float = 4.0;     # before a widowed citizen can pair again
const FERTILE_FROM      :float = 18.0;
const FERTILE_TO        :float = 40.0;
const BIRTH_CHANCE_PER_DAY:float = 0.12;  # at full food and a warm house
const PREGNANCY_DAYS    :float = 3.0;
const POSTPARTUM_DAYS   :float = 8.0;     # before the pair can conceive again
const BABY_NEED_MULT    :float = 0.5;     # hunger and thirst fall this much as fast for a baby
const BABY_CARE_BELOW   :float = 0.7;     # a carer comes once a baby's hunger or thirst is under this
const FOOD_PER_PAWN_PLENTY:float = 30.0;  # food per citizen at which births are at full chance
const STARVING_BIRTH_MULT:float = 0.2;    # chance multiplier with no food, and with a cold house

# Difficulty (decided 2026-10-25; the setting itself comes with the menus in M8, so a new game uses `difficulty`):
# which Town Hall upgrades a colony starts with. Starting goods go into the Town Hall's store room first and the
# rest into a supply cart that disappears when empty.
const DIFFICULTIES:Dictionary = {
    &"hard": {"name": "Hard", "town_hall": []},
    &"normal": {"name": "Normal", "town_hall": [&"storage"]},
    &"easy": {"name": "Easy", "town_hall": [&"storage", &"storage2", &"heating"]},
};
static var difficulty:StringName = &"normal";

# Relocating a building (any one that can move) costs this share of its build cost and work; the old one goes with no refund.
const RELOCATE_COST_MULT:float = 0.5;

# Happiness, grief and burial (decided 2026-10-25). Happiness is a stored value that moves toward a target made of
# named factors (Pawn.happiness_factors); the numbers are my picks to tune.
const MOOD_BASE         :float = 0.65;
const MOOD_HOURS        :float = 12.0;    # how quickly happiness follows its target (a time constant)
const MOOD_SLOW_BELOW   :float = 0.4;     # under this, work gets slower, down to MOOD_SLOW_MIN at zero
const MOOD_SLOW_MIN     :float = 0.85;
const LEAVE_BELOW       :float = 0.15;    # this unhappy for LEAVE_AFTER_DAYS in a row and a citizen leaves
const LEAVE_RECOVER     :float = 0.25;    # the count starts over once happiness is back over this
const LEAVE_AFTER_DAYS  :float = 5.0;
const CHILD_LABOR_MOOD_CHILD:float = 0.25;   # penalty for a child at full child labor, and for an adult
const CHILD_LABOR_MOOD_ADULT:float = 0.1;
const BIRTH_MOOD_RANGE  :Vector2 = Vector2(0.6, 1.2);   # birth chance multiplier from unhappy to happy parents
# [amount, days it fades over] for the partner, a parent or child, a sibling, and everyone else
const GRIEF_PARTNER     :Vector2 = Vector2(0.4, 12.0);
const GRIEF_FAMILY      :Vector2 = Vector2(0.3, 12.0);
const GRIEF_SIBLING     :Vector2 = Vector2(0.1, 6.0);
const GRIEF_COLONY      :Vector2 = Vector2(0.04, 3.0);
const GRIEF_LEFT_MULT   :float = 0.5;     # someone leaving hurts half as much as a death
const GRAVE_SOFTEN      :float = 0.5;     # grief left once the body is buried
const BODY_FAMILY_FIRST_HOURS:float = 6.0; # only kin may carry a body in this time
const BODY_LINGER_DAYS  :float = 6.0;     # an unburied body vanishes after this
const GRAVE_DECAY_YEARS :float = 10.0;    # calendar years before a grave frees its square

# Homelessness (decided 2026-10-25): no bed means sleeping outside; a shack is a poor bed.
const SHACK_AFTER_HOURS :float = 6.0;     # homeless this long before a shack is put up
const OUTDOOR_SLEEP_MULT:float = 0.5;     # energy recovered sleeping outside, against in a bed
const SHACK_WARMTH_RATE :float = 0.06;    # warmth per hour gained in a shack (a heated house gives 0.25)
const SHACK_COLD_DRAIN  :float = 0.004;   # per hour per degree under 8 C, in a shack (outside it is 0.006)
const HOMELESS_MOOD     :Vector2 = Vector2(0.15, 0.30);   # penalty at once, and after HOMELESS_MOOD_DAYS
const HOMELESS_MOOD_DAYS:float = 10.0;
const SHACK_MOOD        :float = 0.1;
const COLD_SLEEP_MOOD   :float = 0.1;

# Schooling (decided 2026-10-23): children study 8:00 to 16:00 with a teacher present. School builds general
# experience, which speeds up all work. Gains get harder as the value rises: a child at school for every school
# hour from 5 to 17 ends up about 23% faster.
const SCHOOL_START      :float = 8.0;
const SCHOOL_END        :float = 16.0;
const GENERAL_XP_RATE   :float = 0.0012;  # experience (as a work speed bonus) per school hour at zero
const GENERAL_XP_HALF   :float = 0.1;     # the rate halves when experience reaches this

static func general_xp_gain(xp:float, hours:float) -> float:
    return GENERAL_XP_RATE * hours / (1.0 + xp / GENERAL_XP_HALF);

# Job experience (decided 2026-10-23): per citizen per job, never decays, earned at any age, speeds up that job
# only. Same curve shape and starting constants as general experience (a starting point to tune).
const JOB_XP_RATE       :float = 0.0012;  # experience (as a work speed bonus) per work hour at zero
const JOB_XP_HALF       :float = 0.1;     # the rate halves when experience reaches this

static func job_xp_gain(xp:float, hours:float) -> float:
    return JOB_XP_RATE * hours / (1.0 + xp / JOB_XP_HALF);

# Teacher quality (decided 2026-10-25): the teacher's teaching experience plus their own general experience
# multiplies how fast pupils gain general experience, up to 1.5x for a veteran.
const TEACHER_MAX_BONUS :float = 0.5;
const TEACHER_VETERAN_XP:float = 0.4;     # teaching + general experience at which the bonus is full

static func teacher_multiplier(teaching_xp:float, general_xp:float) -> float:
    return 1.0 + TEACHER_MAX_BONUS * minf(1.0, (teaching_xp + general_xp) / TEACHER_VETERAN_XP);

# --------------------------------
# Policies (decided 2026-10-23): colony-wide on/off rules the player sets in the HUD, saved with the game.
# Each is id -> {name, desc, default}. Add a rule here, then read it with World.instance.policies.is_on(id).
const POLICIES:Dictionary = {
    &"build_shacks": {
        "name": "Homeless build shacks", "default": true,
        "desc": "A citizen with no home for a few hours gets a shack (3 wood, lost if demolished). Off, they sleep outside until a house has room.",
    },
    &"child_labor": {
        "name": "Child labor", "default": true,
        "desc": "Children (5 to 17) with no school to attend work as laborers at half speed. Forbidden, they stay home instead.",
    },
};

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
