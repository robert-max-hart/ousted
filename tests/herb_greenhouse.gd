# ----------------------------------------------------------------
# HerbGreenhouse
#     The Herbalist's Hut: the Herb Greenhouse upgrade (costly, a bigger
#     store, a steady herb a day in any weather, a glasshouse that
#     appears and survives a save), and the healer's off-time work: pick
#     the greenhouse beds and wild herbs, stock the hut, and drop it all
#     for a sick citizen.
#     godot --headless --path . --fixed-fps 60 res://tests/herb_greenhouse.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;
var world:World;
var _hut:Herbalist;
var _healer:Pawn;
var _patient:Pawn;
var _start:float = 0.0;
var _phase:int = 0;
var _saw_collect:bool = false;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    Weather.drought_enabled = false;
    GameRules.reset();
    GameRules.illness = 0;
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    await get_tree().process_frame;
    var up:Dictionary = Defs.BUILDINGS[&"herbalist"]["upgrades"][&"greenhouse"];
    var total:int = 0;
    for k in up["cost"]:
        total += up["cost"][k];
    _expect("the greenhouse is expensive (%d goods, the hut itself costs 16)" % total, total >= 60 and up["cost"].has(&"iron"));
    _expect("the Forager's Hut can still pick herbs", Defs.BUILDINGS[&"forager"]["controls"].any(func(c:Dictionary) -> bool: return c["id"] == "forage_herb"));
    var o:Vector2i = TestSite.spot(world, Vector2i(3, 3), Vector2i(-6, -9));
    _hut = world.place_building(&"herbalist", o, Vector2i(3, 3), true) as Herbalist;
    _expect("it is a Herbalist with a store of 8", _hut != null and _hut.input_cap(&"herbs") == 8 and _hut.radius() > 0.0);
    for d in 5:
        _hut.on_day();
    _expect("no herbs grow without the upgrade", _hut.ready_herbs == 0 and _hut.collectable().is_empty());
    var decor_before:int = _hut._decor.size();
    _expect("the upgrade can be started", _hut.upgrade_block_reason(&"greenhouse") == "" and _hut.start_upgrade(&"greenhouse"));
    for item in _hut.cost():
        _hut.receive(item, _hut.cost()[item]);
    _hut.add_work(_hut.work_required());
    _expect("it is built", _hut.has_greenhouse() and _hut.upgrading == &"");
    _expect("the hut now keeps 16", _hut.input_cap(&"herbs") == 16);
    _expect("a glasshouse appears (%d new parts)" % (_hut._decor.size() - decor_before), _hut._decor.size() - decor_before >= 8);
    # in deep winter, too
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON * 3 + 2) * GameClock.HOURS_PER_DAY + 8.0;
    Weather.reset();
    Weather._update_temperature();
    for d in 4:
        _hut.on_day();
    _expect("herbs grow in winter, a day each (%d)" % _hut.ready_herbs, _hut.ready_herbs == 4);
    for d in 30:
        _hut.on_day();
    _expect("they stop at the cap (%d)" % _hut.ready_herbs, _hut.ready_herbs == Herbalist.GREEN_CAP);
    _expect("and are ready to pick", _hut.collectable().get("item", &"") == &"herbs");
    # saving
    var d:Dictionary = _hut.to_dict();
    var copy:Herbalist = Herbalist.new();
    copy.world = world;
    copy.def_id = &"herbalist";
    copy.def = Defs.BUILDINGS[&"herbalist"];
    copy.vsize = Vector2i(3, 3);
    copy.restore_dict(d);
    _expect("the beds and the upgrade are saved (%d)" % copy.ready_herbs, copy.ready_herbs == Herbalist.GREEN_CAP and copy.has_upgrade(&"greenhouse"));
    copy.free();
    # the healer's work
    _hut.settings["wild_herbs"] = false;
    _healer = world.pawns[4];
    _healer.profession = JobManager.Profession.HEALER;
    world.jobs.sync_targets();
    _patient = world.pawns[5];
    _patient.home = null;
    for q in world.pawns:
        if q != _healer and q != _patient:
            q.profession = JobManager.Profession.LABORER;
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON + 3) * GameClock.HOURS_PER_DAY + 7.0;
    Weather.reset();
    Weather._update_temperature();
    GameClock.set_speed(3);
    Engine.time_scale = 4.0;
    _start = GameClock.total_hours;
    _phase = 1;

func _process(_delta:float) -> void:
    if _phase == 0 or _phase == 9:
        return;
    for p in world.pawns:
        p.hunger = 1.0; p.thirst = 1.0; p.energy = 1.0; p.warmth = 1.0; p.health = 1.0;
    var hours:float = GameClock.total_hours - _start;
    if _healer.task != null and _healer.task.kind == &"herb_collect":
        _saw_collect = true;
    if _phase == 1:
        if _hut.input_amount(&"herbs") >= 8 or hours > 30.0:
            _expect("the healer picked the beds and filled the hut (%d in the hut, %d ready, %.0f h)" % [_hut.input_amount(&"herbs"), _hut.ready_herbs, hours], _saw_collect and _hut.input_amount(&"herbs") >= 8);
            # the beds refill, the healer fills storage with the overflow, a patient ends the trip
            _hut.ready_herbs = Herbalist.GREEN_CAP;
            _patient.illness = 0.7;
            _start = GameClock.total_hours;
            _phase = 2;
    elif _phase == 2:
        if _patient.care_until > GameClock.total_hours or hours > 30.0:
            _expect("a patient comes first: tended (%.0f h)" % hours, _patient.care_until > GameClock.total_hours);
            _expect("with herbs (quality %.1f)" % _patient.care_quality, _patient.care_quality >= 0.5);
            # wild herbs: no beds, an empty hut, a few ripe patches nearby
            _patient.illness = 0.0;
            _hut.ready_herbs = 0;
            _hut.green_acc = 0.0;
            _hut.inputs[&"herbs"] = 0;
            _hut.settings["wild_herbs"] = true;
            var c:Vector2i = _hut.origin + Vector2i(5, 0);
            var placed:int = 0;
            for dx in range(3, 9):
                for dz in range(-4, 6):
                    var cell:Vector2i = _hut.origin + Vector2i(dx, dz);
                    if placed < 4 and WildGrowth.can_grow(world, cell, &"herb"):
                        var rn:ResourceNode = world.sow_wild(&"herb", cell);
                        rn.amount = rn.def["amount"];
                        placed += 1;
            _expect("sowed wild patches by the hut (%d)" % placed, placed >= 2);
            _start = GameClock.total_hours;
            _phase = 3;
    elif _phase == 3:
        if _hut.input_amount(&"herbs") >= 3 or hours > 30.0:
            _expect("with no beds the healer picks wild herbs for the hut (%d, %.0f h)" % [_hut.input_amount(&"herbs"), hours], _hut.input_amount(&"herbs") >= 3);
            _finish();

func _finish() -> void:
    print("HERB_GREENHOUSE %s" % ("PASS" if _fails == 0 else "FAIL"));
    _phase = 9;
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
