# ----------------------------------------------------------------
# Seeds test
#     The difficulty decides the starting seeds, a field can only be
#     given a crop the colony has seeds for, foraging trips can find
#     the rest (in-season crops likelier), found seeds are kept and
#     saved, and a save from before seeds knows every crop.
#     godot --headless --path . --fixed-fps 60 res://tests/seeds.tscn
# ----------------------------------------------------------------
extends Node;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    for diff in [&"hard", &"normal", &"easy"]:
        Defs.difficulty = diff;
        var s:Seeds = Seeds.new();
        _expect("%s starts with %d crops" % [diff, Defs.DIFFICULTIES[diff]["seeds"].size()], s.known.size() == Defs.DIFFICULTIES[diff]["seeds"].size() and s.has(&"wheat"));
    Defs.difficulty = &"hard";
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    var th:Building = world.town_hall;
    var f:Field = world.place_building(&"field", th.origin + Vector2i(8, 8), Vector2i(4, 4), true) as Field;
    _expect("a field starts on a known crop", f.crop_id == &"wheat");
    _expect("a locked crop is refused", not f.set_crop(&"pumpkin") and f.crop_id == &"wheat");
    _expect("a known crop is accepted", f.set_crop(&"wheat"));
    _expect("the Town Hall lists the seeds", th.info_text().contains("Seeds: Wheat"));

    # the crop menu greys out what is locked
    world.tools.select(f);
    world.hud._on_info_button();
    var disabled:int = 0;
    for b in world.hud._crop_list.get_children():
        disabled += 1 if (b as Button).disabled else 0;
    _expect("the crop list disables %d locked crops" % disabled, disabled == Defs.CROPS.keys().filter(func(id:StringName) -> bool: return not Defs.CROPS[id].get("tree", false)).size() - 1);       # fields list field crops only

    # foraging finds
    var found:Array[StringName] = [];
    GameClock.total_hours = 0.0 * 24 + 12.0;       # spring
    for i in 400:
        var got:StringName = world.seeds.on_forage(world, 0.5);
        if got != &"":
            found.append(got);
    _expect("every locked crop was found eventually (%d)" % found.size(), found.size() == Defs.CROPS.size() - 1 and world.seeds.locked().is_empty());
    _expect("a found crop can be sown", f.set_crop(&"pumpkin"));
    _expect("nothing is left to find", world.seeds.on_forage(world, 1.0) == &"");

    # a crop that can be sown right now is likelier to be found than one that can't (mid summer: only radishes and lettuce can)
    var sowable_first:int = 0;
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON + 4) * GameClock.HOURS_PER_DAY + 12.0;
    Weather._day_offset = 0.0;
    for run in 300:
        var s2:Seeds = Seeds.new();       # hard: only wheat known
        var first:StringName = s2.on_forage(world, 1.0);
        sowable_first += 1 if Weather.can_sow(Defs.CROPS[first]) else 0;
    _expect("in mid summer the crops that can be sown are likelier (%d/300, 2 of 7 by share)" % sowable_first, sowable_first > 140);

    # saving
    var data:Dictionary = world.serialize();
    var s4:Seeds = Seeds.new();
    s4.restore(data["seeds"]);
    _expect("seeds are saved", s4.known.size() == world.seeds.known.size());
    var s5:Seeds = Seeds.new();
    s5.restore(null);
    _expect("an old save knows every crop", s5.locked().is_empty());
    var hard_world_seeds:Seeds = Seeds.new();
    hard_world_seeds.restore(["wheat", "beans"]);
    _expect("a partial list restores exactly", hard_world_seeds.known.size() == 2 and hard_world_seeds.has(&"beans") and not hard_world_seeds.has(&"radish"));
    Defs.difficulty = &"normal";
    get_tree().quit();

func _expect(what:String, ok:bool) -> void:
    print(("PASS " if ok else "FAIL ") + what);
