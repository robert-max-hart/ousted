# ----------------------------------------------------------------
# Pests
#     An outbreak starts in a growing plot, spreads, slows growth and
#     cuts the harvest; farmers pick pests off; frost clears them; a
#     scarecrow makes all of it rarer. Saved with the game.
#     godot --headless --path . --fixed-fps 60 res://tests/pests.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;
var world:World;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    Weather.drought_enabled = false;
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    world.seeds.unlock_all();
    Weather._day_offset = 0.0;
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON * 1 + 2) * GameClock.HOURS_PER_DAY + 12.0;      # early summer
    Weather._update_temperature();
    var o:Vector2i = world.town_hall.origin + Vector2i(8, -10);
    for rn in world.nodes.duplicate():
        if Rect2i(o - Vector2i(3, 3), Vector2i(30, 14)).has_point(rn.cell):
            world.remove_node(rn);
    world.terrain.flatten_rect(Rect2i(o - Vector2i(2, 2), Vector2i(32, 16)));
    var f:Field = world.place_building(&"field", o, Vector2i(6, 6), true) as Field;
    _plant_all(f);
    # spreading and damage: seed one plot and run days
    f.pests[14] = 0.1;
    var before:float = f._growth_rate(Defs.CROPS[f.crop_id], 20.0, 1.0);
    for day in 6:
        f._pests_day();
    var infested:int = f.infested_count();
    _expect("pests spread and worsen (%d plots after 6 days)" % infested, infested > 1 and f.pests[14] > 0.5);
    f.growth.fill(0.0);
    f.moisture.fill(1.0);
    f.pests.fill(0.0);
    f.pests[0] = 1.0 - 0.0001;
    f.pests[1] = 0.0;
    f._pests_day();
    _expect("a plot worn right down is eaten", f.plot_state[0] == Field.Plot.DEAD);
    # growth and yield penalties
    _plant_all(f);
    f.growth.fill(0.0);
    f.pests.fill(0.0);
    f.pests[3] = 1.0;
    Weather._update_temperature();
    f.on_hour();
    _expect("an infested plot grows more slowly (%.5f vs %.5f)" % [f.growth[3], f.growth[4]], f.growth[3] < f.growth[4] * 0.6);
    # treatment
    f.pests.fill(0.0);
    f.pests[14] = 0.5;
    f.pests[15] = 0.5;
    var work:Dictionary = f.find_work(o, &"", Callable(), false);
    _expect("farmers pick pests off an infested plot first (%s)" % work.get("action", ""), work.get("action", &"") == &"treat");
    f.apply(14, &"treat", world.pawns[0]);
    _expect("treating clears the plot and its neighbours", f.pests[14] == 0.0 and f.pests[15] == 0.0);
    # frost clears them
    f.pests[20] = 0.6;
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON * 3 + 4) * GameClock.HOURS_PER_DAY;      # winter
    f._pests_day();
    _expect("a hard cold clears pests", f.infested_count() == 0 and f.pests[20] == 0.0);
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON * 1 + 2) * GameClock.HOURS_PER_DAY + 12.0;
    # outbreaks: count them over many days, with and without a scarecrow
    var plain:int = _outbreaks(f, 600);
    f.upgrades_done[&"scarecrow"] = true;
    var guarded:int = _outbreaks(f, 600);
    _expect("outbreaks happen (%d in 600 days)" % plain, plain > 5);
    _expect("a scarecrow cuts them a lot (%d vs %d)" % [guarded, plain], guarded * 2 < plain);
    f.upgrades_done.erase(&"scarecrow");
    # the same crop in a nearby field makes an outbreak likelier
    var g:Field = world.place_building(&"field", o + Vector2i(10, 0), Vector2i(6, 6), true) as Field;
    g.set_crop(&"beans");
    var alone:int = _outbreaks(f, 600);
    g.set_crop(f.crop_id);
    var crowded:int = _outbreaks(f, 600);
    _expect("the same crop next door raises the chance (%d vs %d)" % [crowded, alone], crowded > alone);
    # save and load
    f.pests[7] = 0.4;
    var d:Dictionary = f.to_dict();
    d["pests"] = d["pests"].duplicate();       # packed arrays are shared, not copied
    f.pests[7] = 0.0;
    f.restore_dict(d);
    _expect("pests are saved (%s)" % [f.pests[7]], is_equal_approx(f.pests[7], 0.4));
    # a farmer picks them off on their own
    _field = f;
    _plant_all(f);
    f.pests.fill(0.0);
    f.pests[14] = 0.6;
    f.near_water.fill(1);
    var farmer:Pawn = world.pawns[0];
    farmer.profession = JobManager.Profession.FARMER;
    world.jobs.change_profession(JobManager.Profession.FARMER, 1);
    GameClock.set_speed(3);
    Engine.time_scale = 4.0;
    _start = GameClock.total_hours;
    _phase = 1;

var _phase:int = 0;
var _field:Field;
var _start:float = 0.0;

func _process(_delta:float) -> void:
    if _phase != 1:
        return;
    for p in world.pawns:
        p.hunger = 1.0; p.thirst = 1.0; p.energy = 1.0; p.warmth = 1.0;
    _field.moisture.fill(1.0);
    if _field.pests[14] == 0.0 or GameClock.total_hours - _start > 12.0:
        _expect("a farmer picked the pests off (%.2f left)" % _field.pests[14], _field.pests[14] == 0.0);
        print("PESTS %s" % ("PASS" if _fails == 0 else "FAIL"));
        get_tree().quit(1 if _fails > 0 else 0);

func _plant_all(f:Field) -> void:
    for i in f.plot_count():
        f.plot_state[i] = Field.Plot.PLANTED;
        f.plot_crop[i] = f.crop_id;
        f.growth[i] = 0.0;
        f.moisture[i] = 1.0;

func _outbreaks(f:Field, days:int) -> int:
    var n:int = 0;
    for d in days:
        f.pests.fill(0.0);
        _plant_all(f);
        f._pests_day();
        for i in f.plot_count():
            if f.pests[i] > 0.0:
                n += 1;
                break;
    return n;

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
