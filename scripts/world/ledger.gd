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
var trades      :Array = [];       # oldest first: a {kind: "deal", day, when, merchant, sold, bought, in, out} per trade and a {kind: "visit", day, when, merchant, deals} per visit that ended
var trade_in_today :float = 0.0;   # trade value the merchants paid for our goods today
var trade_out_today:float = 0.0;   # trade value we paid for theirs
var trade_in_total :float = 0.0;
var trade_out_total:float = 0.0;
var deal_count :int = 0;
var visit_count:int = 0;

const MAX_TRADES:int = 300;

# A finished trade: what was sold and bought (item -> units, as the merchant's offer keys) and its values each way.
func record_deal(merchant:String, sold:Dictionary, bought:Dictionary, value_in:float, value_out:float) -> void:
    trades.append({"kind": "deal", "day": GameClock.day_index(), "when": "%s, %s" % [GameClock.date_string(), GameClock.time_string()], "merchant": merchant, "sold": sold.duplicate(), "bought": bought.duplicate(), "in": value_in, "out": value_out});
    trade_in_today += value_in;
    trade_out_today += value_out;
    trade_in_total += value_in;
    trade_out_total += value_out;
    deal_count += 1;
    _trim_trades();

# A merchant has left, after the given number of deals.
func record_visit(merchant:String, deals:int) -> void:
    trades.append({"kind": "visit", "day": GameClock.day_index(), "when": "%s, %s" % [GameClock.date_string(), GameClock.time_string()], "merchant": merchant, "deals": deals});
    visit_count += 1;
    _trim_trades();

func _trim_trades() -> void:
    if trades.size() > MAX_TRADES:
        trades.pop_front();

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
        "trade_in": trade_in_today, "trade_out": trade_out_today,
    });
    births_today = 0;
    deaths_today = 0;
    trade_in_today = 0.0;
    trade_out_today = 0.0;
    if samples.size() > MAX_SAMPLES:
        samples.pop_front();

func to_dict() -> Dictionary:
    return {"samples": samples.duplicate(true), "events": events.duplicate(true), "births": births_today, "deaths": deaths_today,
        "trades": trades.duplicate(true), "trade_in_today": trade_in_today, "trade_out_today": trade_out_today, "trade_in_total": trade_in_total, "trade_out_total": trade_out_total, "deals": deal_count, "visits": visit_count};

func restore(d:Dictionary) -> void:
    samples = d.get("samples", []);
    events = d.get("events", []);
    births_today = d.get("births", 0);
    deaths_today = d.get("deaths", 0);
    trades = d.get("trades", []);
    trade_in_today = d.get("trade_in_today", 0.0);
    trade_out_today = d.get("trade_out_today", 0.0);
    trade_in_total = d.get("trade_in_total", 0.0);
    trade_out_total = d.get("trade_out_total", 0.0);
    deal_count = d.get("deals", 0);
    visit_count = d.get("visits", 0);
