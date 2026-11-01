# ----------------------------------------------------------------
# Overheating
#     In hot weather a citizen's heat load builds outdoors and falls in
#     shade (indoors, by a tree, by water or a well); thirst, work speed,
#     mood and health follow it; a citizen who is too hot goes to cool
#     off; in the worst midday heat everyone with a home rests indoors
#     unless the policy says to work on; heat is saved.
#     godot --headless --path . --fixed-fps 60 res://tests/overheating.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;
var world:World;

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
    GameClock.hour_changed.disconnect(Weather._on_hour);
    for b in world.buildings.duplicate():
        if b.def_id == &"cart":
            world.remove_building(b, false);
    var o:Vector2i = TestSite.near(world, Vector2i(10, -14), Vector2i(20, 12));
    world.terrain.flatten_rect(Rect2i(o - Vector2i(1, 1), Vector2i(22, 14)));
    for rn in world.nodes.duplicate():
        if Rect2i(o - Vector2i(2, 2), Vector2i(24, 16)).has_point(rn.cell):
            world.remove_node(rn);
    var p:Pawn = world.pawns[0];
    p.clear_carry();
    p.end_task(false);
    var open:Vector2i = o + Vector2i(2, 2);
    var shade_tree:ResourceNode = world.add_node(&"tree", o + Vector2i(12, 2));
    var shade:Vector2i = o + Vector2i(13, 2);
    p.position = world.terrain.cell_center(open);
    p.thirst = 1.0;
    # outdoors in the heat the load builds; temperate summer weather does nothing
    Weather.temperature = 24.0;
    p.overheat = 0.0;
    Heat.tick(p, 4.0);
    _expect("24 C is comfortable (%.2f)" % p.overheat, p.overheat == 0.0);
    Weather.temperature = 36.0;
    Heat.tick(p, 2.0);
    var open_36:float = p.overheat;
    _expect("36 C builds heat outdoors (%.2f in 2 hours)" % open_36, open_36 > 0.15 and open_36 < 0.4);
    p.overheat = 0.0;
    Weather.temperature = 42.0;
    Heat.tick(p, 2.0);
    _expect("42 C builds it faster (%.2f against %.2f)" % [p.overheat, open_36], p.overheat > open_36 * 1.4);
    # what raises and lowers the load
    Weather.temperature = 36.0;
    p.overheat = 0.0;
    p.thirst = 0.0;
    Heat.tick(p, 2.0);
    _expect("thirst makes it worse (%.2f)" % p.overheat, p.overheat > open_36 * 1.2);
    p.thirst = 1.0;
    p.overheat = 0.0;
    p.clothing = &"clothes_wool";
    Heat.tick(p, 2.0);
    _expect("so do warm clothes (%.2f against %.2f)" % [p.overheat, open_36], p.overheat > open_36 * 1.1);
    p.clothing = &"";
    p.overheat = 0.0;
    var baby_age:float = p.age;
    p.age = 70.0;
    Heat.tick(p, 2.0);
    _expect("and old age (%.2f)" % p.overheat, p.overheat > open_36 * 1.3);
    p.age = baby_age;
    # shade: a tree, indoors, water and a well all cool
    p.overheat = 0.8;
    _expect("out in the open there is no cooling spot", not Heat.cooling_spot(p));
    p.position = world.terrain.cell_center(shade);
    _expect("beside a tree there is", Heat.cooling_spot(p));
    Heat.tick(p, 2.0);
    _expect("and heat falls there even at 36 C (%.2f)" % p.overheat, p.overheat < 0.8);
    p.position = world.terrain.cell_center(open);
    var house_at:Vector2i = TestSite.spot(world, Vector2i(3, 3), o - TestSite.anchor(world) + Vector2i(6, 6));
    var house:Building = world.place_building(&"house", house_at, Vector2i(3, 3), true);
    p.go_inside(house, false);
    _expect("indoors cools", Heat.cooling_spot(p));
    p.go_outside();
    var well_at:Vector2i = TestSite.spot(world, Vector2i(2, 2), o - TestSite.anchor(world) + Vector2i(14, 6));
    var well:Building = world.place_building(&"well", well_at, Vector2i(2, 2), true);
    p.position = world.terrain.cell_center(well_at + Vector2i(3, 0));
    _expect("beside a well cools", Heat.cooling_spot(p));
    p.position = world.terrain.cell_center(open);
    Weather.temperature = 20.0;
    p.overheat = 0.6;
    Heat.tick(p, 2.0);
    _expect("in cool weather it falls anywhere (%.2f)" % p.overheat, p.overheat < 0.4);
    # what heat does: thirst, work, mood, health
    p.overheat = 0.0;
    var calm_thirst:float = Heat.thirst_mult(p);
    p.overheat = 1.0;
    _expect("a heat-struck citizen thirsts twice as fast", is_equal_approx(Heat.thirst_mult(p), 2.0) and calm_thirst == 1.0);
    _expect("and works at half speed (%.2f)" % Heat.work_factor(p), is_equal_approx(Heat.work_factor(p), 0.5));
    p.overheat = 0.2;
    _expect("a little heat does not slow them", Heat.work_factor(p) == 1.0 and Heat.mood_loss(p) == 0.0);
    p.overheat = 1.0;
    _expect("it sours the mood", p.happiness_factors().any(func(f:Array) -> bool: return f[0] == "Too hot"));
    Weather.temperature = 40.0;
    var damage:float = Heat.tick(p, 1.0);
    _expect("heatstroke hurts (%.3f an hour)" % damage, damage > 0.03);
    p.overheat = 0.5;
    _expect("but a hot citizen who is not about to collapse is not hurt", Heat.tick(p, 0.1) == 0.0);
    p.overheat = 0.9;
    p.health = 0.0;
    _expect("the cause of death is heatstroke", p._death_cause() == "heatstroke");
    p.health = 1.0;
    _expect("the inspector shows coolness", p.info_text().contains("Coolness"));
    # cooling off: an overheated citizen is sent to shade, and stays until cool
    p.position = world.terrain.cell_center(open);
    p.overheat = 0.7;
    Weather.temperature = 36.0;
    var task:Task = world.jobs.needs.cool_task(p);
    _expect("an overheated citizen is given a cooling task (%s)" % (task.label if task != null else "none"), task != null and task.kind == &"cool");
    p.overheat = 0.7;
    var chosen:Task = world.jobs.choose_task(p);
    _expect("and choose_task picks it before work", chosen != null and chosen.kind == &"cool");
    p.end_task(false);
    # the midday siesta
    p.overheat = 0.0;
    world.families.move_home(p, house);
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON + 3) * GameClock.HOURS_PER_DAY + 13.0;
    Weather.temperature = 40.0;
    _expect("at 40 C at 13:00 with a home, the citizen rests indoors", Heat.siesta_due(p));
    var rest:Task = world.jobs.choose_task(p);
    _expect("and is given a stay-home task (%s)" % (rest.kind if rest != null else "none"), rest != null and rest.kind == &"stay_home");
    Weather.temperature = 34.0;
    _expect("not at 34 C", not Heat.siesta_due(p));
    Weather.temperature = 40.0;
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON + 3) * GameClock.HOURS_PER_DAY + 8.0;
    _expect("not in the morning", not Heat.siesta_due(p));
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON + 3) * GameClock.HOURS_PER_DAY + 13.0;
    world.policies.set_on(&"heat_work", true);
    _expect("the policy lets them work on", not Heat.siesta_due(p));
    world.policies.set_on(&"heat_work", false);
    var homeless:Pawn = world.pawns[5];
    world.families.move_home(homeless, null);
    _expect("someone with no home cannot go in", not Heat.siesta_due(homeless));
    _expect("the rule is a policy, off by default", Defs.POLICIES.has(&"heat_work") and not Defs.POLICIES[&"heat_work"]["default"]);
    # saving
    p.overheat = 0.42;
    var d:Dictionary = p.to_dict();
    p.overheat = 0.0;
    p.restore(world, d);
    _expect("heat is saved", is_equal_approx(p.overheat, 0.42));
    # climates: how hot a day gets
    var peaks:Dictionary = {};
    for id in [Climate.Id.TEMPERATE, Climate.Id.ARCTIC, Climate.Id.DESERT, Climate.Id.TROPICAL]:
        Climate.current = id;
        var hottest:float = -99.0;
        for h in range(0, 24):
            GameClock.total_hours = (GameClock.DAYS_PER_SEASON + 3) * GameClock.HOURS_PER_DAY + h;
            Weather.reset();
            Weather._day_offset = 0.0;
            Weather._update_temperature();
            hottest = maxf(hottest, Weather.temperature);
        peaks[id] = hottest;
    Climate.current = Climate.Id.TEMPERATE;
    print("hottest summer hour by climate: %s" % str(peaks));
    _expect("temperate and arctic summers never overheat anyone, the desert does a lot, the tropics a little", peaks[Climate.Id.TEMPERATE] < Heat.FROM and peaks[Climate.Id.ARCTIC] < Heat.FROM and peaks[Climate.Id.DESERT] > Heat.SIESTA_TEMP and peaks[Climate.Id.TROPICAL] > Heat.FROM);
    print("OVERHEATING %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
