# ----------------------------------------------------------------
# Tavern
#     An evening out: adults visit between 17:00 and 20:00, come away a
#     little happier (even with nothing to drink), drink spirits from
#     the tavern's store when they are ready for a treat, and the store
#     is kept stocked by laborers up to its setting (not while the
#     treats rule is off). The building is expensive.
#     godot --headless --path . --fixed-fps 60 res://tests/tavern.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;
var world:World;
var _tavern:Building;
var _phase:int = 0;
var _start:float = 0.0;
var _unready:Array[Pawn] = [];

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
    var def:Dictionary = Defs.BUILDINGS[&"tavern"];
    var cost:int = 0;
    var school:int = 0;
    for k in def["cost"]:
        cost += def["cost"][k] * Defs.trade_value(k);
    for k in Defs.BUILDINGS[&"school"]["cost"]:
        school += Defs.BUILDINGS[&"school"]["cost"][k] * Defs.trade_value(k);
    _expect("the tavern is expensive (%d against the school's %d)" % [cost, school], cost > school * 1.5 and def["cost"].has(&"iron"));
    _expect("it is in the Civic menu", Defs.BUILD_MENU.has(&"tavern") and (Defs.BUILD_CATEGORIES[4][1] as Array).has(&"tavern"));
    for b in world.buildings.duplicate():           # (no supply cart: citizens busy hauling from it all evening would not get to the tavern)
        if b.def_id == &"cart":
            world.remove_building(b, false);
    for p in world.pawns:
        p.clear_carry();
        p.end_task(false);
    var o:Vector2i = TestSite.spot(world, Vector2i(4, 3), Vector2i(-8, 8));
    _tavern = world.place_building(&"tavern", o, Vector2i(4, 3), true);
    _expect("it was built", _tavern != null and _tavern.is_complete());
    world.town_hall.store(&"spirits", 20);
    world.policies.set_on(&"treats", true);
    _expect("it wants its store filled from storage (%s)" % str(_tavern.inputs_wanted()), _tavern.inputs_wanted().get(&"spirits", 0) == 8);
    _tavern.settings["keep_spirits"] = 4;
    _expect("the level is a setting", _tavern.inputs_wanted().get(&"spirits", 0) == 4);
    world.policies.set_on(&"treats", false);
    _expect("not filled while treats are off", _tavern.inputs_wanted().is_empty());
    world.policies.set_on(&"treats", true);
    _tavern.settings["keep_spirits"] = 8;
    # an evening: nobody has been yet; two thirds of them are ready for a drink
    var day:int = 3 * GameClock.DAYS_PER_SEASON + 1;
    GameClock.total_hours = day * GameClock.HOURS_PER_DAY + 16.0;
    Weather._update_temperature();
    var k:int = 0;
    for p in world.pawns:
        p.treat_until = 0.0;
        p.treat_ready = 1.0 if k % 3 != 0 else 1.0e9;
        if k % 3 == 0:
            _unready.append(p);
        p.tavern_day = -1;
        k += 1;
    world.town_hall.stored.erase(&"spirits");         # (the only spirits left are the tavern's)
    _tavern.add_input(&"spirits", 8);
    var d:Dictionary = world.pawns[0].to_dict();
    world.pawns[0].tavern_day = 5;
    world.pawns[0].restore(world, d);
    _expect("the visit is saved", world.pawns[0].tavern_day == -1);
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
        if p.task != null and p.task.kind == &"tavern":
            inside += 1;
    if inside > 0 and _phase == 1:
        _expect("no more than the tavern holds (%d)" % inside, inside <= 10);
    var hour:float = GameClock.hour();
    var elapsed:float = GameClock.total_hours - _start;
    if elapsed < 6.0:
        return;
    var visited:int = 0;
    var boosted:int = 0;
    var drank:int = 0;
    var ate_alone:int = 0;
    var adults:int = 0;
    for p in world.pawns:
        if not p.is_adult():
            _expect("children stay away", p.tavern_day == -1);
            continue;
        adults += 1;
        if p.tavern_until > _start:
            visited += 1;
            var named:bool = false;
            for f in p.happiness_factors():
                named = named or f[0] == "Evening at the tavern";
            boosted += 1 if named or GameClock.total_hours >= p.tavern_until else 0;
        if p.treat_item == &"spirits":
            drank += 1;
    _expect("about half the adults went (%d of %d, hour %.1f)" % [visited, adults, hour], visited >= 2 and visited < adults);
    _expect("and came away with the lift (%d)" % boosted, boosted == visited);
    _expect("those ready for a drink had spirits (%d)" % drank, drank >= 1 and _tavern.input_amount(&"spirits") == 8 - drank);
    _expect("those who weren't ready did not", _unready.all(func(p:Pawn) -> bool: return p.treat_item != &"spirits"));
    _expect("the mood lift is very small (%.2f)" % Defs.TAVERN_MOOD, Defs.TAVERN_MOOD <= 0.05 and Defs.TAVERN_MOOD < Defs.ITEMS[&"spirits"]["treat"]["mood"] * 0.25);
    _expect("nobody is left inside", world.pawns.all(func(p:Pawn) -> bool: return not (p.indoors and is_same(p.shelter, _tavern))));
    print("TAVERN %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);
    _phase = 2;

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
