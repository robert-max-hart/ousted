# ----------------------------------------------------------------
# Apiary
#     Bees make honey in warm weather, more with blossom nearby; they
#     rest in the cold; a farmer collects the honey; it can be traded.
#     godot --headless --path . --fixed-fps 60 res://tests/apiary.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;
var world:World;
var _hive:Apiary;
var _start:float = 0.0;
var _phase:int = 0;

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
    var o:Vector2i = TestSite.near(world, Vector2i(8, -10));
    for rn in world.nodes.duplicate():
        if Rect2i(o - Vector2i(14, 14), Vector2i(40, 30)).has_point(rn.cell):
            world.remove_node(rn);
    world.terrain.flatten_rect(Rect2i(o - Vector2i(2, 2), Vector2i(30, 16)));
    _hive = world.place_building(&"apiary", o, Vector2i(2, 2), true) as Apiary;
    _expect("it is an apiary", _hive != null and Apiary != null);
    _expect("it is in the build menu", Defs.BUILD_MENU.has(&"apiary"));
    _expect("honey has a trade value and does not spoil", Defs.trade_value(&"honey") >= 10 and not Defs.ITEMS[&"honey"].has("spoil_days"));
    _expect("no blossom: none counted", _hive.count_bloom() == 0.0);
    for i in 30:
        _hive.on_day();
    var bare:int = _hive.ready_honey;
    _expect("bees with no blossom still make a little (%d in 30 days)" % bare, bare >= 1 and bare <= 4);
    _hive.ready_honey = 0;
    _hive.honey_acc = 0.0;
    for k in 8:
        world.add_node(&"bush", o + Vector2i(4 + k, 2));
    world.add_node(&"hazel", o + Vector2i(4, 5));
    world.add_node(&"bush", o + Vector2i(20, 12));       # far away: does not count
    _expect("bushes and hazel in range are counted, the far one is not (%.1f)" % _hive.count_bloom(), is_equal_approx(_hive.count_bloom(), 9.0));
    for i in 30:
        _hive.on_day();
    _expect("with blossom nearby it makes much more (%d in 30 days)" % _hive.ready_honey, _hive.ready_honey > bare * 3 and _hive.ready_honey <= Apiary.READY_CAP);
    # cold: the bees rest
    var kept:int = _hive.ready_honey;
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON * 3 + 4) * GameClock.HOURS_PER_DAY;
    Weather._update_temperature();
    for i in 20:
        _hive.on_day();
    _expect("in the cold no honey is made", _hive.ready_honey == kept and not _hive.active());
    # saving
    var d:Dictionary = _hive.to_dict();
    _hive.ready_honey = 0;
    _hive.restore_dict(d);
    _expect("ready honey is saved", _hive.ready_honey == kept);
    _expect("the inspector has text", _hive.info_text().length() > 0 and _hive.help_text().length() > 0);
    # a farmer collects
    _hive.ready_honey = 6;
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON * 1 + 2) * GameClock.HOURS_PER_DAY + 12.0;
    Weather._update_temperature();
    var farmer:Pawn = world.pawns[0];
    farmer.profession = JobManager.Profession.FARMER;
    world.jobs.change_profession(JobManager.Profession.FARMER, 1);
    GameClock.set_speed(3);
    Engine.time_scale = 4.0;
    _start = GameClock.total_hours;
    _phase = 1;

func _physics_process(_delta:float) -> void:
    if _phase != 1:
        return;
    for p in world.pawns:
        p.hunger = 1.0; p.thirst = 1.0; p.energy = 1.0; p.warmth = 1.0;
    if Stock.amount(&"honey") > 0 or GameClock.total_hours - _start > 14.0:
        _expect("a farmer collected the honey into storage (%d, %d left)" % [Stock.amount(&"honey"), _hive.ready_honey], Stock.amount(&"honey") > 0);
        print("APIARY %s" % ("PASS" if _fails == 0 else "FAIL"));
        get_tree().quit(1 if _fails > 0 else 0);
        _phase = 2;

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
