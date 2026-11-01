# ----------------------------------------------------------------
# Climate
#     The map's climate, picked on the New Game screen and saved with
#     the game. It sets the temperature through the year, how often it
#     rains and how often drought strikes (Weather reads these), how
#     thick the woods are, and whether the land has a winter look.
#     Everything else (sowing, frost, heating, spoilage, drying) already
#     follows the temperature and the rain.
# ----------------------------------------------------------------
class_name Climate extends RefCounted;

enum Id { TEMPERATE, ARCTIC, DESERT, TROPICAL };      # (new ids go last: saves keep the numbers)

# temps: mid-season mean C for spring, summer, autumn and winter. swing: day and night spread (+-).
# rain: chance an hour starts a spell, by season; rain_stop: chance an hour ends one. drought: chance a day starts
# a dry spell, by season. storm: how likely a rain spell is a thunderstorm against the usual (Weather.STORM_CHANCE; missing is 1). heat, cold: the same for heat waves and cold snaps (Weather). wild: how much of each wild food grows here (a share of the temperate amount; missing or 0 is none): see World._spawn_nature and WildGrowth. ground, rock, sand: the colours of the land (four seasons for the ground; the default is green), tufts and tuft_colours: how many grass tufts
# stand on it (a share of the usual) and their colours by season, flowers: the share of the usual flowers. warning: an optional line shown in red under the description on the New Game screen. trees: woodland density against the temperate map. winter: the land goes bare and
# white in the last season (a hot climate keeps its summer look all year). species: the trees that grow here and their share, in the order
# they lie across the land's patches (so the ones next to each other in the list meet in a mixed edge); dead: the share of trees that are dead.
const DEFS:Dictionary = {
    Id.TEMPERATE: {
        "name": "Temperate", "desc": "Four distinct seasons: warm summers and hard winters, steady rain.",
        "temps": [11.0, 21.0, 9.0, -5.0], "swing": 4.0, "rain": [0.06, 0.03, 0.06, 0.05], "rain_stop": 0.12,
        "drought": [0.02, 0.05, 0.02, 0.0], "trees": 1.0, "winter": true, "storm": 1.0, "heat": 1.0, "cold": 1.0,
        "wild": {&"bush": 1.0, &"mushroom": 1.0, &"hazel": 1.0, &"herb": 1.0},
        "species": [[&"tree", 0.45], [&"birch", 0.17], [&"oak", 0.38]], "dead": 0.015,
    },
    Id.ARCTIC: {
        "name": "Arctic", "desc": "A short, cool summer and a long, brutal winter. Only hardy crops ripen. Heating is vital.",
        "temps": [2.0, 12.0, 1.0, -17.0], "swing": 3.0, "rain": [0.04, 0.04, 0.05, 0.06], "rain_stop": 0.12,
        "drought": [0.0, 0.01, 0.0, 0.0], "trees": 0.6, "winter": true, "storm": 0.3, "heat": 0.5, "cold": 1.0,
        "wild": {&"bush": 0.35, &"mushroom": 1.4, &"herb": 0.5, &"lingon": 1.0},
        "species": [[&"tree", 0.72], [&"birch", 0.28]], "dead": 0.07,
        "warning": "Not yet tuned: this climate may be too difficult. In tests the first winter often starves the colony.",
    },
    Id.DESERT: {
        "name": "Desert", "desc": "Hot and dry with cool nights. Rain is rare and droughts are common: water is everything. Food spoils quickly.",
        "temps": [22.0, 34.0, 23.0, 14.0], "swing": 6.0, "rain": [0.012, 0.005, 0.012, 0.015], "rain_stop": 0.2,
        "drought": [0.05, 0.1, 0.05, 0.02], "trees": 0.04, "winter": false, "storm": 0.4, "heat": 1.5, "cold": 0.3,
        "wild": {&"mushroom": 0.1, &"herb": 0.6, &"cactus": 1.0, &"date": 1.0},
        "species": [[&"palm", 1.0]], "dead": 0.5,
        "ground": [Color(0.66, 0.57, 0.4), Color(0.7, 0.6, 0.41), Color(0.67, 0.57, 0.4), Color(0.64, 0.56, 0.41)],
        "rock": Color(0.6, 0.48, 0.38), "sand": Color(0.76, 0.67, 0.48),
        "tufts": 0.3, "tuft_colours": [Color(0.66, 0.58, 0.32), Color(0.7, 0.6, 0.32), Color(0.68, 0.57, 0.32), Color(0.64, 0.57, 0.38)],
        "flowers": 0.12,
    },
    Id.TROPICAL: {
        "name": "Tropical", "desc": "Warm all year with frequent rain: no frost and no heating, so crops grow all year, but food spoils fast.",
        "temps": [26.0, 29.0, 27.0, 24.0], "swing": 3.0, "rain": [0.08, 0.1, 0.08, 0.05], "rain_stop": 0.13,
        "drought": [0.01, 0.01, 0.01, 0.01], "trees": 1.4, "winter": false, "storm": 2.0, "heat": 0.8, "cold": 0.0,
        "wild": {&"bush": 0.5, &"mushroom": 3.0, &"herb": 2.5, &"banana": 1.0, &"coconut": 1.0},
        "species": [[&"palm", 0.5], [&"oak", 0.5]], "dead": 0.0,
    },
};

# How hard pick_tree stretches the species noise (about 0.29 standard deviation) so each kind gets about its listed share of the ground.
const PATCH_SHARPNESS:float = 5.0;

static var current:int = Id.TEMPERATE;

# How much of a wild food grows on this map, against the temperate amount (0: none).
static func wild_share(kind:StringName) -> float:
    return float(data().get("wild", {}).get(kind, 0.0));

static func has_wild(kind:StringName) -> bool:
    return wild_share(kind) > 0.0;

static func data() -> Dictionary:
    return DEFS[current];

static func name_of(id:int) -> String:
    return DEFS[id]["name"];

static func temps() -> Array:
    return DEFS[current]["temps"];

# The season whose look the land wears: a climate without winter shows no snow, bare trees or dead grass.
static func look(season:int) -> int:
    if season == GameClock.Season.WINTER and not DEFS[current]["winter"]:
        return GameClock.Season.SPRING;
    return season;

# Plants rest and trees grow slowly now: the last season of a climate with a winter.
static func is_dormant() -> bool:
    return look(GameClock.season()) == GameClock.Season.WINTER;

# The kind of tree growing at a place: `patch` (-1 to 1, a slow noise over the map plus a little jitter) walks along the species list,
# so each kind grows in patches and neighbouring kinds mix at the edges; a share of the trees is dead (decided from the cell, so it
# costs no random numbers).
static func pick_tree(patch:float, cell:Vector2i) -> StringName:
    var d:Dictionary = DEFS[current];
    if float(d["dead"]) > 0.0 and float(posmod(hash(cell), 1000)) / 1000.0 < float(d["dead"]):
        return &"dead";
    var t:float = 1.0 / (1.0 + exp(-patch * PATCH_SHARPNESS));       # (the noise bunches up near zero, which would make the middle kinds far too common: this spreads it out evenly)
    var at:float = 0.0;
    var total:float = 0.0;
    for e in d["species"]:
        total += float(e[1]);
    for e in d["species"]:
        at += float(e[1]) / total;
        if t < at:
            return e[0];
    return d["species"][d["species"].size() - 1][0];

# The kind a woodcutter plants: a living tree of the climate, picked at random by share.
static func plant_kind(roll:float) -> StringName:
    var d:Dictionary = DEFS[current];
    var total:float = 0.0;
    for e in d["species"]:
        total += float(e[1]);
    var at:float = 0.0;
    for e in d["species"]:
        at += float(e[1]) / total;
        if roll < at:
            return e[0];
    return d["species"][d["species"].size() - 1][0];

# The grass tuft colour for a look (a season): the climate's own, or the usual green.
static func tuft_colour(look_season:int, default:Color) -> Color:
    var cols:Variant = DEFS[current].get("tuft_colours");
    return cols[look_season] if cols != null else default;
