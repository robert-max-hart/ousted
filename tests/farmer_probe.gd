# ----------------------------------------------------------------
# Farmer workload probe
#     One farmer alone on a single field of side N (best-case water),
#     for a number of days from the start of spring. Prints how fast
#     the field is sown, how long ripe plots wait, and how busy the
#     farmer is. Used to pick how many plots one farmer can cover.
#     godot --headless --path . --fixed-fps 60 res://tests/farmer_probe.tscn -- <side> <days> [crop]
# ----------------------------------------------------------------
extends Node;

var world:World;
var field:Field;
var farmer:Pawn;
var _days:int = 24;
var _last_day:int = -1;
var _prev:PackedByteArray;
var _sown:int = 0;
var _harvested:int = 0;
var _first_full_sow_day:float = -1.0;
var _ripe_hours:float = 0.0;           # plot-hours spent ripe and waiting
var _farm_frames:int = 0;
var _day_frames:int = 0;
var _last_hours:float = 0.0;
var _side:int = 6;
var _crop:StringName = &"wheat";

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    var args:PackedStringArray = OS.get_cmdline_user_args();
    _side = args[0].to_int();
    _days = args[1].to_int();
    if args.size() > 2:
        _crop = StringName(args[2]);
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    Weather._day_offset = 0.0;
    var th:Building = world.town_hall;
    var best:Vector2i = th.origin;
    var best_share:float = -1.0;
    var size:Vector2i = Vector2i(_side, _side);
    for dz in range(-30, 31, 2):
        for dx in range(-30, 31, 2):
            var o:Vector2i = th.origin + Vector2i(dx, dz);
            if world.can_place(&"field", o, size) == "" and world._rect_free_of_nodes(Rect2i(o, size)):
                var d:float = Vector2(dx, dz).length();
                var score:float = -d;
                if score > best_share:
                    best_share = score;
                    best = o;
    for rn in world.nodes.duplicate():
        if Rect2i(best - Vector2i(1, 1), size + Vector2i(2, 2)).has_point(rn.cell):
            world.remove_node(rn);
    field = world.place_building(&"field", best, size, true) as Field;
    field.set_crop(_crop);
    for i in field.plot_count():
        field.near_water[i] = 1;
        field.moisture[i] = 0.7;
    for p in world.pawns:
        p.profession = JobManager.Profession.LABORER;
    world.jobs.change_profession(JobManager.Profession.FARMER, 1);
    world.jobs.sync_targets();
    world.jobs.reconcile();
    for p in world.pawns:
        if p.profession == JobManager.Profession.FARMER:
            farmer = p;
    for item in [&"wheat", &"berries"]:
        th.store(item, 100);
    _prev = field.plot_state.duplicate();
    Engine.time_scale = 10.0;
    GameClock.set_speed(3);
    _last_hours = GameClock.total_hours;

func _process(_delta:float) -> void:
    if not World.alive(farmer):
        print("FARMER DIED");
        get_tree().quit();
        return;
    var now:float = GameClock.total_hours;
    var dh:float = now - _last_hours;
    _last_hours = now;
    var ripe:int = 0;
    var planted_or_better:int = 0;
    for i in field.plot_count():
        var st:int = field.plot_state[i];
        if st == Field.Plot.RIPE:
            ripe += 1;
        if st != Field.Plot.FALLOW:
            planted_or_better += 1;
        if _prev[i] == Field.Plot.FALLOW and st == Field.Plot.PLANTED:
            _sown += 1;
        if _prev[i] == Field.Plot.RIPE and st != Field.Plot.RIPE and st != Field.Plot.DEAD:
            _harvested += 1;
        _prev[i] = st;
    _ripe_hours += ripe * dh;
    if _first_full_sow_day < 0.0 and planted_or_better == field.plot_count():
        _first_full_sow_day = (now - GameClock.START_HOUR) / GameClock.HOURS_PER_DAY;
    if not GameClock.is_night():
        _day_frames += 1;
        if farmer.task != null and farmer.task.kind == &"farm":
            _farm_frames += 1;
    var d:int = GameClock.day_index();
    if d >= _days:
        var n:int = field.plot_count();
        print("RESULT crop=%s plots=%d days=%d sown=%d harvested=%d full_sow_day=%.1f ripe_wait_h_per_plot=%.1f busy=%.0f%%" % [
            _crop, n, _days, _sown, _harvested, _first_full_sow_day, _ripe_hours / n, 100.0 * _farm_frames / maxf(1.0, _day_frames)]);
        get_tree().quit();
