# ----------------------------------------------------------------
# GameRules
#     The rules picked on the New Game screen on top of the difficulty
#     preset: how many settlers, how big the starting stock, how often
#     merchants come, droughts on or off, and realism mode (slower days
#     and citizens that age at the pace of the calendar). Saved with the
#     game; readers ask here (GameClock, Weather, Traders, StartSite).
# ----------------------------------------------------------------
class_name GameRules extends RefCounted;

const SETTLERS        :Array[int]    = [6, 9, 12, 16, 20];
const SUPPLY_NAMES    :Array[String] = ["Scarce", "Lean", "Normal", "Generous", "Plentiful"];
const SUPPLY_SHARES   :Array[float]  = [0.5, 0.75, 1.0, 1.5, 2.0];
const MERCHANT_NAMES  :Array[String] = ["None", "Rare", "Normal", "Frequent"];
const MERCHANT_SHARES :Array[float]  = [0.0, 0.5, 1.0, 2.0];
const EVENT_NAMES     :Array[String] = ["None", "Rare", "Normal", "Frequent", "Extreme"];       # droughts and thunderstorms
const EVENT_SHARES    :Array[float]  = [0.0, 0.4, 1.0, 2.0, 4.0];
const RAIN_NAMES      :Array[String] = ["None", "Light", "Normal", "Heavy", "Torrential"];       # how often rain spells start
const RAIN_SHARES     :Array[float]  = [0.0, 0.4, 1.0, 1.7, 2.8];
const ILLNESS_NAMES   :Array[String] = ["None", "Rare", "Normal", "Frequent", "Plague"];
const ILLNESS_SHARES  :Array[float]  = [0.0, 0.4, 1.0, 2.2, 6.0];

# Realism mode: a game hour takes twice as long in real time, and a citizen year is a game year (32 days).
const SECONDS_PER_HOUR        :float = 7.5;
const REALISM_SECONDS_PER_HOUR:float = 15.0;
const AGEING_DAYS             :float = 4.0;
const REALISM_AGEING_DAYS     :float = 32.0;

# What the colony starts with besides the supply cart of goods: a Town Hall (storage and a well, as always), only a
# well, or nothing at all (the cart itself marks the spot).
enum Start { HALL, WELL, NOTHING };
const START_NAMES:Array[String] = ["Town Hall", "Well", "Nothing"];
const START_DESCS:Array[String] = [
    "The settlers arrive at a Town Hall: a well, and the first storage.",
    "Only a well. All the goods start in supply carts, and you build storage (and later a Town Hall) yourself.",
    "No buildings at all. All the goods start in supply carts; the settlers drink from open water until you dig a well.",
];

static var start    :int = Start.HALL;
static var settlers :int = 12;           # how many start (the last quarter of them children)
static var supplies :int = 2;            # index into SUPPLY_SHARES
static var merchants:int = 2;            # index into MERCHANT_SHARES
static var illness  :int = 2;            # index into ILLNESS_SHARES
static var droughts :int = 2;            # index into EVENT_SHARES: how often dry spells start
static var storms   :int = 2;            # ... and thunderstorms
static var heat     :int = 2;            # heat waves (indices into EVENT_SHARES)
static var cold     :int = 2;            # cold snaps
static var pests    :int = 2;            # crop pest outbreaks
static var rain     :int = 2;            # index into RAIN_SHARES
static var realism  :bool = false;

static func reset() -> void:
    start = Start.HALL;
    settlers = 12;
    supplies = 2;
    merchants = 2;
    illness = 2;
    droughts = 2;
    storms = 2;
    heat = 2;
    cold = 2;
    pests = 2;
    rain = 2;
    realism = false;

# The building the player places to choose the start: the Town Hall, the well, or the supply cart itself.
static func start_def() -> StringName:
    return [&"town_hall", &"well", &"cart"][start];

@warning_ignore("integer_division")
static func children() -> int:
    return settlers / 4;

static func supply_share() -> float:
    return SUPPLY_SHARES[supplies];

static func merchant_share() -> float:
    return MERCHANT_SHARES[merchants];

static func illness_share() -> float:
    return ILLNESS_SHARES[illness];

static func drought_share() -> float:
    return EVENT_SHARES[droughts];

static func storm_share() -> float:
    return EVENT_SHARES[storms];

static func heat_share() -> float:
    return EVENT_SHARES[heat];

static func cold_share() -> float:
    return EVENT_SHARES[cold];

static func pest_share() -> float:
    return EVENT_SHARES[pests];

static func rain_share() -> float:
    return RAIN_SHARES[rain];

static func seconds_per_hour() -> float:
    return REALISM_SECONDS_PER_HOUR if realism else SECONDS_PER_HOUR;

static func ageing_days() -> float:
    return REALISM_AGEING_DAYS if realism else AGEING_DAYS;

static func to_dict() -> Dictionary:
    return {"start": start, "settlers": settlers, "supplies": supplies, "merchants": merchants, "illness": illness, "droughts": droughts, "storms": storms, "heat": heat, "cold": cold, "pests": pests, "rain": rain, "realism": realism};

# A save without rules (made before this existed) gets the usual ones.
static func from_dict(d:Dictionary) -> void:
    start = clampi(int(d.get("start", Start.HALL)), 0, START_NAMES.size() - 1);
    settlers = clampi(int(d.get("settlers", 12)), SETTLERS[0], SETTLERS[SETTLERS.size() - 1]);
    supplies = clampi(int(d.get("supplies", 2)), 0, SUPPLY_SHARES.size() - 1);
    merchants = clampi(int(d.get("merchants", 2)), 0, MERCHANT_SHARES.size() - 1);
    illness = clampi(int(d.get("illness", 2)), 0, ILLNESS_SHARES.size() - 1);
    var dr:Variant = d.get("droughts", 2);       # (older saves hold on or off)
    droughts = clampi((2 if dr else 0) if dr is bool else int(dr), 0, EVENT_SHARES.size() - 1);
    storms = clampi(int(d.get("storms", 2)), 0, EVENT_SHARES.size() - 1);
    heat = clampi(int(d.get("heat", 2)), 0, EVENT_SHARES.size() - 1);
    cold = clampi(int(d.get("cold", 2)), 0, EVENT_SHARES.size() - 1);
    pests = clampi(int(d.get("pests", 2)), 0, EVENT_SHARES.size() - 1);
    rain = clampi(int(d.get("rain", 2)), 0, RAIN_SHARES.size() - 1);
    realism = bool(d.get("realism", false));
