# ----------------------------------------------------------------
# Ledger test
#     Daily samples and the event history are recorded from the start,
#     births and deaths are counted, the record is saved and loads back
#     (an old save loads with an empty one), and the history is capped.
#     godot --headless --path . --fixed-fps 60 res://tests/ledger.tscn
# ----------------------------------------------------------------
extends Node;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    var led:Ledger = world.ledger;
    _expect("a notification is kept as history", led.events.size() > 0 and "settlers have arrived" in led.events[0]["text"]);
    world.notify("A test event.");
    _expect("the newest event is last", led.events[led.events.size() - 1]["text"] == "A test event.");
    led.on_day(world);
    var s:Dictionary = led.samples[0];
    _expect("a sample counts the citizens", s["pop"] == world.pawns.size() and s["adults"] + s["children"] + s["babies"] == s["pop"] and s["babies"] == 0);
    _expect("it has food and firewood", s["food"] == Stock.food_total() and s["firewood"] == Stock.amount(&"firewood"));
    _expect("it has an average happiness", s["mood"] > 0.0 and s["mood"] <= 100.0);
    world.kill_pawn(world.pawns[0], "old age");
    var house:Building = world.place_building(&"house", world.town_hall.origin + Vector2i(-8, 2), Vector2i(3, 3), true);
    world.families.move_home(world.pawns[1], house);
    world.families._give_birth(world.pawns[1]);
    led.on_day(world);
    var t:Dictionary = led.samples[1];
    _expect("a death and a birth are counted for the day", t["deaths"] == 1 and t["births"] == 1);
    led.on_day(world);
    _expect("the counters start over each day", led.samples[2]["deaths"] == 0 and led.samples[2]["births"] == 0);
    var saved:Dictionary = world.serialize();
    var copy:Ledger = Ledger.new();
    copy.restore(saved["ledger"]);
    _expect("the ledger is saved and loads back", copy.samples == led.samples and copy.events == led.events);
    var old:Ledger = Ledger.new();
    old.restore({});
    _expect("an old save loads with an empty record", old.samples.is_empty() and old.events.is_empty());
    for i in Ledger.MAX_EVENTS + 20:
        led.record_event("filler %d" % i);
    _expect("the history is capped", led.events.size() == Ledger.MAX_EVENTS and led.events[led.events.size() - 1]["text"] == "filler %d" % (Ledger.MAX_EVENTS + 19));
    get_tree().quit();

func _expect(what:String, ok:bool) -> void:
    print(("PASS " if ok else "FAIL ") + what);
