# ----------------------------------------------------------------
# Scenarios
#     The list of scenarios: a named, preset game (map, climate, start,
#     rules) with goals to reach. Each has a fixed map seed so everyone
#     plays the same map; the title screen can randomize it instead.
#     Which ones were completed is kept in user://scenarios.cfg.
#
#     setup: size (a Terrain.MAP_SIZES entry), water (Terrain.RiverStyle), [hills] (Terrain.Hills, normal if missing), climate (Climate.Id), start
#     (GameRules.Start), difficulty (a Defs.DIFFICULTIES id), settlers, supplies and merchants (indices into the
#     GameRules lists), droughts. goals: {type, count, [id], [item]}, see ScenarioRun.
# ----------------------------------------------------------------
class_name Scenarios extends RefCounted;

const PATH:String = "user://scenarios.cfg";

static var path:String = PATH;             # tests point this at a file of their own, so they never touch real progress
static var pending:StringName = &"";        # the scenario the next new World belongs to (set when one is launched)

const LIST:Array[Dictionary] = [
    {
        "id": &"riverside", "name": "Riverside Beginnings", "seed": 4417,
        "desc": "A mild land with a winding river: good soil, wood and fish. The gentle one, a place to learn the game for real.",
        "story": "The settlers have come down to the river. Plant before the summer is out, and have food and firewood stored before the first frost.",
        "setup": {"size": 128, "water": Terrain.RiverStyle.WINDING, "climate": Climate.Id.TEMPERATE, "start": GameRules.Start.HALL,
                  "difficulty": &"normal", "settlers": 12, "supplies": 2, "merchants": 2, "droughts": true},
        "goals": [
            {"type": &"population", "count": 25},
            {"type": &"years", "count": 3},
            {"type": &"stock", "item": &"food", "count": 200},
        ],
    },
    {
        "id": &"dry_season", "name": "Dry Season", "seed": 2209,
        "desc": "Desert heat, little rain and droughts every year. One river is the colony's lifeline: dig wells and channels, and keep the fields wet.",
        "story": "The land is hard and the sun is hot. Water is everything here: find it, bring it to your fields, and do not let the wells run dry.",
        "setup": {"size": 128, "water": Terrain.RiverStyle.GENTLE, "climate": Climate.Id.DESERT, "start": GameRules.Start.HALL,
                  "difficulty": &"normal", "settlers": 12, "supplies": 1, "merchants": 2, "droughts": true},
        "goals": [
            {"type": &"population", "count": 15},
            {"type": &"years", "count": 2},
            {"type": &"building", "id": &"well", "count": 3},
        ],
    },
    {
        "id": &"wetlands", "name": "The Wetlands", "seed": 8123,
        "desc": "Most of the map is shallow water with islands of dry land. You start with only a well. Wade, bridge the deep channels and fish.",
        "story": "There is more water than land here. Settle on the dry rise, learn to cross the shallows, and feed the colony from the water.",
        "setup": {"size": 128, "water": Terrain.RiverStyle.WETLANDS, "climate": Climate.Id.TEMPERATE, "start": GameRules.Start.WELL,
                  "difficulty": &"normal", "settlers": 12, "supplies": 2, "merchants": 2, "droughts": false},
        "goals": [
            {"type": &"population", "count": 20},
            {"type": &"building", "id": &"bridge", "count": 2},
            {"type": &"stock", "item": &"fish", "count": 30},
        ],
    },
    {
        "id": &"coast", "name": "The Coast", "seed": 6061,
        "desc": "An ocean along one side of the map. Fish from piers, and trade with the merchants who walk in along the shore.",
        "story": "The sea is at your back. Build piers and a Trading Post: the colony's wealth will come from the water and from trade.",
        "setup": {"size": 128, "water": Terrain.RiverStyle.COAST, "climate": Climate.Id.TEMPERATE, "start": GameRules.Start.HALL,
                  "difficulty": &"normal", "settlers": 12, "supplies": 2, "merchants": 3, "droughts": true},
        "goals": [
            {"type": &"population", "count": 20},
            {"type": &"building", "id": &"fishing_hut", "count": 2},
            {"type": &"building", "id": &"trading_post", "count": 1},
            {"type": &"trade", "count": 3},
        ],
    },
    {
        "id": &"bare_hands", "name": "Bare Hands", "seed": 1337,
        "desc": "Nine settlers, half the usual supplies, no buildings, and a hard start. Survive the first year and raise a Town Hall.",
        "story": "You have a cart, a few tools and each other. Build shelter before the cold, and find food while the fields are still bare.",
        "setup": {"size": 96, "water": Terrain.RiverStyle.WINDING, "climate": Climate.Id.TEMPERATE, "start": GameRules.Start.NOTHING,
                  "difficulty": &"hard", "settlers": 9, "supplies": 0, "merchants": 1, "droughts": false},
        "goals": [
            {"type": &"years", "count": 1},
            {"type": &"building", "id": &"house", "count": 3},
            {"type": &"building", "id": &"town_hall", "count": 1},
        ],
    },
];

static func find(id:StringName) -> Dictionary:
    for s in LIST:
        if s["id"] == id:
            return s;
    return {};

# Sets every static the next new game reads, from the scenario's setup. `randomize` draws a new map instead of the
# fixed seed. The player always chooses where to settle.
static func apply(id:StringName, randomize:bool) -> void:
    var s:Dictionary = find(id);
    var setup:Dictionary = s["setup"];
    Defs.difficulty = setup["difficulty"];
    Terrain.set_size(setup["size"]);
    Terrain.river_style = setup["water"];
    Terrain.hills_level = setup.get("hills", Terrain.Hills.NORMAL);
    Climate.current = setup["climate"];
    GameRules.reset();
    GameRules.start = setup["start"];
    GameRules.settlers = setup["settlers"];
    GameRules.supplies = setup["supplies"];
    GameRules.merchants = setup["merchants"];
    GameRules.droughts = setup["droughts"];
    World.choose_start = true;
    World.new_game_seed = 0 if randomize else s["seed"];
    pending = id;

# One line naming the map: "Medium map, Wetlands, Temperate, starts with a Well".
static func setup_text(s:Dictionary) -> String:
    var setup:Dictionary = s["setup"];
    var size:int = Terrain.MAP_SIZES.find(setup["size"]);
    return "%s map, %s water, %s climate, starts with %s, %d settlers" % [
        Terrain.MAP_SIZE_NAMES[size], Terrain.RIVER_STYLES[setup["water"]]["name"].to_lower(), Climate.name_of(setup["climate"]).to_lower(),
        GameRules.START_NAMES[setup["start"]].to_lower().replace("nothing", "no buildings"), setup["settlers"]];

# --------------------------------
# Which ones have been completed (the day it took), kept between runs

static func done_days(id:StringName) -> int:
    var cfg:ConfigFile = ConfigFile.new();
    if cfg.load(path) != OK:
        return -1;
    return int(cfg.get_value("done", String(id), -1));

# Keeps the quickest completion.
static func mark_done(id:StringName, days:int) -> void:
    var cfg:ConfigFile = ConfigFile.new();
    cfg.load(path);
    var best:int = int(cfg.get_value("done", String(id), -1));
    if best < 0 or days < best:
        cfg.set_value("done", String(id), days);
        cfg.save(path);
