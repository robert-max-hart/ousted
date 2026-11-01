# ----------------------------------------------------------------
# Loose ends
#     Things added after the first versions of several M8 features:
#     the Cultivation upgrade sows herbs and the climates' wild foods,
#     merchants and the Distillery take the new foods, lightning hurts
#     what it hits, shade buildings cool citizens (and heat makes them
#     more likely to fall ill and slows crops), snow shows in the
#     walking costs the pathfinder uses, and the fire, fishing, teaching
#     and healing tasks each have their own pose.
#     godot --headless --path . --fixed-fps 60 res://tests/loose_ends.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;
var world:World;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    Weather.drought_enabled = false;
    GameRules.reset();
    GameRules.illness = 2;
    Climate.current = Climate.Id.TROPICAL;
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    await get_tree().process_frame;
    GameClock.hour_changed.disconnect(Weather._on_hour);
    for b in world.buildings.duplicate():
        if b.def_id == &"cart":
            world.remove_building(b, false);
    var o:Vector2i = TestSite.near(world, Vector2i(10, -14), Vector2i(22, 16));
    world.terrain.flatten_rect(Rect2i(o - Vector2i(1, 1), Vector2i(24, 18)));
    for rn in world.nodes.duplicate():
        if Rect2i(o - Vector2i(2, 2), Vector2i(26, 20)).has_point(rn.cell):
            world.remove_node(rn);
    _sowing(o);
    _trade_and_still();
    _lightning(o);
    _shade_and_heat(o);
    _snow_paths(o);
    _action_poses();
    Climate.current = Climate.Id.TEMPERATE;
    print("LOOSE ENDS %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

# --------------------------------
func _sowing(o:Vector2i) -> void:
    var ctl:Array = Defs.BUILDINGS[&"forager"]["controls"];
    var ids:Array = ctl.map(func(c:Dictionary) -> String: return c["id"]);
    for kind in ProductionTasks.FORAGE_KINDS:
        _expect("the forager can be set to sow %s" % kind, ids.has("sow_%s" % kind));
    var hut:Building = world.place_building(&"forager", TestSite.spot(world, Vector2i(3, 3), o - TestSite.anchor(world) + Vector2i(2, 2)), Vector2i(3, 3), true);
    hut.upgrades_done[&"cultivation"] = true;
    var sower:Pawn = world.pawns[0];
    sower.clear_carry();
    sower.end_task(false);
    for k in ProductionTasks.FORAGE_KINDS:
        hut.settings["sow_%s" % k] = false;
    hut.settings["sow_banana"] = true;
    hut.settings["sow_lingon"] = true;                  # (not in this climate: it must be left alone)
    var sown:Dictionary = {};
    for round in 40:
        var t:Task = world.jobs.production._sow_task(hut);
        if t == null:
            continue;
        _expect("the task is for sowing", t.kind == &"plant");
        for cell in world.planting.keys():
            world.planting.erase(cell);                     # (what the task does when the work is done)
            if WildGrowth.can_grow(world, cell, &"banana"):
                var rn:ResourceNode = world.sow_wild(&"banana", cell);
                sown[rn.kind] = sown.get(rn.kind, 0) + 1;
    _expect("bananas are sown in a tropical map (%d patches)" % sown.get(&"banana", 0), sown.get(&"banana", 0) > 0);
    var lingon:int = world.nodes.filter(func(rn:ResourceNode) -> bool: return rn.kind == &"lingon").size();
    _expect("no lingonberries appear in the tropics (%d)" % lingon, lingon == 0);
    hut.settings["sow_herb"] = true;
    hut.settings["sow_banana"] = false;
    var herb_task:Task = null;
    for round in 40:
        herb_task = world.jobs.production._sow_task(hut);
        if herb_task != null:
            break;
    _expect("herbs can be sown too (the Herbalist's supply)", herb_task != null and herb_task.label.contains("herbs"));
    world.planting.clear();

# --------------------------------
func _trade_and_still() -> void:
    for item in [&"dates", &"coconuts", &"lingonberries", &"cactus_fruit", &"bananas"]:
        _expect("merchants deal in %s" % item, Traders.WANTS.has(item) or Traders.BRINGS.has(item));
        _expect("%s has a trade value" % item, Defs.trade_value(item) > 0);
    _expect("merchants can bring dates, coconuts and lingonberries", Traders.BRINGS.has(&"dates") and Traders.BRINGS.has(&"coconuts") and Traders.BRINGS.has(&"lingonberries"));

# --------------------------------
func _lightning(o:Vector2i) -> void:
    GameRules.fires = 0;                                # (no fires: only the blow itself)
    var at:Vector2i = TestSite.spot(world, Vector2i(3, 3), o - TestSite.anchor(world) + Vector2i(10, 8));
    var house:Building = world.place_building(&"house", at, Vector2i(3, 3), true);
    var stone_at:Vector2i = TestSite.spot(world, Vector2i(3, 3), o - TestSite.anchor(world) + Vector2i(15, 8));
    var stone:Building = world.place_building(&"stone_house", stone_at, Vector2i(3, 3), true);
    world.fires.strike(at + Vector2i(1, 1));
    world.fires.strike(stone_at + Vector2i(1, 1));
    _expect("a bolt on a wooden house hurts it (%.2f) and burns nothing at the None rule" % house.health, house.health < 0.9 and house.health > 0.6 and not house.burning);
    _expect("and hurts a stone one much less (%.2f)" % stone.health, stone.health > house.health + 0.05 and stone.health < 1.0);
    var tree_cell:Vector2i = o + Vector2i(2, 14);
    var blasted:int = 0;
    for i in 40:
        var tr:ResourceNode = world.add_node(&"tree", tree_cell);
        world.fires.strike(tree_cell);
        if world.node_at[world.idx(tree_cell)] != null and world.node_at[world.idx(tree_cell)].def.get("dead", false):
            blasted += 1;
        var left:ResourceNode = world.node_at[world.idx(tree_cell)];
        if left != null:
            world.remove_node(left);
    _expect("a bolt on a tree often blasts it into a dead one (%d of 40)" % blasted, blasted >= 8 and blasted <= 32);
    GameRules.fires = 2;

# --------------------------------
func _shade_and_heat(o:Vector2i) -> void:
    var p:Pawn = world.pawns[1];
    p.clear_carry();
    p.end_task(false);
    var open:Vector2i = o + Vector2i(12, 2);
    p.position = world.terrain.cell_center(open);
    _expect("no shade in the open", not Heat.cooling_spot(p));
    var arbor:Building = world.place_building(&"arbor", open + Vector2i(2, 0), Vector2i(2, 2), true);
    _expect("an arbor is built and counts as shade", arbor != null and arbor.is_complete() and arbor.def.get("shade", false));
    p.position = world.terrain.cell_center(open + Vector2i(1, 0));
    _expect("beside it citizens are in the shade", Heat.cooling_spot(p));
    p.position = world.terrain.cell_center(open + Vector2i(6, 0));
    _expect("farther off they are not", not Heat.cooling_spot(p));
    Weather.temperature = 38.0;
    p.overheat = 0.7;
    var task:Task = world.jobs.needs.cool_task(p);
    _expect("a hot citizen is sent to the arbor (%s)" % (task.target.def_id if task != null and task.target is Building else "none"), task != null and task.target is Building and (task.target as Building).def_id == &"arbor");
    var cost:Dictionary = Defs.BUILDINGS[&"arbor"]["cost"];
    _expect("it is cheap wood", cost.size() == 1 and cost[&"wood"] <= 8 and Defs.BUILD_MENU.has(&"arbor"));
    # illness and crops
    Weather.temperature = 20.0;
    p.overheat = 0.0;
    p.hunger = 1.0;
    var base:float = world.illness.onset_chance(p);
    p.overheat = 0.7;
    var hot:float = world.illness.onset_chance(p);
    _expect("heat makes a day's illness chance 1.5 times likelier (%.4f against %.4f)" % [hot, base], base > 0.0 and is_equal_approx(hot, base * Illness.HEAT_ONSET_MULT));
    var crop:Dictionary = Defs.CROPS[&"wheat"];
    var field:Field = Field.new();
    var cool_rate:float = field._growth_rate(crop, 28.0, 1.0);
    var scorch_rate:float = field._growth_rate(crop, 45.0, 1.0);
    field.free();
    _expect("scorching weather slows crops (%.5f against %.5f)" % [scorch_rate, cool_rate], scorch_rate < cool_rate * 0.75 and scorch_rate > cool_rate * 0.4);
    Weather.temperature = 20.0;
    p.overheat = 0.0;

# --------------------------------
func _snow_paths(o:Vector2i) -> void:
    var open:Vector2i = Vector2i(-1, -1);
    var road:Vector2i = Vector2i(-1, -1);
    for dz in range(0, 14):                           # two free cells, one above the other, away from anything built
        for dx in range(0, 20):
            var c:Vector2i = o + Vector2i(dx, dz);
            if open == Vector2i(-1, -1) and world.occupant[world.idx(c)] == null and world.node_at[world.idx(c)] == null and world.occupant[world.idx(c + Vector2i(0, 2))] == null and world.node_at[world.idx(c + Vector2i(0, 2))] == null and not world.terrain.is_water(c) and not world.terrain.is_water(c + Vector2i(0, 2)):
                open = c;
                road = c + Vector2i(0, 2);
    world.terrain.set_overlay(road, Terrain.Overlay.ROAD);
    world._refresh_nav(road);
    world._refresh_nav(open);
    Weather.snow_depth = 0.0;
    world._update_nav_snow();
    var open_dry:float = world.nav.astar.get_point_weight_scale(open);
    var road_dry:float = world.nav.astar.get_point_weight_scale(road);
    Weather.snow_depth = 1.0;
    world._update_nav_snow();
    var open_snow:float = world.nav.astar.get_point_weight_scale(open);
    var road_snow:float = world.nav.astar.get_point_weight_scale(road);
    _expect("snow makes open ground dearer to walk (%.2f to %.2f) and a road only a little (%.2f to %.2f)" % [open_dry, open_snow, road_dry, road_snow], open_snow > open_dry * 1.5 and road_snow < road_dry * 1.2);
    _expect("so a road wins by more in snow (%.2f against %.2f)" % [open_snow / road_snow, open_dry / road_dry], open_snow / road_snow > open_dry / road_dry * 1.3);
    Weather.snow_depth = 0.0;
    world._update_nav_snow();
    _expect("and the costs go back when it melts", is_equal_approx(world.nav.astar.get_point_weight_scale(open), open_dry));

# --------------------------------
func _action_poses() -> void:
    var p:Pawn = world.pawns[2];
    var cases:Array = [[&"fire", -1, &"throw"], [&"fish", JobManager.Profession.FISHERMAN, &"cast"], [&"teach", JobManager.Profession.TEACHER, &"gesture"], [&"heal", JobManager.Profession.HEALER, &"tend"]];
    for c in cases:
        var t:Task = Task.new(c[0], "x", true);
        t.job = c[1];
        p.task = t;
        _expect("%s tasks use the %s pose" % [c[0], c[2]], p._work_sound() == c[2]);
        p._rig.pose(PawnRig.Mode.WORK, 1.0, 1.0, p._work_sound(), false);
        var prop_wanted:bool = PawnRig.SWINGS[c[2]]["prop"] != &"";
        _expect("%s: the right tool shows (%s)" % [c[2], PawnRig.SWINGS[c[2]]["prop"]], p._rig._prop.visible == prop_wanted);
    p.task = null;
    var slow:bool = PawnRig.rate_of(&"cast") < PawnRig.rate_of(&"chop") * 0.6 and PawnRig.rate_of(&"gesture") < PawnRig.WORK_RATE;
    _expect("a cast and a lecture run at a slower pace than a chop", slow);
    _expect("the rod and the bucket have models", PawnRig.part("rod") != null and PawnRig.part("bucket") != null);

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
