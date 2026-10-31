# ----------------------------------------------------------------
# ScenarioRun
#     The scenario a game belongs to: checks its goals once a day,
#     remembers which ones were reached (they stay reached), tells the
#     player when all are, and when everyone is gone. Saved with the game.
#     Goal types: population (citizens alive), years (full years lived
#     through), stock (an item, or &"food" for all food, in storage),
#     building (finished ones of a def id), trade (deals with merchants).
# ----------------------------------------------------------------
class_name ScenarioRun extends RefCounted;

var id        :StringName;
var reached   :Array[bool] = [];
var won       :bool = false;
var lost      :bool = false;
var won_day   :int = -1;
var _goals    :Array = [];        # this game's own copy of the goals (the data is constant)

func _init(scenario_id:StringName = &"") -> void:
    id = scenario_id;
    if id != &"":
        _goals = data().get("goals", []).duplicate(true);
        reached.resize(_goals.size());
        reached.fill(false);

func data() -> Dictionary:
    return Scenarios.find(id);

func goals() -> Array:
    return _goals;

# --------------------------------
# Progress

# [current, target] of goal i, for the panel.
@warning_ignore("integer_division")
func progress(world:World, i:int) -> Vector2i:
    var g:Dictionary = goals()[i];
    var target:int = g["count"];
    match g["type"]:
        &"population":
            return Vector2i(world.pawns.size(), target);
        &"years":
            return Vector2i(GameClock.day_index() / GameClock.DAYS_PER_YEAR, target);
        &"stock":
            return Vector2i(Stock.food_total() if g["item"] == &"food" else Stock.amount(g["item"]), target);
        &"building":
            var n:int = 0;
            for b in world.buildings:
                if b.def_id == g["id"] and b.is_complete():
                    n += 1;
            return Vector2i(n, target);
        &"trade":
            var deals:int = 0;
            for t in world.ledger.trades:
                if t.get("kind", "") == "deal":
                    deals += 1;
            return Vector2i(deals, target);
    return Vector2i(0, target);

func goal_text(i:int) -> String:
    var g:Dictionary = goals()[i];
    var n:int = g["count"];
    match g["type"]:
        &"population":
            return "Reach %d citizens" % n;
        &"years":
            return "Survive %d year%s" % [n, "" if n == 1 else "s"];
        &"stock":
            return "Hold %d %s in storage" % [n, "food" if g["item"] == &"food" else Defs.item_name(g["item"]).to_lower()];
        &"building":
            return "Build %d x %s" % [n, Defs.BUILDINGS[g["id"]]["name"]];
        &"trade":
            return "Make %d trade%s with merchants" % [n, "" if n == 1 else "s"];
    return "?";

func reached_count() -> int:
    var n:int = 0;
    for r in reached:
        if r:
            n += 1;
    return n;

# --------------------------------
# Daily check

func on_day(world:World) -> void:
    if won or lost or id == &"":
        return;
    if world.pawns.is_empty() and not world.awaiting_start:
        lost = true;
        world.notify("Everyone is gone. The scenario \"%s\" is lost." % data()["name"]);
        return;
    var changed:bool = false;
    for i in goals().size():
        if reached[i]:
            continue;
        var p:Vector2i = progress(world, i);
        if p.x >= p.y:
            reached[i] = true;
            changed = true;
            world.notify("Goal reached: %s." % goal_text(i));
    if changed and reached_count() == reached.size():
        won = true;
        won_day = GameClock.day_index();
        Scenarios.mark_done(id, won_day);
        world.notify("Victory! You completed \"%s\" in %d days. You may keep playing." % [data()["name"], won_day]);
        if world.hud != null:
            world.hud.toast("Victory! Scenario complete.");

# --------------------------------
# Save and load

func to_dict() -> Dictionary:
    return {"id": id, "reached": reached, "won": won, "lost": lost, "won_day": won_day};

static func from_dict(d:Dictionary) -> ScenarioRun:
    var run:ScenarioRun = ScenarioRun.new(StringName(d.get("id", "")));
    if run.id == &"" or run.data().is_empty():
        return null;
    var saved:Array = d.get("reached", []);
    for i in mini(saved.size(), run.reached.size()):
        run.reached[i] = bool(saved[i]);
    run.won = bool(d.get("won", false));
    run.lost = bool(d.get("lost", false));
    run.won_day = int(d.get("won_day", -1));
    return run;
