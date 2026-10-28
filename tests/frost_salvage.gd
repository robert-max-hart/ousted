# ----------------------------------------------------------------
# Frost salvage and early harvest test
#     A frost freezes growing crops instead of killing them at once:
#     they can be harvested for part of the yield for a day, then
#     they are lost. A field can also be told to harvest growing
#     plots early. Both give the share that has grown.
#     godot --headless --path . --fixed-fps 60 res://tests/frost_salvage.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    world.seeds.unlock_all();
    var f:Field = world.place_building(&"field", world.town_hall.origin + Vector2i(8, 8), Vector2i(3, 3), true) as Field;
    f.set_crop(&"pumpkin");
    var pawn:Pawn = world.pawns[0];
    var c:Dictionary = Defs.CROPS[&"pumpkin"];
    var ripe_amount:int = maxi(1, roundi(c["yield"] * lerpf(0.4, 1.3, f.fertility(0))));
    for i in 4:
        f.plot_state[i] = Field.Plot.PLANTED;
        f.plot_crop[i] = &"pumpkin";
    f.growth[0] = 0.6;
    f.growth[1] = 0.6;
    f.growth[2] = 0.1;       # too little grown to be worth saving
    f.growth[3] = 0.9;
    f.plot_state[4] = Field.Plot.RIPE;
    f.plot_crop[4] = &"pumpkin";

    # early harvest
    _expect("without the order a growing crop is not harvested", f.find_work(Vector2i.ZERO, &"harvest").get("index", -1) == 4);
    f.harvest_early = true;
    _expect("the order stops sowing", not f.can_plant());
    var fert0:float = lerpf(0.4, 1.3, f.fertility(0));
    pawn.clear_carry();
    f.apply(0, &"harvest", pawn);
    var early:int = pawn.carry_amount;
    _expect("early harvest of 60%% grown gives part of a crop (%d of %d)" % [early, ripe_amount], early >= 1 and early < ripe_amount and early == maxi(1, roundi(c["yield"] * fert0 * 0.6 * Field.EARLY_SHARE)));
    _expect("the plot is fallow again", f.plot_state[0] == Field.Plot.FALLOW);
    _expect("10%% grown is not worth taking", f.find_work(Vector2i(0, 0), &"harvest").get("index", -1) != 2);
    f.harvest_early = false;

    # frost
    Weather.temperature = c["frost_temp"] - 5.0;
    f.on_hour();
    _expect("frost freezes a crop that has grown a fair amount", f.plot_state[1] == Field.Plot.FROZEN and f.plot_state[3] == Field.Plot.FROZEN);
    _expect("a barely grown one just dies", f.plot_state[2] == Field.Plot.DEAD);
    _expect("growth is kept but halted", is_equal_approx(f.growth[1], 0.6));
    var work:Dictionary = f.find_work(Vector2i(20, 20), &"");
    _expect("frozen crops are harvested before the ripe one, however far away", work.get("action", &"") == &"harvest" and f.plot_state[work["index"]] == Field.Plot.FROZEN and work["rank"] < 0.0);
    var fert:float = lerpf(0.4, 1.3, f.fertility(1));       # before the harvest changes the soil
    pawn.clear_carry();
    f.apply(1, &"harvest", pawn);
    var salvaged:int = pawn.carry_amount;
    _expect("a frozen 60%% crop gives the frost share of its growth (%d)" % salvaged, salvaged == maxi(1, roundi(c["yield"] * fert * 0.6 * Field.FROZEN_SHARE)) and Field.FROZEN_SHARE <= Field.EARLY_SHARE);
    pawn.clear_carry();
    f.apply(3, &"harvest", pawn);
    _expect("a frozen 90%% crop gives most of a crop (%d of %d)" % [pawn.carry_amount, ripe_amount], pawn.carry_amount > salvaged);

    # the window closes
    f.plot_state[5] = Field.Plot.PLANTED;
    f.plot_crop[5] = &"pumpkin";
    f.growth[5] = 0.5;
    f.on_hour();
    for h in int(Field.SALVAGE_HOURS):
        f.on_hour();
    _expect("a frozen crop left for a day is lost", f.plot_state[5] == Field.Plot.DEAD);

    # saving
    f.plot_state[6] = Field.Plot.FROZEN;
    f.plot_crop[6] = &"pumpkin";
    f.frozen_hours[6] = 7.0;
    f.harvest_early = true;
    var copy:Dictionary = f.to_dict().duplicate(true);
    f.frozen_hours[6] = 0.0;
    f.harvest_early = false;
    f.restore_dict(copy);
    _expect("frozen time and the early order are saved", is_equal_approx(f.frozen_hours[6], 7.0) and f.harvest_early);
    f.plot_state[4] = Field.Plot.FALLOW;
    for i in f.plot_count():
        if f.plot_state[i] == Field.Plot.PLANTED:
            f.plot_state[i] = Field.Plot.FALLOW;
    f.on_hour();
    _expect("the order ends when nothing is left growing", not f.harvest_early);
    Weather.temperature = 10.0;
    print("FROST SALVAGE %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    print(("PASS " if ok else "FAIL ") + what);
    if not ok:
        _fails += 1;
