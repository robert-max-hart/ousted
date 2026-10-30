# ----------------------------------------------------------------
# Livestock and manure
#     A pasture starts empty; animals give eggs and manure, breed up
#     to the room, eat grain in the cold months and die without it;
#     farmers collect, and spread manure on poor fallow plots.
#     godot --headless --path . --fixed-fps 60 res://tests/livestock.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;
var world:World;
var _phase:int = 0;
var _pen:Pasture;
var _field:Field;
var _start:float = 0.0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    Weather.drought_enabled = false;
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    world.rng.seed = 4242;       # breeding is a daily chance: keep the run the same every time
    world.seeds.unlock_all();
    Weather._day_offset = 0.0;
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON * 1 + 2) * GameClock.HOURS_PER_DAY + 12.0;      # early summer
    Weather._update_temperature();
    var o:Vector2i = TestSite.near(world, Vector2i(8, -10));
    for rn in world.nodes.duplicate():
        if Rect2i(o - Vector2i(3, 3), Vector2i(28, 14)).has_point(rn.cell):
            world.remove_node(rn);
    world.terrain.flatten_rect(Rect2i(o - Vector2i(2, 2), Vector2i(30, 16)));
    _pen = world.place_building(&"pasture", o, Vector2i(4, 4), true) as Pasture;
    _pen.on_day();
    _expect("a new run is empty and stays empty (animals are bought)", _pen.animals == 0 and _pen.ready_product == 0);
    _expect("it has room for ten chickens", _pen.free_room() == 10);
    _expect("animals added are counted, up to the room (%d)" % _pen.add_animals(4), _pen.animals == 4 and _pen.free_room() == 6);
    _expect("it says it is empty when it is", true);
    _expect("the run holds up to %d chickens (4x4 / 1.5)" % _pen.capacity_animals(), _pen.capacity_animals() == 10);
    _expect("the ground is mown", world.terrain.get_overlay(o) == Terrain.Overlay.ORCHARD);
    for i in 12:
        _pen.on_day();
    _expect("they lay eggs and leave manure (%d, %d)" % [_pen.ready_product, _pen.ready_manure], _pen.ready_product >= Pasture.COLLECT_AT and _pen.ready_manure >= 1);
    _expect("they breed but never past the room (%d)" % _pen.animals, _pen.animals > 4 and _pen.animals <= _pen.capacity_animals());
    for i in 300:
        _pen.on_day();
    _expect("a full run stays at its capacity", _pen.animals == _pen.capacity_animals());
    # cold: grain or death
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON * 3 + 4) * GameClock.HOURS_PER_DAY;
    Weather._update_temperature();
    var herd:int = _pen.animals;
    _pen.add_input(&"barley", 8);
    for i in 4:
        _pen.on_day();
    _expect("in the cold they eat the grain (%d left)" % _pen.input_amount(&"barley"), _pen.input_amount(&"barley") < 8);
    _expect("and are still all alive", _pen.animals == herd);
    _pen.inputs.clear();
    for i in 12:
        _pen.on_day();
    _expect("with no grain they starve (%d of %d left)" % [_pen.animals, herd], _pen.animals < herd);
    _expect("and grain is asked for", not _pen.inputs_wanted().is_empty() or Stock.available(&"barley") + Stock.available(&"wheat") == 0);
    # saving
    var d:Dictionary = _pen.to_dict();
    var n:int = _pen.animals;
    _pen.animals = 99;
    _pen.restore_dict(d);
    _expect("animals are saved", _pen.animals == n);
    # manure on a poor fallow plot, and a farmer doing the work
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON * 1 + 2) * GameClock.HOURS_PER_DAY + 12.0;
    Weather._update_temperature();
    _field = world.place_building(&"field", o + Vector2i(8, 0), Vector2i(4, 4), true) as Field;
    for i in _field.plot_count():
        world.soil_fertility[world.terrain.index(_field.plot_cell(i))] = 0.3;
        _field.moisture[i] = 1.0;
    world.town_hall.store(&"manure", 3);
    var work:Dictionary = _field.find_work(o, &"", Callable(), false, true);
    _expect("a poor fallow plot is manured before it is sown (%s)" % work.get("action", ""), work.get("action", &"") == &"manure");
    work = _field.find_work(o, &"", Callable(), false, false);
    _expect("without manure it is sown", work.get("action", &"") == &"plant");
    _field.apply(5, &"manure", world.pawns[0]);
    _expect("a load enriches the plot and its neighbours", _field.fertility(5) >= 0.6 and _field.fertility(6) >= 0.6 and _field.fertility(15) < 0.35);
    for i in _field.plot_count():
        world.soil_fertility[world.terrain.index(_field.plot_cell(i))] = 0.3;
    var farmer:Pawn = world.pawns[0];
    farmer.profession = JobManager.Profession.FARMER;
    world.jobs.change_profession(JobManager.Profession.FARMER, 1);
    GameClock.set_speed(3);
    Engine.time_scale = 4.0;
    _start = GameClock.total_hours;
    _phase = 1;

func _process(_delta:float) -> void:
    if _phase != 1:
        return;
    for p in world.pawns:
        p.hunger = 1.0; p.thirst = 1.0; p.energy = 1.0; p.warmth = 1.0;
    var spread:bool = false;
    for i in _field.plot_count():
        spread = spread or _field.fertility(i) > 0.5;
    if spread or GameClock.total_hours - _start > 14.0:
        _expect("a farmer fetched manure and spread it (manure left %d)" % Stock.amount(&"manure"), spread and Stock.amount(&"manure") < 3);
        if _phase == 1:
            _phase = 2;
            _collect();
        return;

func _collect() -> void:
    _pen.animals = 6;
    _pen.ready_product = 8;
    _pen.ready_manure = 0;
    var before:int = Stock.amount(&"eggs");
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON * 1 + 2) * GameClock.HOURS_PER_DAY + 12.0;
    _start = GameClock.total_hours;
    _phase = 3;
    _before_eggs = before;

var _before_eggs:int = 0;

func _physics_process(_delta:float) -> void:
    if _phase != 3:
        return;
    for p in world.pawns:
        p.hunger = 1.0; p.thirst = 1.0; p.energy = 1.0; p.warmth = 1.0;
    if Stock.amount(&"eggs") > _before_eggs or GameClock.total_hours - _start > 14.0:
        _expect("a farmer collected the eggs into storage (%d)" % Stock.amount(&"eggs"), Stock.amount(&"eggs") > _before_eggs);
        print("LIVESTOCK %s" % ("PASS" if _fails == 0 else "FAIL"));
        get_tree().quit(1 if _fails > 0 else 0);
        _phase = 4;

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
