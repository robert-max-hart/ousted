# ----------------------------------------------------------------
# Water: drought, buckets and irrigation channels
#     godot --headless --path . --fixed-fps 60 res://tests/water.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;
var world:World;
var _phase:int = 0;
var _field:Field;
var _farmer:Pawn;
var _start:float = 0.0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    Weather.drought_enabled = false;
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    world.seeds.unlock_all();
    _drought();
    _channels();
    _buckets();

func _drought() -> void:
    Weather.drought_days = 0;
    var cool:float = Weather.temperature;
    Weather.drought_days = 5;
    Weather.is_raining = true;
    Weather._on_hour(GameClock.hour());
    _expect("a drought stops the rain", not Weather.is_raining);
    Weather._update_temperature();
    _expect("it is hotter (%.1f vs %.1f)" % [Weather.temperature, cool], Weather.temperature > cool + 2.0);
    _expect("everything dries faster and the weather says so", Weather.drying() > 2.0 and Weather.description() == "Drought");
    var saved:Dictionary = Weather.save_state();
    Weather.drought_days = 0;
    Weather.restore_state(saved);
    _expect("a drought is saved", Weather.drought_days == 5);
    Weather.drought_days = 0;

func _free_spot() -> Vector2i:
    var o:Vector2i = world.town_hall.origin + Vector2i(8, -10);
    for rn in world.nodes.duplicate():
        if Rect2i(o - Vector2i(3, 3), Vector2i(16, 12)).has_point(rn.cell):
            world.remove_node(rn);
    world.terrain.flatten_rect(Rect2i(o - Vector2i(2, 2), Vector2i(18, 14)));
    return o;

func _channels() -> void:
    var o:Vector2i = _free_spot();
    var t:Terrain = world.terrain;
    # a lone channel cell is dry; one beside water is wet, and so is whatever connects to it
    world.plan_road(o, Terrain.Overlay.CHANNEL);
    _expect("a staked channel cell waits for work", world.road_work.has(o) and world.road_kind[o] == Terrain.Overlay.CHANNEL);
    _expect("it takes channel work, not road work", not world.work_road(o, Defs.ROAD_WORK_HOURS + 0.01) and world.work_road(o, Defs.CHANNEL_WORK_HOURS));
    _expect("a dug cell away from water is a dry channel", t.get_overlay(o) == Terrain.Overlay.CHANNEL);
    var shore:Vector2i = Vector2i(-1, -1);
    for z in range(2, Terrain.SIZE - 2):
        for x in range(2, Terrain.SIZE - 2):
            var c:Vector2i = Vector2i(x, z);
            if shore.x < 0 and not t.is_water(c) and t.is_water(c + Vector2i(1, 0)) and world.occupant[world.idx(c)] == null and world.node_at[world.idx(c)] == null and not t.is_water(c + Vector2i(-1, 0)) and not t.is_water(c + Vector2i(-2, 0)) and not t.is_water(c + Vector2i(-1, 1)) and not t.is_water(c + Vector2i(-1, -1)) and not t.is_water(c + Vector2i(-2, 1)) and not t.is_water(c + Vector2i(-2, -1)):
                shore = c;
    _expect("a shore cell exists on this map", shore.x >= 0);
    if shore.x < 0:
        return;
    for rn in world.nodes.duplicate():
        if Rect2i(shore - Vector2i(8, 3), Vector2i(10, 7)).has_point(rn.cell):
            world.remove_node(rn);
    for c in [shore, shore + Vector2i(-1, 0)]:
        world.plan_road(c, Terrain.Overlay.CHANNEL);
        world.work_road(c, 5.0);
    _expect("a channel beside water is wet", t.get_overlay(shore) == Terrain.Overlay.CHANNEL_WET);
    _expect("so is the cell connected to it", t.get_overlay(shore + Vector2i(-1, 0)) == Terrain.Overlay.CHANNEL_WET);
    _expect("a house can't go on a channel", world.can_place(&"house", shore - Vector2i(1, 1), Vector2i(3, 3)) != "");
    world.remove_channel(shore);
    _expect("removing the link dries the rest", t.get_overlay(shore + Vector2i(-1, 0)) == Terrain.Overlay.CHANNEL);
    # a field beside a wet channel stays moist
    world.plan_road(shore, Terrain.Overlay.CHANNEL);
    world.work_road(shore, 5.0);
    var spot:Vector2i = shore + Vector2i(-5, -1);
    var f:Field = world.place_building(&"field", spot, Vector2i(3, 3), true) as Field;
    f.plot_state[4] = Field.Plot.PLANTED;
    f.plot_crop[4] = f.crop_id;
    for i in f.plot_count():
        f.moisture[i] = 0.0;
        f.near_water[i] = 0;
    f.on_hour();
    var irrigated:int = 0;
    var moist:int = 0;
    for i in f.plot_count():
        irrigated += f.irrigated[i];
        moist += 1 if f.moisture[i] >= Field.IRRIGATED_MOISTURE - 0.01 else 0;
    _expect("plots within reach of a flowing channel are irrigated (%d of %d)" % [irrigated, f.plot_count()], irrigated > 0);
    _expect("and are held moist (%d)" % moist, moist == irrigated);

func _buckets() -> void:
    var o:Vector2i = world.town_hall.origin + Vector2i(-12, -14);
    for rn in world.nodes.duplicate():
        if Rect2i(o - Vector2i(3, 3), Vector2i(18, 12)).has_point(rn.cell):
            world.remove_node(rn);
    world.terrain.flatten_rect(Rect2i(o - Vector2i(2, 2), Vector2i(20, 14)));
    world.place_building(&"well", o + Vector2i(8, 0), Vector2i(2, 2), true);
    _field = world.place_building(&"field", o, Vector2i(5, 5), true) as Field;
    for i in _field.plot_count():
        _field.moisture[i] = 0.9;
        _field.near_water[i] = 0;
        _field.irrigated[i] = 0;
    _field._irrigation_seen = world.irrigation_version;
    _field.plot_state[12] = Field.Plot.PLANTED;
    _field.plot_crop[12] = _field.crop_id;
    _field.moisture[12] = 0.1;
    _expect("a dry growing plot wants a bucket", _field.find_work(o, &"", Callable(), true).get("action", &"") == &"water");
    _expect("but not when there is no well", _field.find_work(o, &"", Callable(), false).get("action", &"") != &"water");
    _field.apply(12, &"water", world.pawns[0]);
    _expect("a bucket wets the plot and its neighbours", _field.moisture[12] >= Field.BUCKET_MOISTURE and _field.moisture[13] >= Field.BUCKET_MOISTURE and _field.moisture[6] >= Field.BUCKET_MOISTURE);
    _expect("and not the far corner", _field.moisture[24] < 0.95 and _field.moisture[0] > 0.0);
    # a farmer does it on their own
    _field.moisture[12] = 0.05;
    _farmer = world.pawns[0];
    _farmer.profession = JobManager.Profession.FARMER;
    world.jobs.change_profession(JobManager.Profession.FARMER, 1);
    GameClock.total_hours = 10.0;
    GameClock.set_speed(3);
    Engine.time_scale = 4.0;
    _start = GameClock.total_hours;
    _phase = 1;

func _process(_delta:float) -> void:
    if _phase != 1:
        return;
    for p in world.pawns:
        p.hunger = 1.0; p.thirst = 1.0; p.energy = 1.0; p.warmth = 1.0;
    _field.moisture[12] = minf(_field.moisture[12], 0.05) if GameClock.total_hours - _start < 0.01 else _field.moisture[12];
    if _field.moisture[12] >= Field.BUCKET_MOISTURE - 0.001 or GameClock.total_hours - _start > 12.0:
        _expect("a farmer fetched a bucket and watered the plot", _field.moisture[12] >= Field.BUCKET_MOISTURE - 0.001);
        print("WATER %s" % ("PASS" if _fails == 0 else "FAIL"));
        Weather.drought_enabled = true;
        get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
