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
static var droughts :bool = true;
static var realism  :bool = false;

static func reset() -> void:
    start = Start.HALL;
    settlers = 12;
    supplies = 2;
    merchants = 2;
    droughts = true;
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

static func seconds_per_hour() -> float:
    return REALISM_SECONDS_PER_HOUR if realism else SECONDS_PER_HOUR;

static func ageing_days() -> float:
    return REALISM_AGEING_DAYS if realism else AGEING_DAYS;

static func to_dict() -> Dictionary:
    return {"start": start, "settlers": settlers, "supplies": supplies, "merchants": merchants, "droughts": droughts, "realism": realism};

# A save without rules (made before this existed) gets the usual ones.
static func from_dict(d:Dictionary) -> void:
    start = clampi(int(d.get("start", Start.HALL)), 0, START_NAMES.size() - 1);
    settlers = clampi(int(d.get("settlers", 12)), SETTLERS[0], SETTLERS[SETTLERS.size() - 1]);
    supplies = clampi(int(d.get("supplies", 2)), 0, SUPPLY_SHARES.size() - 1);
    merchants = clampi(int(d.get("merchants", 2)), 0, MERCHANT_SHARES.size() - 1);
    droughts = bool(d.get("droughts", true));
    realism = bool(d.get("realism", false));
