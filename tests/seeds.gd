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
    _expect("the crop list disables %d locked crops" % disabled, disabled == Defs.CROPS.size() - 1);

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

    # a spring-sowing crop is likelier to be found in spring than a crop sown only in summer/autumn
    var spring_first:int = 0;
    var autumn_first:int = 0;
    for run in 300:
        var s2:Seeds = Seeds.new();       # hard: only wheat known
        GameClock.total_hours = 0.0 * 24 + 12.0;
        var first_spring:StringName = s2.on_forage(world, 1.0);
        spring_first += 1 if (Defs.CROPS[first_spring]["sow"] as Array).has(0) else 0;
        var s3:Seeds = Seeds.new();
        GameClock.total_hours = 2.0 * 8.0 * 24 + 12.0;       # autumn
        var first_autumn:StringName = s3.on_forage(world, 1.0);
        autumn_first += 1 if (Defs.CROPS[first_autumn]["sow"] as Array).has(2) else 0;
    _expect("in spring spring crops dominate (%d/300)" % spring_first, spring_first > 180);
    _expect("in autumn the autumn crops are likelier than their share (%d/300)" % autumn_first, autumn_first > 150);

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
