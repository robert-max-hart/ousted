# ----------------------------------------------------------------
# Foraging test
#     Wild foods come back per kind and per season, the Forage tool marks
#     only forageables (and the Harvest tool leaves them alone), and a
#     Forager's Hut sends its workers to pick what it is switched on for,
#     in its radius, until the food cap is reached.
#     godot --headless --path . --fixed-fps 60 res://tests/foraging.tscn
# ----------------------------------------------------------------
extends Node;

var world:World;
var hut:Building;
var forager:Pawn;
var _frames:int = 0;
var _start_hours:float;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    var ok:bool = true;
    for kind in Defs.RESOURCE_NODES:
        var d:Dictionary = Defs.RESOURCE_NODES[kind];
        if d.get("forage", false):
            ok = ok and d.has("fruit_seasons") and d.has("regrow_days") and d.get("regrows", false) and Defs.is_food(d["item"]);
    _expect("every forageable has seasons, a respawn rate and a food item", ok);
    # respawn per kind and season
    var th:Building = world.town_hall;
    var hazel:ResourceNode = _node_near(&"hazel", Vector2i(-10, -6));
    var mushroom:ResourceNode = _node_near(&"mushroom", Vector2i(-10, -3));
    var berry:ResourceNode = _node_near(&"bush", Vector2i(-10, 0));
    var empty_all:Callable = func() -> void:
        for rn in [hazel, mushroom, berry]:
            rn.amount = 0;
    var day_at:Callable = func(season:int, day_of_season:int) -> void:
        GameClock.total_hours = float(season * GameClock.DAYS_PER_SEASON + day_of_season) * GameClock.HOURS_PER_DAY + 8.0;
    empty_all.call();
    day_at.call(0, 2);        # spring, an even day
    world._on_day(0);
    _expect("spring, even day: mushrooms and berries come back, hazelnuts don't", mushroom.amount == 1 and berry.amount == 1 and hazel.amount == 0);
    day_at.call(0, 3);        # odd day: mushrooms only every second day
    world._on_day(0);
    _expect("odd day: berries again, mushrooms rest", berry.amount == 2 and mushroom.amount == 1);
    day_at.call(2, 2);        # autumn
    world._on_day(0);
    _expect("autumn: hazelnuts come back, berries (spring and summer) don't", hazel.amount == 1 and berry.amount == 2);
    day_at.call(3, 2);        # winter
    empty_all.call();
    world._on_day(0);
    _expect("winter: nothing comes back", hazel.amount == 0 and mushroom.amount == 0 and berry.amount == 0);
    # tools
    for rn in [hazel, mushroom, berry]:
        rn.amount = rn.max_amount;
        world.set_designated(rn, false);
    var tree:ResourceNode = _node_near(&"tree", Vector2i(-10, 3));
    world.set_designated(tree, false);
    var tools:PlayerTools = world.tools;
    var area:Callable = func(m:int) -> void:
        tools.set_mode(m);
        tools._dragging = true;
        tools._drag_start = hazel.cell + Vector2i(-12, -12);
        tools._hover_cell = hazel.cell + Vector2i(12, 12);
        tools._on_release();
    area.call(PlayerTools.Mode.HARVEST);
    _expect("the Harvest tool leaves wild foods alone", not hazel.designated and not mushroom.designated and not berry.designated);
    world.set_designated(tree, false);        # the Harvest tool marked it above
    area.call(PlayerTools.Mode.FORAGE);
    _expect("the Forage tool marks them", hazel.designated and mushroom.designated and berry.designated);
    _expect("and leaves trees alone", not tree.designated);
    for rn in world.nodes:
        world.set_designated(rn, false);        # including the natural ones the tools just marked
    # the hut
    hut = world.place_building(&"forager", th.origin + Vector2i(-4, 8), Vector2i(3, 3), true);
    var near:ResourceNode = _node_near(&"mushroom", Vector2i(-4, 14));
    var off:ResourceNode = _node_near(&"hazel", Vector2i(-4, 11));
    var far:ResourceNode = _node_near(&"mushroom", Vector2i(-4, 40));
    near.amount = 3;
    off.amount = 6;
    far.amount = 3;
    hut.settings["forage_hazel"] = false;
    forager = world.pawns[0];
    forager.profession = JobManager.Profession.FORAGER;
    world.jobs.sync_targets();
    GameClock.total_hours = 8.0;
    hut.settings["cap_food"] = 1;
    _expect("a food cap already reached stops the hut", world.jobs.production.forager_task(forager) == null);
    hut.settings["cap_food"] = 0;
    var t:Task = world.jobs.production.forager_task(forager);
    var first:ResourceNode = t.target as ResourceNode if t != null else null;
    _expect("the hut sends a forager to a wild food in its radius", first != null and first.is_forageable() and first.kind != &"hazel" and Vector2(first.cell).distance_to(hut.center_cell()) <= hut.radius());
    if first != null:
        first.reserved_by = null;
    near.reserved_by = null;
    for rn in world.nodes:
        if rn.is_forageable() and rn != off and rn != far and Vector2(rn.cell).distance_to(hut.center_cell()) <= hut.radius() + 3.0:
            rn.amount = 0;          # nothing else to pick in range
    var t2:Task = world.jobs.production.forager_task(forager);
    _expect("with nothing else in range it picks no hazelnuts (switched off) and nothing beyond the radius", t2 == null);

    near.amount = 3;
    near.reserved_by = null;
    # save format
    var copy:ResourceNode = ResourceNode.from_array(near.to_array(), world.rng);
    _expect("a mushroom saves and loads back", copy.kind == &"mushroom" and copy.amount == 3);
    Engine.time_scale = 4.0;
    GameClock.set_speed(3);
    _start_hours = GameClock.total_hours;

func _node_near(kind:StringName, offset:Vector2i) -> ResourceNode:
    var center:Vector2i = world.town_hall.origin + offset;
    for r in range(0, 20):
        for dz in range(-r, r + 1):
            for dx in range(-r, r + 1):
                var c:Vector2i = center + Vector2i(dx, dz);
                if maxi(absi(dx), absi(dz)) == r and world.can_plant_tree(c):
                    return world.add_node(kind, c);
    return null;

func _process(_delta:float) -> void:
    if hut == null:
        return;
    _frames += 1;
    if Stock.amount(&"mushrooms") > 0 or GameClock.total_hours - _start_hours > 30.0:
        _expect("the forager picked mushrooms and they reached storage (%d)" % Stock.amount(&"mushrooms"), Stock.amount(&"mushrooms") > 0);
        _expect("and left the hazelnuts alone", Stock.amount(&"hazelnuts") == 0);
        get_tree().quit();

func _expect(what:String, ok:bool) -> void:
    print(("PASS " if ok else "FAIL ") + what);
