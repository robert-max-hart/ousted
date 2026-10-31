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
# a dry spell, by season. warning: an optional line shown in red under the description on the New Game screen. trees: woodland density against the temperate map. winter: the land goes bare and
# white in the last season (a hot climate keeps its summer look all year).
const DEFS:Dictionary = {
    Id.TEMPERATE: {
        "name": "Temperate", "desc": "Four distinct seasons: warm summers and hard winters, steady rain.",
        "temps": [11.0, 21.0, 9.0, -5.0], "swing": 4.0, "rain": [0.06, 0.03, 0.06, 0.05], "rain_stop": 0.12,
        "drought": [0.02, 0.05, 0.02, 0.0], "trees": 1.0, "winter": true,
    },
    Id.ARCTIC: {
        "name": "Arctic", "desc": "A short, cool summer and a long, brutal winter. Only hardy crops ripen. Heating is vital.",
        "temps": [2.0, 12.0, 1.0, -17.0], "swing": 3.0, "rain": [0.04, 0.04, 0.05, 0.06], "rain_stop": 0.12,
        "drought": [0.0, 0.01, 0.0, 0.0], "trees": 0.6, "winter": true,
        "warning": "Not yet tuned: this climate may be too difficult. In tests the first winter often starves the colony.",
    },
    Id.DESERT: {
        "name": "Desert", "desc": "Hot and dry with cool nights. Rain is rare and droughts are common: water is everything. Food spoils quickly.",
        "temps": [22.0, 34.0, 23.0, 14.0], "swing": 6.0, "rain": [0.012, 0.005, 0.012, 0.015], "rain_stop": 0.2,
        "drought": [0.05, 0.1, 0.05, 0.02], "trees": 0.2, "winter": false,
    },
    Id.TROPICAL: {
        "name": "Tropical", "desc": "Warm all year with frequent rain: no frost and no heating, so crops grow all year, but food spoils fast.",
        "temps": [26.0, 29.0, 27.0, 24.0], "swing": 3.0, "rain": [0.08, 0.1, 0.08, 0.05], "rain_stop": 0.13,
        "drought": [0.01, 0.01, 0.01, 0.01], "trees": 1.4, "winter": false,
    },
};

static var current:int = Id.TEMPERATE;

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
