# ----------------------------------------------------------------
# Ledger
#     The colony's record, kept from the first day: one sample of the
#     numbers per day (for the graphs) and every message the event log
#     showed (the history). Viewing it needs the Town Hall's Governance
#     upgrade, recording does not. Owned by World.
# ----------------------------------------------------------------
class_name Ledger extends RefCounted;

const MAX_EVENTS:int = 500;        # the oldest are dropped past this
const MAX_SAMPLES:int = 1600;      # about 50 game years of days

var samples     :Array = [];       # per day: {day, pop, babies, children, adults, food, firewood, mood, births, deaths}
var events      :Array = [];       # oldest first: {day, when, text}
var births_today:int = 0;
var deaths_today:int = 0;

func record_event(text:String) -> void:
    events.append({"day": GameClock.day_index(), "when": "%s, %s" % [GameClock.date_string(), GameClock.time_string()], "text": text});
    if events.size() > MAX_EVENTS:
        events.pop_front();

# Takes the day's sample. mood is the average over citizens past babyhood, as a share.
func on_day(world:World) -> void:
    var babies:int = 0;
    var children:int = 0;
    var adults:int = 0;
    var mood:float = 0.0;
    for p in world.pawns:
        if p.is_baby():
            babies += 1;
            continue;
        if p.is_adult():
            adults += 1;
        else:
            children += 1;
        mood += p.mood;
    var grown:int = adults + children;
    samples.append({
        "day": GameClock.day_index(), "pop": world.pawns.size(), "babies": babies, "children": children, "adults": adults,
        "food": Stock.food_total(), "firewood": Stock.amount(&"firewood"),
        "mood": mood / grown * 100.0 if grown > 0 else 0.0, "births": births_today, "deaths": deaths_today,
    });
    births_today = 0;
    deaths_today = 0;
    if samples.size() > MAX_SAMPLES:
        samples.pop_front();

func to_dict() -> Dictionary:
    return {"samples": samples.duplicate(true), "events": events.duplicate(true), "births": births_today, "deaths": deaths_today};

func restore(d:Dictionary) -> void:
    samples = d.get("samples", []);
    events = d.get("events", []);
    births_today = d.get("births", 0);
    deaths_today = d.get("deaths", 0);
