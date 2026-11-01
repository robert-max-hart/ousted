# ----------------------------------------------------------------
# Chapel
#     A service every 8th day, in the morning, led by no one: about 6 in
#     10 adults go, come away lifted for a few days, and the grief for a
#     recent death is halved. Not on other days, not the children.
#     godot --headless --path . --fixed-fps 60 res://tests/chapel.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;
var world:World;
var _chapel:Building;
var _phase:int = 0;
var _start:float = 0.0;
var _griever:Pawn;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    Weather.drought_enabled = false;
    GameRules.reset();
    GameRules.illness = 0;
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    Weather._day_offset = 0.0;
    _expect("it is in the Civic menu, needs only wood and stone", Defs.BUILD_MENU.has(&"chapel") and (Defs.BUILD_CATEGORIES[4][1] as Array).has(&"chapel") and Defs.BUILDINGS[&"chapel"]["cost"].keys().all(func(k:StringName) -> bool: return k == &"wood" or k == &"stone"));
    _expect("service days come every 8th day", Defs.is_service_day(7) and Defs.is_service_day(15) and not Defs.is_service_day(8) and not Defs.is_service_day(0));
    for b in world.buildings.duplicate():
        if b.def_id == &"cart":
            world.remove_building(b, false);
    for p in world.pawns:
        p.clear_carry();
        p.end_task(false);
    var o:Vector2i = TestSite.spot(world, Vector2i(3, 4), Vector2i(-8, 8));
    _chapel = world.place_building(&"chapel", o, Vector2i(3, 4), true);
    _expect("it was built", _chapel != null and _chapel.is_complete());
    # an ordinary day: nobody is due
    var plain:int = 3 * GameClock.DAYS_PER_SEASON + 6;
    GameClock.total_hours = plain * GameClock.HOURS_PER_DAY + 8.2;
    _expect("not due on an ordinary day", world.pawns.all(func(p:Pawn) -> bool: return not p.chapel_due()));
    # the service day
    var day:int = 3 * GameClock.DAYS_PER_SEASON + 7;
    GameClock.total_hours = day * GameClock.HOURS_PER_DAY + 7.4;
    Weather._update_temperature();
    for p in world.pawns:
        p.chapel_day = -1;
        p.chapel_until = 0.0;
        p.grief.clear();
        if _griever == null and p.is_adult():
            _griever = p;
    _griever.add_grief(0.4, 12.0, 99);
    _griever.add_grief(0.3, 12.0, 98);
    _griever.grief[1]["start"] -= 20.0 * GameClock.HOURS_PER_DAY;       # a death long ago: not eased
    var before:float = _griever.grief_now();
    _griever.pray();
    _expect("praying halves recent grief only (%.2f to %.2f)" % [before, _griever.grief_now()], _griever.grief[0]["amount"] == 0.2 and _griever.grief[1]["amount"] == 0.3);
    _griever.pray();
    _expect("and only once", _griever.grief[0]["amount"] == 0.2);
    _griever.grief[0]["amount"] = 0.4;
    _griever.grief[0]["prayed"] = false;
    var d:Dictionary = world.pawns[0].to_dict();
    world.pawns[0].chapel_day = 5;
    world.pawns[0].restore(world, d);
    _expect("the visit is saved", world.pawns[0].chapel_day == -1);
    GameClock.set_speed(3);
    Engine.time_scale = 4.0;
    _start = GameClock.total_hours;
    _phase = 1;

func _process(_delta:float) -> void:
    if _phase != 1:
        return;
    for p in world.pawns:
        p.hunger = 1.0; p.thirst = 1.0; p.warmth = 1.0; p.health = 1.0;
        if GameClock.total_hours - _start < 0.5:
            p.energy = 1.0;
    var inside:int = 0;
    for p in world.pawns:
        if p.task != null and p.task.kind == &"chapel":
            inside += 1;
    _expect("no more than the chapel holds (%d)" % inside, inside <= 20);
    if GameClock.total_hours - _start < 5.0:
        return;
    var visited:int = 0;
    var adults:int = 0;
    var named:int = 0;
    for p in world.pawns:
        if not p.is_adult():
            _expect("children stay away", p.chapel_day == -1);
            continue;
        adults += 1;
        if p.chapel_until > _start:
            visited += 1;
            for f in p.happiness_factors():
                if f[0] == "Attended service":
                    named += 1;
    _expect("a good share of the adults went (%d of %d)" % [visited, adults], visited >= 2 and visited <= adults);
    _expect("and came away with the lift (%d)" % named, named == visited);
    if _griever.chapel_until > _start:
        _expect("the griever's sorrow was eased", _griever.grief[0]["amount"] <= 0.2 + 0.0001);
    _expect("the lift beats the tavern's", Defs.CHAPEL_MOOD > Defs.TAVERN_MOOD);
    _expect("nobody is left inside", world.pawns.all(func(p:Pawn) -> bool: return not (p.indoors and is_same(p.shelter, _chapel))));
    print("CHAPEL %s" % ("PASS" if _fails == 0 else "FAIL"));
    _phase = 2;
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
