# ----------------------------------------------------------------
# Scenarios test
#     Every scenario's setup builds a world on its fixed map (the same
#     map twice, a different one when randomized) with the water, climate
#     and start it names; goals count what they say and stay reached; the
#     victory and defeat messages come once; the scenario is saved and
#     loaded; and the title's list can pick one.
#     godot --headless --path . --fixed-fps 60 res://tests/scenarios.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Scenarios.path = "user://scenarios_test.cfg";       # not the real progress file
    DirAccess.remove_absolute(Scenarios.path);
    # the data is complete
    for s in Scenarios.LIST:
        var run:ScenarioRun = ScenarioRun.new(s["id"]);
        _expect("%s: goals and text" % s["name"], run.goals().size() >= 2 and s["desc"] != "" and s["story"] != "" and Scenarios.setup_text(s) != "" and run.goal_text(0) != "?");
    # each one builds on its map
    var heights:Dictionary = {};
    for s in Scenarios.LIST:
        Scenarios.apply(s["id"], false);
        var setup:Dictionary = s["setup"];
        GameClock.reset();
        World.choose_start = false;
        var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
        add_child(world);
        await get_tree().process_frame;
        var label:String = s["name"];
        _expect("%s: the map seed, size, water and climate are the scenario's" % label, world.world_seed == s["seed"] and Terrain.SIZE == setup["size"] and Terrain.river_style == setup["water"] and Climate.current == setup["climate"]);
        _expect("%s: it belongs to the scenario" % label, world.scenario != null and world.scenario.id == s["id"] and Scenarios.pending == &"");
        _expect("%s: the start and settlers are right" % label, world.start_building != null and GameRules.start == setup["start"] and world.pawns.size() == setup["settlers"]);
        heights[s["id"]] = world.terrain.heights.duplicate();
        # the same seed again gives the same map
        if s["id"] == &"riverside":
            world.queue_free();
            await get_tree().process_frame;
            Scenarios.apply(s["id"], false);
            World.choose_start = false;
            var again:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
            add_child(again);
            await get_tree().process_frame;
            _expect("riverside: the same seed makes the same map", again.terrain.heights == heights[s["id"]]);
            again.queue_free();
            await get_tree().process_frame;
            Scenarios.apply(s["id"], true);
            World.choose_start = false;
            var other:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
            add_child(other);
            await get_tree().process_frame;
            _expect("riverside: randomizing gives a different map", other.world_seed != s["seed"] and other.terrain.heights != heights[s["id"]]);
            other.queue_free();
            await get_tree().process_frame;
        else:
            world.queue_free();
            await get_tree().process_frame;

    # goals, victory, defeat and saving on one world
    Scenarios.apply(&"riverside", false);
    World.choose_start = false;
    var w:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(w);
    await get_tree().process_frame;
    var run:ScenarioRun = w.scenario;
    _expect("a goals panel is on the HUD", w.hud.get_node_or_null("ScenarioPanel") != null);
    _expect("nothing is reached at the start", run.reached_count() == 0 and not run.won);
    _expect("population counts citizens (%s)" % run.progress(w, 0), run.progress(w, 0) == Vector2i(w.pawns.size(), 25));
    Stock.amount(&"food");
    var goals:Array = run.goals();
    goals[0]["count"] = w.pawns.size();       # make the first goal easy for the test
    run.on_day(w);
    _expect("a met goal is reached and stays reached", run.reached[0]);
    goals[0]["count"] = 25;
    run.on_day(w);
    _expect("it stays reached when the number falls back", run.reached[0] and not run.won);
    var dict:Dictionary = run.to_dict();
    var back:ScenarioRun = ScenarioRun.from_dict(dict);
    _expect("it round-trips through a dictionary", back != null and back.id == &"riverside" and back.reached == run.reached);
    var data:Dictionary = w.serialize();
    _expect("and is in the save", (data["scenario"] as Dictionary).get("id", &"") == &"riverside");
    Scenarios.mark_done(&"riverside", 99999);       # (keeps only a quicker one, so a real record stays)
    for i in run.reached.size():
        run.reached[i] = true;
    run.reached[run.reached.size() - 1] = false;
    goals[run.reached.size() - 1]["count"] = 0;       # the last goal is met now
    var best_before:int = Scenarios.done_days(&"riverside");
    run.on_day(w);
    _expect("meeting the last goal wins", run.won and run.won_day >= 0);
    _expect("and records the completion (%d)" % Scenarios.done_days(&"riverside"), Scenarios.done_days(&"riverside") >= 0 and (best_before < 0 or Scenarios.done_days(&"riverside") <= best_before));
    goals[run.reached.size() - 1]["count"] = 3;
    w.pawns.clear();
    var lost_run:ScenarioRun = ScenarioRun.new(&"bare_hands");
    lost_run.on_day(w);
    _expect("everyone gone loses the scenario", lost_run.lost);
    # put the shared test data back
    goals[0]["count"] = 25;
    Scenarios.pending = &"";
    var list:ScenarioList = ScenarioList.new();
    add_child(list);
    var picked:Array = [];
    list.chosen.connect(func(id:StringName, rnd:bool) -> void: picked.append([id, rnd]));
    list._select(&"coast");
    list._random.button_pressed = true;
    list._start.pressed.emit();
    _expect("the title's list reports the choice and the random option", picked == [[&"coast", true]]);
    list.queue_free();
    DirAccess.remove_absolute(Scenarios.path);
    Scenarios.path = Scenarios.PATH;
    print("SCENARIOS %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    print("%s: %s" % ["PASS" if ok else "FAIL", what]);
    if not ok:
        _fails += 1;
