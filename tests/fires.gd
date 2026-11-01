# ----------------------------------------------------------------
# Fires
#     Campfires, wildfires and buildings on fire. The rules: what
#     catches and how readily, dryness (rain, snow, wet ground), roads
#     and water as firebreaks, spreading, burning down trees and
#     crops, wooden buildings that burn down and stone ones that
#     survive, buckets that put fires out and soak the ground, citizens
#     who flee and fight, rare burns, the Wildfires rule, lightning,
#     campfires for the cold, and saving.
#     godot --headless --path . --fixed-fps 60 res://tests/fires.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;
var world:World;
var fires:Fires;

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
    fires = world.fires;
    for b in world.buildings.duplicate():
        if b.def_id == &"cart":
            world.remove_building(b, false);
    # a dry summer afternoon, a patch of forest cleared and replanted so the test knows what is where
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON + 3) * GameClock.HOURS_PER_DAY + 14.0;
    Weather.reset();
    Weather._day_offset = 0.0;
    Weather._update_temperature();
    world.wetness = 0.1;
    var o:Vector2i = TestSite.near(world, Vector2i(10, -14), Vector2i(26, 20));
    world.terrain.flatten_rect(Rect2i(o - Vector2i(1, 1), Vector2i(28, 22)));
    for rn in world.nodes.duplicate():
        if Rect2i(o - Vector2i(2, 2), Vector2i(30, 24)).has_point(rn.cell):
            world.remove_node(rn);
    # what catches: trees, shrubs and wood, not rock, road or water
    var tree:ResourceNode = world.add_node(&"tree", o + Vector2i(0, 0));
    var bush:ResourceNode = world.add_node(&"bush", o + Vector2i(3, 0));
    var rock:ResourceNode = world.add_node(&"rock", o + Vector2i(6, 0));
    world.terrain.set_overlay(o + Vector2i(9, 0), Terrain.Overlay.ROAD);
    _expect("a tree burns longer than a bush (%s, %s)" % [fires.flammability(tree.cell), fires.flammability(bush.cell)], fires.flammability(tree.cell)["hours"] > fires.flammability(bush.cell)["hours"] and fires.flammability(tree.cell)["catch"] > fires.flammability(o + Vector2i(1, 5))["catch"]);
    _expect("rock and road do not burn", fires.flammability(rock.cell).is_empty() and fires.flammability(o + Vector2i(9, 0)).is_empty());
    _expect("dry bare grass burns a little", not fires.flammability(o + Vector2i(1, 5)).is_empty());
    # dryness: rain, snow, wet ground, drought
    var dry:float = fires.dryness();
    Weather.intensity = 1.0;
    var wet:float = fires.dryness();
    Weather.intensity = 0.0;
    world.wetness = 0.9;
    var damp:float = fires.dryness();
    world.wetness = 0.1;
    Weather.drought_days = 3;
    var drought:float = fires.dryness();
    Weather.drought_days = 0;
    Weather.snow_depth = 0.5;
    var snowy:float = fires.dryness();
    Weather.snow_depth = 0.0;
    _expect("dryness: rain, damp ground and snow cut it, a drought raises it (%.2f, %.2f, %.2f, %.2f, %.2f)" % [dry, wet, damp, drought, snowy], wet < dry * 0.3 and damp < dry and drought > dry and snowy == 0.0);
    # a campfire burns its hours and goes out, and warms nearby citizens
    var camp:Vector2i = o + Vector2i(12, 14);
    _expect("a campfire lights on bare ground", fires.light_campfire(camp));
    _expect("not twice on a cell, not on a tree", not fires.light_campfire(camp) and not fires.light_campfire(tree.cell));
    _expect("it warms within its radius (%s)" % fires.camp_near(camp + Vector2i(2, 0), Fires.CAMP_WARM_RADIUS), fires.camp_near(camp + Vector2i(2, 0), Fires.CAMP_WARM_RADIUS) and not fires.camp_near(camp + Vector2i(6, 0), Fires.CAMP_WARM_RADIUS));
    _expect("a campfire is not a wildfire", not fires.wild_burning());
    for h in int(Fires.CAMP_HOURS) + 1:
        fires.on_hour();
    _expect("and it goes out after its hours", not fires.is_burning(camp));
    # a wildfire: ignite a tree among trees and watch it spread and burn the trees down
    var grove:Array[ResourceNode] = [];
    for dz in 5:
        for dx in 5:
            if (dx + dz) % 1 == 0:
                grove.append(world.add_node(&"tree", o + Vector2i(14 + dx, 2 + dz)));
    GameRules.fires = 2;
    _expect("a tree ignites", fires.ignite(grove[12].cell));
    _expect("it is a wildfire, and a tree on fire is marked", fires.wild_burning() and grove[12].burning);
    var peak:int = 0;
    print("dryness %.2f wet %.2f temp %.1f snow %.2f intensity %.2f share %.1f" % [fires.dryness(), world.wetness, Weather.temperature, Weather.snow_depth, Weather.intensity, GameRules.fire_share()]);
    for h in 30:
        fires.on_hour();
        peak = maxi(peak, fires.wild_cell_count());
    var gone:int = grove.filter(func(rn:ResourceNode) -> bool: return rn.removed).size();
    print("grove fire: peak %d cells, %d of %d trees gone, still burning %d" % [peak, gone, grove.size(), fires.wild_cell_count()]);
    _expect("it spreads through the grove (peak %d cells)" % peak, peak >= 4);
    _expect("and burns trees down (%d of %d)" % [gone, grove.size()], gone >= 5);
    _expect("and then it is out", not fires.wild_burning());
    # firebreaks: a fire cannot cross a road or water; a rock does not burn
    for e in fires.cells.keys():
        fires.cells.erase(e);
    GameRules.fires = 4;
    Weather.drought_days = 3;
    var left_tree:ResourceNode = world.add_node(&"tree", o + Vector2i(0, 10));
    var right_tree:ResourceNode = world.add_node(&"tree", o + Vector2i(2, 10));
    for rz in range(4, 17):          # a long road: dry grass could carry the fire round a short one
        world.terrain.set_overlay(o + Vector2i(1, rz), Terrain.Overlay.ROAD);
    fires.ignite(left_tree.cell);
    for h in 12:
        fires.on_hour();
    _expect("a road between trees stops the fire", not right_tree.removed and not right_tree.burning);
    Weather.drought_days = 0;
    # a bucket of water: puts out the fire and soaks the ground, so it does not spread back
    var t2:ResourceNode = world.add_node(&"tree", o + Vector2i(20, 12));
    var t3:ResourceNode = world.add_node(&"tree", o + Vector2i(21, 12));
    fires.ignite(t2.cell);
    fires.ignite(t3.cell);
    fires.douse(o + Vector2i(20, 12));
    _expect("a bucket puts out the cell it is thrown at, not the one beside it", not fires.is_burning(t2.cell) and fires.is_burning(t3.cell) and not t2.removed);
    _expect("and soaks the ground: it will not catch again for a while", not fires.ignite(t2.cell) and fires.is_soaked(t2.cell) and fires.is_soaked(t3.cell));
    fires.douse(t3.cell);
    _expect("a second bucket puts out the other", not fires.is_burning(t3.cell));
    GameClock.total_hours += Fires.SOAK_HOURS + 1.0;
    _expect("a soaking dries out", not fires.is_soaked(t2.cell));
    # rain puts fires out: heavy rain stops a forest fire that would otherwise burn on, a drizzle does nothing
    for e in fires.cells.keys():
        fires.cells.erase(e);
    GameRules.fires = 4;
    var rainy:Array[ResourceNode] = [];
    for k in 8:
        var rt:ResourceNode = world.add_node(&"tree", o + Vector2i(k * 2, 18));
        rainy.append(rt);
        fires.ignite(rt.cell);
    Weather.intensity = 0.15;
    fires._rain_on_fires();
    _expect("a drizzle does not put a fire out (%d of 8 still burning)" % fires.wild_cell_count(), fires.wild_cell_count() == 8);
    Weather.intensity = 1.0;
    for h in 5:
        fires.on_hour();
    var saved_trees:int = rainy.filter(func(rn:ResourceNode) -> bool: return not rn.removed).size();
    _expect("heavy rain puts them out within a few hours (%d burning, %d of 8 trees saved)" % [fires.wild_cell_count(), saved_trees], fires.wild_cell_count() == 0 and saved_trees >= 6);
    _expect("and the burnt-out ground is wet: it does not catch again at once", fires.is_soaked(rainy[0].cell) or rainy[0].removed);
    Weather.intensity = 0.0;
    # buildings: wooden burns down, stone survives, damage mends
    var wood_at:Vector2i = TestSite.spot(world, Vector2i(3, 3), o - TestSite.anchor(world) + Vector2i(0, 14));
    var wooden:Building = world.place_building(&"granary", wood_at, Vector2i(3, 3), true);
    var stone_at:Vector2i = TestSite.spot(world, Vector2i(3, 3), o - TestSite.anchor(world) + Vector2i(8, 14));
    var stone:Building = world.place_building(&"stone_house", stone_at, Vector2i(3, 3), true);
    _expect("a wooden store catches far more readily than a stone house", fires.flammability(wooden.rect().position)["catch"] > fires.flammability(stone.rect().position)["catch"] * 5.0);
    wooden.stored[&"wheat"] = 40;
    stone.residents.clear();
    _expect("a building ignites as a whole", fires.ignite(wooden.rect().position) and wooden.burning and fires.is_burning(wooden.rect().position + Vector2i(2, 2)));
    var name_before:String = wooden.name;
    for h in 8:
        fires.on_hour();
    _expect("the wooden building burns down and what was inside with it", not World.alive(wooden) and not world.buildings.has(wooden));
    for e in fires.cells.keys():
        fires.cells.erase(e);
    stone.burning = false;
    stone.health = 1.0;
    _expect("a stone house ignites too, with difficulty", fires.ignite(stone.rect().position));
    for h in 6:
        fires.on_hour();
    _expect("a stone house comes through scorched (%.2f, burning %s)" % [stone.health, stone.burning], World.alive(stone) and stone.health < 1.0 and stone.health > 0.7 and not stone.burning);
    var scorched:float = stone.health;
    stone.on_day();
    _expect("and mends a little each day", stone.health > scorched);
    _expect("damage is saved", stone.to_dict()["health"] == stone.health);
    # a field: a crop burns, the field stays
    var field_at:Vector2i = TestSite.spot(world, Vector2i(4, 4), o - TestSite.anchor(world) + Vector2i(14, 14));
    var field:Field = world.place_building(&"field", field_at, Vector2i(4, 4), true) as Field;
    world.seeds.unlock_all();
    field.set_crop(&"wheat");
    for i in field.plot_count():
        field.plot_state[i] = Field.Plot.PLANTED;
        field.plot_crop[i] = field.crop_id;
        field.growth[i] = 0.0;
        field.moisture[i] = 1.0;
    var crop_cell:Vector2i = field.plot_cell(5);
    _expect("a planted plot catches more readily than bare ground", fires.flammability(crop_cell)["catch"] > Fires.GRASS_CATCH);
    fires.ignite(crop_cell);
    for h in 4:
        fires.on_hour();
    _expect("the crop in a burned plot is dead, the field stands", field.plot_state[5] == Field.Plot.DEAD and World.alive(field));
    # citizens: flee, fight, and rare burns
    for e in fires.cells.keys():
        fires.cells.erase(e);
    var p:Pawn = world.pawns[0];
    var q:Pawn = world.pawns[1];
    p.clear_carry(); q.clear_carry();
    p.end_task(false); q.end_task(false);
    var spot:Vector2i = o + Vector2i(6, 3);
    p.position = world.terrain.cell_center(spot);
    q.position = world.terrain.cell_center(o + Vector2i(24, 3));
    var blaze:ResourceNode = world.add_node(&"tree", spot + Vector2i(2, 0));
    fires.ignite(blaze.cell);
    GameClock.set_speed(1);
    _expect("a citizen close to a fire wants to leave it", world.fire_tasks.wants(p) and fires.nearest_wild(p.cell(), Fires.FLEE_RADIUS) != Fires.NO_CELL);
    var flee:Task = world.fire_tasks.flee_task(p);
    _expect("and is given a place to run to, clear of the flames", flee != null and flee.kind == &"flee" and fires.nearest_wild(flee.steps[0]["cell"], Fires.FLEE_RADIUS) == Fires.NO_CELL);
    _expect("someone farther off is called to fight", world.fire_tasks.can_fight(q) and world.fire_tasks.wants(q));
    var fight:Task = world.fire_tasks.fight_task(q);
    _expect("a fighter with no bucket first fetches water (%s)" % (fight.label if fight != null else "none"), fight != null and fight.kind == &"fire" and fight.label == "Fetching water");
    q.bucket = true;
    var douse:Task = world.fire_tasks.fight_task(q);
    _expect("with a bucket they go for the flames", douse != null and douse.label == "Putting out the fire");
    _expect("only so many fight at once", fires.fighters.size() <= FireTasks.MAX_FIGHTERS);
    # burns are rare, and a burn counts as the cause of death
    p.health = 1.0;
    var hurt:int = 0;
    for h in 400:
        p.health = 1.0;
        p.position = world.terrain.cell_center(blaze.cell + Vector2i(1, 0));
        fires._hurt_citizens();
        if p.health < 1.0:
            hurt += 1;
    _expect("beside a fire a citizen is rarely burned (%d in 400 hours)" % hurt, hurt > 3 and hurt < 60);
    p.health = 0.2;
    p.burned_until = GameClock.total_hours + 5.0;
    _expect("death after a burn is put down to burns", p._death_cause() == "burns");
    # the rule: none means nothing starts or spreads
    GameRules.fires = 0;
    for e in fires.cells.keys():
        fires.cells.erase(e);
    var calm:ResourceNode = world.add_node(&"tree", o + Vector2i(4, 16));
    Weather.drought_days = 3;
    fires.strike(calm.cell);
    var struck:int = 0;
    for i in 100:
        fires.strike(calm.cell);
        if fires.is_burning(calm.cell):
            struck += 1;
    _expect("at None, lightning starts nothing", struck == 0);
    GameRules.fires = 2;
    Weather.drought_days = 3;
    for i in 200:
        fires.strike(calm.cell);
        if fires.is_burning(calm.cell):
            struck += 1;
            break;
    _expect("at Normal in a drought, lightning can", struck >= 1);
    for e in fires.cells.keys():
        (fires.cells[e] as Fires.FireCell).left = 0.0;
    Weather.drought_days = 0;
    # what a fire leaves behind: scorched ground that fades back, a pasture that loses animals
    for e in fires.cells.keys():
        fires.cells.erase(e);
    var burnt:ResourceNode = world.add_node(&"tree", o + Vector2i(6, 16));
    var burnt_cell:Vector2i = burnt.cell;
    fires.ignite(burnt_cell);
    for h in 6:
        fires.on_hour();
    _expect("a burnt tree leaves scorched ground", burnt.removed and fires.scorch.has(burnt_cell));
    var after:Array = fires.to_array();
    var kept:int = after.filter(func(e:Array) -> bool: return int(e[1]) < 0).size();
    fires.scorch.clear();
    fires.restore(after);
    _expect("the scorch is saved (%d cells)" % kept, kept >= 1 and fires.scorch.has(burnt_cell));
    GameClock.total_hours += (Fires.SCORCH_DAYS + 1.0) * GameClock.HOURS_PER_DAY;
    fires.on_hour();
    _expect("and it fades away after its days", not fires.scorch.has(burnt_cell));
    var pas_at:Vector2i = TestSite.spot(world, Vector2i(4, 4), o - TestSite.anchor(world) + Vector2i(18, 8));
    var pasture:Pasture = world.place_building(&"pasture", pas_at, Vector2i(4, 4), true) as Pasture;
    pasture.animals = 20;
    GameRules.fires = 4;
    Weather.drought_days = 3;
    var pasture_cell:Vector2i = pas_at + Vector2i(1, 1);
    _expect("a pasture's grass can burn", not fires.flammability(pasture_cell).is_empty() and fires.ignite(pasture_cell) and not pasture.burning);
    for h in 4:
        fires.on_hour();
    _expect("and the animals suffer (%d of 20 left), the pasture stands" % pasture.animals, pasture.animals < 20 and World.alive(pasture));
    Weather.drought_days = 0;
    for e in fires.cells.keys():
        fires.cells.erase(e);
    # citizens go round flames: a burning cell costs a lot to walk through
    var cold_cell:Vector2i = o + Vector2i(2, 17);
    var plain_w:float = world.nav.astar.get_point_weight_scale(cold_cell);
    var tree3:ResourceNode = world.add_node(&"tree", cold_cell);
    fires.ignite(tree3.cell);
    _expect("a burning cell is weighted so walkers avoid it (%.1f against %.1f)" % [world.nav.astar.get_point_weight_scale(cold_cell), plain_w], world.nav.astar.get_point_weight_scale(cold_cell) >= plain_w + Fires.NAV_WEIGHT - 0.001);
    fires.douse(cold_cell);
    _expect("and back to normal when it is out", world.nav.astar.get_point_weight_scale(cold_cell) < plain_w + 3.0);
    # repairs: builders mend scorched buildings, with no materials
    var scorched_at:Vector2i = TestSite.spot(world, Vector2i(3, 3), o - TestSite.anchor(world) + Vector2i(22, 14));
    var scorched_house:Building = world.place_building(&"stone_house", scorched_at, Vector2i(3, 3), true);
    scorched_house.health = 0.5;
    _expect("a scorched building wants repair, a whole one does not", scorched_house.needs_repair() and not stone.needs_repair() or stone.health >= Building.REPAIR_BELOW);
    var fixer:Pawn = world.pawns[2];
    fixer.clear_carry();
    fixer.end_task(false);
    var repair:Task = world.jobs._repair_task(fixer);
    _expect("a repair task is made for it", repair != null and repair.label.begins_with("Repairing"));
    var rounds:int = 0;
    while not scorched_house.repair_work(1.0) and rounds < 20:
        rounds += 1;
    _expect("it takes a few hours of work to make it whole (%d)" % rounds, rounds >= 2 and scorched_house.health >= 0.999);
    scorched_house.repairers = 0;
    # a fire lit in a wooden building very rarely gets out of it
    var hearth_at:Vector2i = TestSite.spot(world, Vector2i(3, 3), o - TestSite.anchor(world) + Vector2i(26, 14));
    var hearth:Building = world.place_building(&"house", hearth_at, Vector2i(3, 3), true);
    hearth.fuel = 20;
    hearth.residents.append(world.pawns[3]);
    Weather.temperature = 0.0;
    _expect("a house with its hearth lit counts as fired", hearth.is_burning());
    _expect("the real chance is small (%.5f an hour)" % fires.chimney_chance, fires.chimney_chance < 0.001);
    fires.chimney_chance = 0.05;
    GameRules.fires = 2;
    var started:int = 0;
    for i in 300:
        fires._chimney_fires();
        if hearth.burning:
            started += 1;
            fires._extinguish_building(hearth);
    GameRules.fires = 0;
    var none:int = 0;
    for i in 300:
        fires._chimney_fires();
        if hearth.burning:
            none += 1;
            fires._extinguish_building(hearth);
    GameRules.fires = 2;
    fires.chimney_chance = Fires.CHIMNEY_CHANCE;
    print("chimney fires in 300 hours at a chance of 0.05: %d at Normal, %d at None" % [started, none]);
    _expect("a house fire can start at Normal and never at None", started >= 3 and none == 0);
    hearth.residents.clear();
    # saving
    for e in fires.cells.keys():
        fires.cells.erase(e);
    var keep:ResourceNode = world.add_node(&"tree", o + Vector2i(18, 16));
    fires.ignite(keep.cell);
    fires.light_campfire(o + Vector2i(22, 17));
    var saved:Array = fires.to_array();
    var before:int = fires.cells.size();
    fires.cells.clear();
    fires.restore(saved);
    _expect("fires are saved and restored (%d cells)" % fires.cells.size(), fires.cells.size() == before and before >= 2 and keep.burning);
    # the Wildfires rule is saved
    GameRules.fires = 3;
    var rules:Dictionary = GameRules.to_dict();
    GameRules.reset();
    GameRules.from_dict(rules);
    _expect("the Wildfires level is saved", GameRules.fires == 3);
    GameRules.reset();
    print("FIRES %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
