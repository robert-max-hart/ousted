# ----------------------------------------------------------------
# Crops test
#     Every crop is well formed and has a food item, sowing windows work
#     per crop, a multi-harvest crop regrows and then ends, a one-harvest
#     crop ends at once, and the new per-plot state is saved.
#     godot --headless --path . --fixed-fps 60 res://tests/crops.tscn
# ----------------------------------------------------------------
extends Node;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    world.seeds.unlock_all();       # this test is about the crops, not finding their seeds
    GameClock.set_speed(0);
    var ok:bool = true;
    for id in Defs.CROPS:
        var c:Dictionary = Defs.CROPS[id];
        for key in ["name", "item", "grow_days", "min_temp", "frost_temp", "sow", "yield", "fertility", "color", "desc"]:
            ok = ok and c.has(key);
        ok = ok and Defs.is_food(c["item"]) and c["frost_temp"] < c["min_temp"] and not (c["sow"] as Array).is_empty();
        if c.has("harvests"):
            ok = ok and c["regrow_days"] < c["grow_days"];
    _expect("all %d crops are well formed and give a food item" % Defs.CROPS.size(), ok and Defs.CROPS.size() >= 8);
    var th:Building = world.town_hall;
    var field:Field = world.place_building(&"field", th.origin + Vector2i(8, 8), Vector2i(3, 3), true) as Field;
    var pawn:Pawn = world.pawns[0];
    # sowing windows (the mean temperature follows the calendar: about 3 C an hour into spring, 11 C by mid spring, without the random daily swing)
    var can:Callable = func(id:StringName) -> bool:
        field.set_crop(id);
        return field.can_plant();
    Weather._day_offset = 0.0;        # the day's random swing would make the thresholds vary
    GameClock.total_hours = 1.0;
    _expect("first day of spring (about 3 C): radishes (1 C) and barley (2 C) can be sown", can.call(&"radish") and can.call(&"barley"));
    _expect("but wheat (4 C), potatoes (6 C) and pumpkins (10 C) can't", not can.call(&"wheat") and not can.call(&"potato") and not can.call(&"pumpkin"));
    GameClock.total_hours = 4.0 * GameClock.HOURS_PER_DAY;
    _expect("mid spring (about 11 C) every spring crop can, pumpkins included", can.call(&"wheat") and can.call(&"potato") and can.call(&"pumpkin"));
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON * 1 + 4) * GameClock.HOURS_PER_DAY + 12.0;      # mid summer
    _expect("summer: radishes and wheat can, barley (spring only) can't", can.call(&"radish") and can.call(&"wheat") and not can.call(&"barley"));
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON * 2 + 1) * GameClock.HOURS_PER_DAY;      # early autumn
    _expect("autumn: radishes can, wheat can't", can.call(&"radish") and not can.call(&"wheat"));
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON * 3 + 4) * GameClock.HOURS_PER_DAY;      # winter
    var any:bool = false;
    for id in Defs.CROPS:
        any = any or can.call(id);
    _expect("nothing is sown in winter", not any);
    # a one-harvest crop
    field.set_crop(&"wheat");
    field.plot_state[0] = Field.Plot.RIPE;
    field.plot_crop[0] = &"wheat";
    field.apply(0, &"harvest", pawn);
    _expect("wheat is fallow after its harvest", field.plot_state[0] == Field.Plot.FALLOW and pawn.carry_item == &"wheat");
    pawn.clear_carry();
    # a multi-harvest crop
    field.plot_crop[1] = &"lettuce";
    field.plot_state[1] = Field.Plot.RIPE;
    var cuts:int = 0;
    while field.plot_state[1] == Field.Plot.RIPE and cuts < 10:
        field.apply(1, &"harvest", pawn);
        cuts += 1;
        if cuts < 4:
            _expect("lettuce cut %d regrows" % cuts, field.plot_state[1] == Field.Plot.PLANTED and field.growth[1] > 0.3);
            field.plot_state[1] = Field.Plot.RIPE;
    _expect("lettuce ends after %d cuttings" % cuts, cuts == 4 and field.plot_state[1] == Field.Plot.FALLOW and field.cuts[1] == 0);
    # saved
    field.plot_crop[2] = &"lettuce";
    field.plot_state[2] = Field.Plot.PLANTED;
    field.cuts[2] = 2;
    var copy:Dictionary = field.to_dict();
    copy["cuts"] = copy["cuts"].duplicate();       # packed arrays are shared, not copied
    field.cuts[2] = 0;
    field.restore_dict(copy);
    _expect("the cutting count is saved", field.cuts[2] == 2);
    var old:Dictionary = copy.duplicate();
    old.erase("cuts");
    field.restore_dict(old);
    _expect("an old save without cuttings loads", field.cuts[2] == 0);
    get_tree().quit();

func _expect(what:String, ok:bool) -> void:
    print(("PASS " if ok else "FAIL ") + what);
