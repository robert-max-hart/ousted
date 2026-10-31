# ----------------------------------------------------------------
# World
#     Root of the game scene. Builds the terrain, environment, camera,
#     UI and starting colony, and owns all entities plus the per-cell
#     occupancy used for placement and pathfinding.
# ----------------------------------------------------------------
class_name World extends Node3D;

static var instance:World = null;
static var pending_load:Dictionary = {};     # set by SaveGame before a World is created from a save
static var new_game_seed:int = 0;           # set by the title screen for the next new game (0 = random)
static var choose_start:bool = false;       # set by the title screen: the next new game waits for the player to place the Town Hall
static var backdrop:bool = false;           # the title screen builds a frozen mock town with no citizens, HUD or tools

# How fast particle effects (rain, snow, smoke) play: with the game's clock, except behind the title screen where the
# clock is stopped and they run at normal speed.
static func fx_speed() -> float:
    return 1.0 if instance != null and instance.is_backdrop else GameClock.speed()

const START_PAWNS       :int = 12;
const START_CHILDREN    :int = 3;                  # the last few of them are children (5 to 17)
const START_STOCK       :Dictionary = {&"wood": 40, &"stone": 20, &"iron": 4, &"wheat": 130, &"berries": 30, &"firewood": 30};
const START_PROFESSIONS :Array[int] = [
    JobManager.Profession.BUILDER, JobManager.Profession.BUILDER,
    JobManager.Profession.FARMER,
];
const RIVER_SOIL_BONUS :float = 0.2;                 # extra fertility right at the river, fading to nothing RIVER_NEAR cells out
const START_RIVER_AT    :float = 12.0;              # the start site is picked this far from the river (near enough to use it, far enough to build)
const SPARSE_FROM      :float = 0.7;               # lone trees use this slice of the cell's random roll (clear of the berry, rock, mushroom and hazel slices)
const SPARSE_TREES     :float = 0.04;              # share of the open ground near the groves that holds a lone tree
const START_ORE_MIN     :int = 2;                   # iron outcrops guaranteed in the ring START_ORE_NEAR..START_ORE_FAR cells from the start
const START_ORE_NEAR    :float = 14.0;
const START_ORE_FAR     :float = 30.0;
const START_ROCKS_MIN   :int = 5;                   # loose rocks guaranteed near the start (8 stone each), whatever the seed
const START_ROCKS_NEAR  :float = 10.0;              # ... in the ring this far from the start, no further than START_ROCKS_FAR
const START_ROCKS_FAR   :float = 22.0;
const START_ROCKS_CLOSE :int = 2;                   # ... and this many of them within START_ROCKS_CLOSE_FAR cells
const START_ROCKS_CLOSE_FAR:float = 16.0;
const MAX_BUILD_SLOPE   :float = Terrain.BUILD_SLOPE;
const MAX_WALK_SLOPE    :float = 2.2;

@export var world_seed:int = 0;     # 0 = random each run

var terrain     :Terrain;
var nav         :NavGrid;
var jobs        :JobManager;
var policies    :Policies = Policies.new();
var seeds       :Seeds = Seeds.new();       # the crops that can be sown (starting seeds come from the difficulty)
var ledger      :Ledger = Ledger.new();
var traders     :Traders;                  # merchant visits (needs a Trading Post)
var families    :Families;
var bodies      :Array[Body] = [];
var child_labor_share:float = 0.0;   # share of the children working right now (0 when the policy forbids it)
var _next_body_id:int = 1;
var visuals     :WorldVisuals;
var tools       :PlayerTools;
var hud         :HUD;
var camera_rig  :RTSCamera;
var renderer    :ResourceRenderer;
var rng         :RandomNumberGenerator = RandomNumberGenerator.new();
var is_backdrop :bool = false;      # this world is the title screen's picture

var buildings   :Array[Building] = [];
var pawns       :Array[Pawn] = [];
var nodes       :Array[ResourceNode] = [];
var piles       :Array[GroundPile] = [];
var occupant    :Array = [];        # Building per cell, or null
var node_at     :Array = [];        # ResourceNode per cell, or null
var soil_fertility:PackedFloat32Array;
var awaiting_start:bool = false;            # a new game before the Town Hall is placed: no colony yet, the clock stopped
var suggested_start:Vector2i = Vector2i.ZERO;   # where the game would have started the colony (the camera begins there)
var town_hall   :Building;
var scenario    :ScenarioRun;          # the scenario this game belongs to, if any
var start_building:Building;           # what the colony was founded with (the Town Hall, a well or a supply cart: GameRules.Start)

var _entities   :Node3D;
var wetness     :float = 0.5;       # 0..1 how wet the ground is (rain wets, warmth dries); trees grow on it
var saplings    :Array[ResourceNode] = [];
var road_work:Dictionary = {};              # cell -> work hours done: road cells staked out, waiting for builders and laborers
var road_claimed:Dictionary = {};           # cell -> true while a citizen is working on it (not saved)
var road_kind:Dictionary = {};              # cell -> Terrain.Overlay.ROAD or CHANNEL: what a staked or waiting cell becomes (missing: road)
var irrigation_version:int = 0;             # bumped when channels are dug, filled in or flow changes (fields re-check their plots)
var pending_roads:Dictionary = {};          # cell -> true: road cells waiting for a tree or rock to be cleared
var death_log   :Array = [];        # {name, age, cause, when, profession}, oldest first
var tree_orders :Dictionary = {};   # cell -> true: single trees the player asked for (the Plant tool), planted by laborers
var tree_claimed:Dictionary = {};   # ... the ones a laborer is on the way to
var _order_objects:Dictionary = {}; # cell -> the TreeOrder that stands for it when selected
var _order_marks:Dictionary = {};   # cell -> a stake standing where a tree will go
var planting    :Dictionary = {};   # cells a pawn is walking to plant a tree on
var _storage_warned:bool = false;
var _spoiled_today:int = 0;
var _spoiled_stored:Dictionary = {};        # item -> units that spoiled in storage today
var _spoiled_ground:Dictionary = {};        # item -> units that spoiled lying on the ground today

static func alive(o:Variant) -> bool:
    return o != null and is_instance_valid(o) and not o.removed;

func _ready() -> void:
    instance = self;
    is_backdrop = backdrop;
    var save:Dictionary = pending_load;
    pending_load = {};
    var loading:bool = not save.is_empty();
    if loading:
        world_seed = save["seed"];
        var map:Dictionary = save.get("map", {}) as Dictionary;       # older saves: a Large map with the winding river
        Terrain.set_size(map.get("size", Terrain.DEFAULT_SIZE));
        Terrain.river_style = map.get("river", Terrain.RiverStyle.WINDING);
        Climate.current = map.get("climate", Climate.Id.TEMPERATE);
        Terrain.hills_level = map.get("hills", Terrain.Hills.NORMAL);
        scenario = ScenarioRun.from_dict(save.get("scenario", {}) as Dictionary);
        GameRules.from_dict(save.get("rules", {}) as Dictionary);
    elif world_seed == 0:
        world_seed = new_game_seed if new_game_seed > 0 else randi() % 1000000;
        new_game_seed = 0;
    if not loading and not backdrop and Scenarios.pending != &"":
        scenario = ScenarioRun.new(Scenarios.pending);
    Scenarios.pending = &"";
    rng.seed = world_seed;
    print("Ousted world seed: %d" % world_seed);

    terrain = Terrain.new();
    terrain.soil_source = func(i:int) -> float: return soil_fertility[i];
    terrain.water_source = func(i:int) -> float: return water_reach()[i];
    terrain.name = "Terrain";
    add_child(terrain);
    terrain.generate(world_seed);
    if loading:
        terrain.heights = save["heights"];
        terrain.overlay = save["overlay"];
        terrain.mark_all_dirty();
    terrain.changed.connect(_on_terrain_changed);

    var n:int = Terrain.SIZE * Terrain.SIZE;
    occupant.resize(n);
    node_at.resize(n);
    _init_soil();
    nav = NavGrid.new();
    nav.setup(Terrain.SIZE);
    _refresh_nav_rect(Rect2i(0, 0, Terrain.SIZE, Terrain.SIZE));

    visuals = WorldVisuals.new(self);
    visuals.name = "Visuals";
    add_child(visuals);
    visuals.setup_environment();
    traders = Traders.new(self);
    _entities = Node3D.new();
    _entities.name = "Entities";
    add_child(_entities);
    renderer = ResourceRenderer.new();
    renderer.name = "Nature";
    add_child(renderer);
    add_child(RoadDetail.new(self));
    add_child(GrassDetail.new(self));
    jobs = JobManager.new(self);
    families = Families.new(self);
    policies.changed.connect(jobs.on_policy_changed);

    if loading:
        _restore_entities(save);
    else:
        _spawn_nature();
        var start:Vector2i = _find_start_cell();
        _clear_nodes(start, 13);
        if backdrop:
            TitleBackdrop.build(self, start);
            return;
        if choose_start:
            choose_start = false;
            awaiting_start = true;
            suggested_start = start;
            GameClock.locked = true;       # time stands still until the Town Hall is placed
            GameClock.set_speed(0);
        else:
            _found_colony(start);

    camera_rig = RTSCamera.new();
    camera_rig.name = "CameraRig";
    add_child(camera_rig);
    if loading:
        camera_rig.restore_state(save["camera"]);
    elif awaiting_start:
        camera_rig.focus_on(Vector3(suggested_start.x, 0.0, suggested_start.y));
        camera_rig._distance = 75.0;
        camera_rig._target_distance = 75.0;
    else:
        camera_rig.focus_on((start_building if start_building != null else town_hall).position);
    visuals.setup_weather_fx();

    tools = PlayerTools.new();
    tools.name = "Tools";
    add_child(tools);
    hud = HUD.new();
    hud.name = "HUD";
    add_child(hud);

    GameClock.hour_changed.connect(_on_hour);
    GameClock.day_changed.connect(_on_day);
    GameClock.season_changed.connect(_on_season);
    Weather.drought_changed.connect(_on_drought);
    _apply_season(GameClock.season());
    if awaiting_start:
        tools.begin_start_mode();
        notify("Choose where to settle: click to place your %s." % Defs.BUILDINGS[GameRules.start_def()]["name"]);
    else:
        notify("Game loaded." if loading else "Your settlers have arrived. Spring has begun.");

func idx(c:Vector2i) -> int:
    return c.y * Terrain.SIZE + c.x;

func notify(msg:String) -> void:
    ledger.record_event(msg);
    if hud != null:
        hud.notify(msg);
    else:
        print(msg);

# --------------------------------
# World generation

func _init_soil() -> void:
    var noise:FastNoiseLite = FastNoiseLite.new();
    noise.seed = world_seed + 7;
    noise.frequency = 0.03;
    soil_fertility.resize(Terrain.SIZE * Terrain.SIZE);
    for z in Terrain.SIZE:
        for x in Terrain.SIZE:
            var valley:float = 1.0 - clampf(terrain.river_distance(Vector2i(x, z)) / Terrain.RIVER_NEAR, 0.0, 1.0);       # the river's valley is richer soil
            soil_fertility[z * Terrain.SIZE + x] = clampf(0.7 + noise.get_noise_2d(x, z) * 0.5 + valley * RIVER_SOIL_BONUS, 0.2, 1.0);

func _spawn_nature() -> void:
    var forest:FastNoiseLite = FastNoiseLite.new();
    forest.seed = world_seed + 3;
    forest.frequency = 0.025;
    var species:FastNoiseLite = FastNoiseLite.new();
    species.seed = world_seed + 11;
    species.frequency = 0.045;
    var trees:float = float(Climate.data()["trees"]);       # a dry climate has thin woods, a wet one thick
    for z in Terrain.SIZE:
        for x in Terrain.SIZE:
            var c:Vector2i = Vector2i(x, z);
            if terrain.is_water(c) or terrain.cell_height(c) < Terrain.WATER_LEVEL + 0.4:
                continue;
            var slope:float = terrain.cell_slope(c);
            var f:float = forest.get_noise_2d(x, z);
            var r:float = rng.randf();
            if slope > 1.0 and r < 0.09:
                add_node(&"ore" if rng.randf() < 0.12 else &"rock", c);       # (the ore share dropped as the rocks grew: iron is unchanged)
            elif slope < 1.4 and f > 0.15 and r < 0.45 * trees:
                var oak:float = species.get_noise_2d(x, z) + rng.randf_range(-0.25, 0.25);       # patches of oak among the pines
                add_node(&"oak" if oak > 0.05 else &"tree", c);
            elif slope < 1.0 and f > -0.1 and f < 0.15 and r < 0.025:
                add_node(&"bush", c);
            elif slope < 1.4 and f > -0.35 and f <= 0.15 and r > SPARSE_FROM and r < SPARSE_FROM + (SPARSE_TREES if f > -0.1 else SPARSE_TREES * 0.55) * trees:
                var kind:float = species.get_noise_2d(x, z) + rng.randf_range(-0.25, 0.25);        # a lone tree here and there, thicker towards the groves
                add_node(&"oak" if kind > 0.05 else &"tree", c);
            elif slope < 1.0 and r < 0.008:
                add_node(&"rock", c);             # loose surface stone on open ground (twice what it was originally)
            elif slope < 1.0 and f > 0.1 and f < 0.4 and r > 0.45 and r < 0.485:
                add_node(&"mushroom", c);         # damp patches among the trees
            elif slope < 1.0 and f > -0.3 and f <= -0.1 and r > 0.6 and r < 0.64:
                add_node(&"hazel", c);            # groves on the open ground beside the woods
    renderer.mark_dirty();

# Picks the flattest dry spot nearest the map center.














# --------------------------------
# Save and load (see SaveGame)



# --------------------------------
# Resource nodes

func add_node(kind:StringName, c:Vector2i) -> ResourceNode:
    var rn:ResourceNode = ResourceNode.new(kind, c, rng);
    nodes.append(rn);
    node_at[idx(c)] = rn;
    _refresh_nav(c);
    renderer.mark_dirty();
    return rn;

# A new patch of wild food: it starts with nothing picked yet to give (it fruits in its season).
func sow_wild(kind:StringName, c:Vector2i) -> ResourceNode:
    var rn:ResourceNode = add_node(kind, c);
    rn.amount = 0;
    return rn;

# Plants a new tree that grows up over time. Returns it, or null if the cell is not usable.
func plant_tree(c:Vector2i) -> ResourceNode:
    if not can_plant_tree(c):
        return null;
    var rn:ResourceNode = add_node(&"oak" if rng.randf() < 0.35 else &"tree", c);
    rn.make_sapling();
    saplings.append(rn);
    return rn;






# Free, dry, gentle ground that is not road or field, and not touching another tree.
# spacing: how many cells of clear ground a new tree needs on every side (0 lets trees stand shoulder to shoulder).
func can_plant_tree(c:Vector2i, spacing:int = 1) -> bool:
    if not terrain.in_bounds(c) or terrain.is_water(c) or terrain.cell_height(c) < Terrain.WATER_LEVEL + 0.4:
        return false;
    if occupant[idx(c)] != null or node_at[idx(c)] != null or terrain.get_overlay(c) != Terrain.Overlay.NONE:
        return false;
    if terrain.cell_slope(c) > 1.2 or planting.has(c) or tree_orders.has(c):
        return false;
    for dz in range(-spacing, spacing + 1):
        for dx in range(-spacing, spacing + 1):
            var n:Vector2i = c + Vector2i(dx, dz);
            if terrain.in_bounds(n) and node_at[idx(n)] != null and (node_at[idx(n)] as ResourceNode).is_tree():
                return false;
    return true;

func near_water(c:Vector2i, r:int = 4) -> bool:
    for dz in range(-r, r + 1):
        for dx in range(-r, r + 1):
            var n:Vector2i = c + Vector2i(dx, dz);
            if terrain.in_bounds(n) and terrain.is_water(n):
                return true;
    return false;

# Growth per hour as a fraction of full growth. Year-round, but slow in winter, and far less
# fussy about water than crops: dry ground still allows about a third of the pace.
func tree_growth_rate(rn:ResourceNode) -> float:
    var base:float = 1.0 / rn.def["grow_hours"];
    var season:float = 0.25 if Climate.is_dormant() else 1.0;
    var water:float = maxf(wetness, 0.8 if near_water(rn.cell) else 0.0);
    return base * season * (0.35 + 0.65 * water);

func _grow_trees() -> void:
    if saplings.is_empty():
        return;
    for rn in saplings.duplicate():
        if rn.removed:
            saplings.erase(rn);
            continue;
        rn.set_growth(rn.growth + tree_growth_rate(rn));
        if rn.is_mature():
            saplings.erase(rn);
    renderer.mark_dirty();

func _on_drought(on:bool) -> void:
    if is_backdrop:
        return;
    notify("A drought begins: no rain, and the ground dries fast. Fields away from water need watering." if on else "The drought has broken.");

func _update_wetness() -> void:
    wetness += 0.03 * Weather.intensity;
    wetness -= (0.004 + maxf(0.0, Weather.temperature) * 0.0003) * (1.0 - Weather.intensity) * Weather.drying();
    wetness = clampf(wetness, 0.0, 1.0);

func remove_node(rn:ResourceNode) -> void:
    if rn.removed:
        return;
    rn.removed = true;
    saplings.erase(rn);
    nodes.erase(rn);
    node_at[idx(rn.cell)] = null;
    _refresh_nav(rn.cell);
    renderer.mark_dirty();
    if pending_roads.erase(rn.cell):
        stake_road(rn.cell);

func node_changed(_rn:ResourceNode) -> void:
    renderer.mark_dirty();

func set_designated(rn:ResourceNode, on:bool) -> void:
    if not on:
        rn.clearing = false;
    if rn.designated != on:
        rn.designated = on;
        renderer.mark_dirty();

# Marks something in the way of a building or road: laborers clear it (a bush too, even though it would regrow).
func mark_for_clearing(rn:ResourceNode) -> void:
    rn.clearing = true;
    set_designated(rn, true);

# --------------------------------
# Buildings

# Returns "" when placement is allowed, otherwise a reason.
# relocating: the building is being moved, so a unique one may be placed again.
func can_place(def_id:StringName, origin:Vector2i, size:Vector2i, relocating:bool = false, facing:int = 0) -> String:
    var r:Rect2i = Rect2i(origin, size);
    if Defs.BUILDINGS[def_id].get("unique", false) and not relocating:
        for b in buildings:
            if b.def_id == def_id:
                return "There is only one %s" % Defs.BUILDINGS[def_id]["name"];
    if Defs.BUILDINGS[def_id].get("orchard", false) and not seeds.knows_trees():
        return "No saplings yet: foragers may find some";
    if not Rect2i(0, 0, Terrain.SIZE, Terrain.SIZE).encloses(r):
        return "Out of bounds";
    var bridge:bool = Defs.BUILDINGS[def_id].get("bridge", false);
    var fishing:bool = Defs.BUILDINGS[def_id].get("fishing", false);       # goes partly over the water, like a bridge
    var wet:int = 0;
    var dry:int = 0;
    for z in range(r.position.y, r.end.y):
        for x in range(r.position.x, r.end.x):
            var c:Vector2i = Vector2i(x, z);
            if terrain.is_water(c):
                if not bridge and not fishing:
                    return "Can't build on water";
                wet += 1;
            else:
                dry += 1;
                if fishing and terrain.cell_slope(c) > 1.3:
                    return "The shore is too steep here";
            if occupant[idx(c)] != null:
                return "Something is already built here";
            if terrain.get_overlay(c) == Terrain.Overlay.ROAD:
                return "A road is in the way";
            if terrain.get_overlay(c) == Terrain.Overlay.CHANNEL or terrain.get_overlay(c) == Terrain.Overlay.CHANNEL_WET:
                return "A channel is in the way";
    if bridge:
        return "" if wet > 0 else "A bridge has to cross water";
    if fishing:
        var pier:Rect2i = Building.pier_rect_for(Defs.BUILDINGS[def_id], origin, size, facing);
        var pier_wet:int = 0;
        for z in range(pier.position.y, pier.end.y):
            for x in range(pier.position.x, pier.end.x):
                if terrain.is_water(Vector2i(x, z)):
                    pier_wet += 1;
        if pier_wet * 3 < pier.size.x * pier.size.y * 2:
            return "The pier (the back, away from the door) has to run out over the water: turn it with R";
        return "" if dry * 3 >= size.x * size.y else "The door end of a fishing hut needs ground on the shore";
    var hr:Vector2 = terrain.rect_height_range(r);
    var limit:float = MAX_BUILD_SLOPE * (2.0 if Defs.BUILDINGS[def_id].get("drag_size", false) else 1.0);
    if hr.y - hr.x > limit:
        return "Ground is too steep (flatten it first)";
    return "";

# restoring: put a saved building back as it was (no flattening, clearing or overlay changes).
func place_building(def_id:StringName, origin:Vector2i, size:Vector2i, prebuilt:bool = false, restoring:bool = false, facing:int = 0) -> Building:
    var def:Dictionary = Defs.BUILDINGS[def_id];
    var r:Rect2i = Rect2i(origin, size);
    var is_field:bool = def.get("field", false);
    var is_ground:bool = is_field or def.get("graveyard", false) or def.get("pasture", false);       # drawn as a terrain overlay: bare while it goes up
    if (not def.get("drag_size", false) or def.get("flatten", false)) and not def.get("no_flatten", false) and not restoring:
        terrain.flatten_rect(r);
    var b:Building = Field.new() if is_field else Graveyard.new() if def.get("graveyard", false) else Pasture.new() if def.get("pasture", false) else TradingPost.new() if def.get("trade_post", false) else Apiary.new() if def.get("apiary", false) else FishingHut.new() if def.get("fishing", false) else Building.new();
    for z in range(r.position.y, r.end.y):
        for x in range(r.position.x, r.end.x):
            var c:Vector2i = Vector2i(x, z);
            occupant[idx(c)] = b;
            if restoring:
                continue;
            terrain.set_overlay(c, Terrain.Overlay.SITE if is_ground and not prebuilt else Terrain.Overlay.NONE);       # bare staked ground until it is done
            var rn:ResourceNode = node_at[idx(c)];
            if rn != null:
                mark_for_clearing(rn);       # nothing vanishes at once: laborers clear it before building starts
    b.facing = facing;
    b.setup(self, def_id, origin, size);
    _entities.add_child(b);
    buildings.append(b);
    _refresh_nav_rect(r);
    if prebuilt:
        b.complete();
    return b;

func remove_building(b:Building, refund:bool) -> void:
    if b.is_storage() and not b.is_empty():
        notify("%s can't be demolished until it is empty." % b.display_name());
        return;
    if b is Graveyard and (b as Graveyard).used_slots() > 0:
        notify("%s can't be demolished while it has graves in it." % b.display_name());
        return;
    if b is TradingPost:
        (b as TradingPost).dump_goods();
    if b.fuel > 0:
        deposit(&"firewood", b.fuel, b.position);
    for item in b.inputs:
        if b.inputs[item] > 0:
            deposit(item, b.inputs[item], b.position);
    if refund and not b.def.get("no_refund", false):
        var share:float = 1.0 if not b.is_complete() else 0.5;
        var all:Dictionary = b.all_delivered();
        for item in all:
            deposit(item, floori(all[item] * share), b.position);
    for p in b.residents:
        p.home = null;
    # cancel work aimed at it now, while task callbacks can still see it
    release_site_workers(b);
    var r:Rect2i = b.footprint();
    for z in range(r.position.y, r.end.y):
        for x in range(r.position.x, r.end.x):
            occupant[idx(Vector2i(x, z))] = null;
            if b is Field or b is Graveyard or b is Pasture:
                terrain.set_overlay(Vector2i(x, z), Terrain.Overlay.NONE);
    b.removed = true;
    if tools != null and tools.selected == b:
        tools.select(null);       # the inspector must not be left holding a freed building
    buildings.erase(b);
    if b.def.get("water", false):
        water_sources_changed();
    if b == town_hall:
        town_hall = null;
        notify("The Town Hall is gone. Build a new one from the menu.");
    if b.relocating_to != null and alive(b.relocating_to):
        b.relocating_to.relocating_from = null;      # the new site stands on its own, still at the moving price
    if b.relocating_from != null and alive(b.relocating_from):
        b.relocating_from.relocating_to = null;
    _refresh_nav_rect(r);
    b.queue_free();
    families.assign_homes();

# Ends every citizen's task aimed at (or working for) b: cancelled hauls hand their goods back, builders walk off.
func release_site_workers(b:Building) -> void:
    for p in pawns:
        if p.task != null and (is_same(p.task.target, b) or is_same(p.task.workplace, b) or is_same(p.task.related, b)):
            p.end_task(false);

func is_site_clear(b:Building) -> bool:
    return _rect_free_of_nodes(b.rect());

func _rect_free_of_nodes(r:Rect2i) -> bool:
    for z in range(r.position.y, r.end.y):
        for x in range(r.position.x, r.end.x):
            if node_at[idx(Vector2i(x, z))] != null:
                return false;
    return true;

# --------------------------------
# Town Hall features, relocation

# Whether the Town Hall's governance upgrade is built (it unlocks the Policies panel).
func has_governance() -> bool:
    return alive(town_hall) and town_hall.is_complete() and town_hall.has_upgrade(&"governance");

# Why this building can't be moved right now, or "" when it can.
# --------------------------------
# Water reach (the Water overlay)

var _water_reach:PackedFloat32Array = PackedFloat32Array();
var _water_reach_dirty:bool = true;



# A bridge deck stands on this cell (walkers cross the water on it).
func is_bridge(c:Vector2i) -> bool:
    var b:Building = occupant[idx(c)] if terrain.in_bounds(c) else null;
    if b == null:
        return false;
    return b.def.get("bridge", false) or b.deck_has(c);       # (a fishing hut's pier is a deck too)

# The height citizens stand at on this spot: the ground, or the deck of a bridge over water.
func stand_y(x:float, z:float) -> float:
    var y:float = terrain.height_at(x, z);
    if y < Terrain.WATER_LEVEL + Building.DECK_HEIGHT and is_bridge(Vector2i(int(x), int(z))):
        return Terrain.WATER_LEVEL + Building.DECK_HEIGHT;
    return y;




func on_building_completed(b:Building) -> void:
    if b.def.get("water", false):
        water_sources_changed();
    if b is Graveyard:
        for z in range(b.origin.y, b.origin.y + b.size.y):
            for x in range(b.origin.x, b.origin.x + b.size.x):
                terrain.set_overlay(Vector2i(x, z), Terrain.Overlay.GRAVE);
    if b is Pasture:
        for z in range(b.origin.y, b.origin.y + b.size.y):
            for x in range(b.origin.x, b.origin.x + b.size.x):
                terrain.set_overlay(Vector2i(x, z), Terrain.Overlay.ORCHARD);
    if b is Field:
        for z in range(b.origin.y, b.origin.y + b.size.y):
            for x in range(b.origin.x, b.origin.x + b.size.x):
                terrain.set_overlay(Vector2i(x, z), Terrain.Overlay.ORCHARD if (b as Field).is_orchard() else Terrain.Overlay.TILLED);
    if b.def_id == &"town_hall" and town_hall == null:
        town_hall = b;
    if b.relocating_from != null and alive(b.relocating_from):
        _finish_relocation(b);
    if b.def.has("beds"):
        families.assign_homes();
    if hud != null:
        notify("%s completed." % b.display_name());

func nearest_building(pos:Vector3, pred:Callable) -> Building:
    var best:Building = null;
    var best_d:float = INF;
    for b in buildings:
        if not pred.call(b):
            continue;
        var c:Vector2 = Vector2(b.origin) + Vector2(b.size) * 0.5;
        var d:float = c.distance_squared_to(Vector2(pos.x, pos.z));
        if d < best_d:
            best = b;
            best_d = d;
    return best;

# Nearest storage building holding at least one unpromised unit of the item.
func nearest_storage_with(item:StringName, pos:Vector3) -> Building:
    return nearest_building(pos, func(b:Building) -> bool:
        return b.is_storage() and b.available(item) > 0);

# Nearest storage building that would accept the item and has room for it.
# Distance still counts, but a store that suits the item (a Granary for food) beats a nearer general one
# (Building.storage_rank, each point worth STORAGE_RANK_CELLS cells of walking).
const STORAGE_RANK_CELLS:float = 3.0;

# Merchants are drawn with the other entities.
func add_merchant(m:Merchant) -> void:
    _entities.add_child(m);

func nearest_storage_for(item:StringName, pos:Vector3) -> Building:
    var best:Building = null;
    var best_score:float = INF;
    for b in buildings:
        if not b.can_store(item):
            continue;
        var c:Vector2 = Vector2(b.origin) + Vector2(b.size) * 0.5;
        var score:float = c.distance_to(Vector2(pos.x, pos.z)) + b.storage_rank(item) * STORAGE_RANK_CELLS;
        if score < best_score:
            best = b;
            best_score = score;
    return best;

# Puts n units into the nearest storage with room, spilling to further ones and finally onto
# the ground near pos. Returns how many ended up in storage.
func deposit(item:StringName, n:int, pos:Vector3) -> int:
    var left:int = n;
    while left > 0:
        var b:Building = nearest_storage_for(item, pos);
        if b == null:
            break;
        left -= b.store(item, left);
    if left > 0:
        drop_pile(item, left, terrain.world_to_cell(pos));
    return n - left;

# Where to go to warm up: a heated home, else the nearest heated shelter, else any shelter.
func warm_shelter_for(p:Pawn) -> Building:
    if alive(p.home) and p.home.is_complete() and p.home.is_heated():
        return p.home;
    var heated:Building = nearest_building(p.position, func(b:Building) -> bool:
        return b.is_complete() and b.is_heated());
    return heated if heated != null else shelter_for(p);

# Where this citizen sleeps: their own home, if it is built; otherwise nowhere (the Town Hall shelters no one).
func shelter_for(p:Pawn) -> Building:
    if alive(p.home) and p.home.is_complete():
        return p.home;
    return null;

# --------------------------------
# Ground piles




# --------------------------------
# Roads







# --------------------------------
# Irrigation: a dug channel that connects (cell to cell, not diagonally) to water carries it; plots near such a
# channel stay moist (Field).





# --------------------------------
# Pawns

# at_home: a natural death (old age) happens in bed when the citizen has a home.

# --------------------------------
# Navigation

func _refresh_nav_rect(r:Rect2i) -> void:
    r = r.intersection(Rect2i(0, 0, Terrain.SIZE, Terrain.SIZE));
    for z in range(r.position.y, r.end.y):
        for x in range(r.position.x, r.end.x):
            _refresh_nav(Vector2i(x, z));

func _refresh_nav(c:Vector2i) -> void:
    var i:int = idx(c);
    var solid:bool = (terrain.is_water(c) and not terrain.is_shallow(c)) or terrain.cell_slope(c) > MAX_WALK_SLOPE;
    var weight:float = 3.0 if terrain.is_water(c) else 1.0;       # wading is slow: a detour is cheaper than a short ford
    var b:Building = occupant[i];
    if b != null and is_bridge(c):
        solid = false;          # a deck (a bridge, or a fishing hut's pier; the stakes of one too) carries walkers over the water
        weight = 0.8;
    elif b != null and not b.is_walkable():
        solid = true;
    var rn:ResourceNode = node_at[i];
    if rn != null:
        if rn.solid:
            solid = true;
        else:
            weight = 1.6;
    if terrain.overlay[i] == Terrain.Overlay.ROAD:
        weight = 0.6;
    nav.set_cell(c, solid, weight);

# Cells a pawn can stand on to work a rect: the ring around it, plus the
# inside when it is walkable.
func access_cells(r:Rect2i, inside_ok:bool) -> Array[Vector2i]:
    var out:Array[Vector2i] = [];
    var outer:Rect2i = r.grow(1);
    for z in range(outer.position.y, outer.end.y):
        for x in range(outer.position.x, outer.end.x):
            var c:Vector2i = Vector2i(x, z);
            if not inside_ok and r.has_point(c):
                continue;
            if nav.is_walkable(c):
                out.append(c);
    return out;

func access_cells_for_cell(c:Vector2i) -> Array[Vector2i]:
    if nav.is_walkable(c):
        return [c];
    return access_cells(Rect2i(c, Vector2i.ONE), false);

# Terraform tools must not move ground under buildings.
func is_corner_locked(x:int, z:int) -> bool:
    for dz in [-1, 0]:
        for dx in [-1, 0]:
            var c:Vector2i = Vector2i(x + dx, z + dz);
            if terrain.in_bounds(c) and occupant[idx(c)] != null:
                return true;
    return false;

func _on_terrain_changed(r:Rect2i) -> void:
    _refresh_nav_rect(r);
    renderer.mark_dirty();
    visuals.rebuild_water();
    for b in buildings:
        if b.rect().intersects(r):
            b.on_terrain_changed();

# --------------------------------
# Time

func _on_hour(_h:int) -> void:
    jobs.reconcile();
    families.on_hour();
    for b in buildings.duplicate():
        if b.def.get("temporary", false) and b.is_complete() and b.is_empty():
            remove_building(b, false);      # the supply cart, once emptied
    _update_child_labor();
    for b in bodies.duplicate():
        if b.expired():
            remove_body(b);
    for b in buildings:
        b.on_hour();
        if b.is_storage():
            _spoiled_today += b.spoil_tick(1.0, _spoiled_stored);
    for pl in piles.duplicate():
        _spoiled_today += pl.spoil_tick(1.0, _spoiled_ground);
        if pl.amount <= 0 and not pl.removed and pl.reserved_by == null:
            remove_pile(pl);
            pl.queue_free();
    _update_wetness();
    _grow_trees();
    _check_storage_full();

# "Spoiled yesterday: 9 berries, 4 lettuce (3 berries were lying on the ground)", the biggest losses first.
func _spoilage_report() -> String:
    var total:Dictionary = _spoiled_stored.duplicate();
    for item in _spoiled_ground:
        total[item] = total.get(item, 0) + _spoiled_ground[item];
    var items:Array = total.keys();
    items.sort_custom(func(a:StringName, b:StringName) -> bool: return total[a] > total[b]);
    var parts:PackedStringArray = [];
    for item in items:
        parts.append("%d %s" % [total[item], Defs.item_name(item).to_lower()]);
    var s:String = "Spoiled yesterday: %s" % ", ".join(parts);
    if not _spoiled_ground.is_empty():
        var ground:PackedStringArray = [];
        for item in _spoiled_ground:
            ground.append("%d %s" % [_spoiled_ground[item], Defs.item_name(item).to_lower()]);
        s += " (on the ground: %s)" % ", ".join(ground);
    return s + ".";

# Warns once when all storage fills up; re-arms after it drops below 90%.
func _check_storage_full() -> void:
    var cap:int = Stock.capacity();
    if cap <= 0:
        return;
    if Stock.used() >= cap:
        if not _storage_warned:
            _storage_warned = true;
            notify("Storage is full. Build more storage or workers will stop gathering.");
    elif Stock.used() < cap * 0.9:
        _storage_warned = false;

func _update_child_labor() -> void:
    var kids:int = 0;
    var working:int = 0;
    for p in pawns:
        if p.is_child():
            kids += 1;
            if p.is_laboring():
                working += 1;
    child_labor_share = float(working) / kids if kids > 0 and policies.is_on(&"child_labor") else 0.0;

func _on_day(_d:int) -> void:
    if scenario != null:
        scenario.on_day(self);
    renderer.update_foliage();
    traders.on_day();
    ledger.on_day(self);
    for b in buildings:
        b.on_day();
    families.on_day();
    if _spoiled_today >= 5:
        notify(_spoilage_report());
    _spoiled_today = 0;
    _spoiled_stored.clear();
    _spoiled_ground.clear();
    var s:int = GameClock.season();
    var day:int = GameClock.day_index();
    var regrown:bool = false;
    for rn in nodes:
        if rn.regrows and rn.amount < rn.max_amount and (rn.def["fruit_seasons"] as Array).has(s) and day % rn.def["regrow_days"] == 0:
            rn.amount += 1;
            regrown = true;
    WildGrowth.spread_daily(self);
    if regrown:
        renderer.mark_dirty();

func _apply_season(s:int) -> void:
    renderer.update_foliage();
    terrain.set_season(Climate.look(s));
    renderer.set_season(Climate.look(s));

func _on_season(s:int) -> void:
    _apply_season(s);
    if GameClock.total_hours > GameClock.START_HOUR + 1.0:
        notify("%s has arrived." % GameClock.SEASON_NAMES[s]);
        SaveGame.autosave(self);

# --------------------------------
# Delegates: the work lives in StartSite, WorldSave, RoadWork, WaterReach, TreeOrders and GroundPiles

func _find_start_cell() -> Vector2i:
    return StartSite._find_start_cell(self);

func _ensure_start_rocks(start:Vector2i) -> void:
    StartSite._ensure_start_rocks(self, start);

func _top_up(kind:StringName, start:Vector2i, near:float, far:float, minimum:int) -> void:
    StartSite._top_up(self, kind, start, near, far, minimum);

func _found_colony(start:Vector2i) -> void:
    StartSite._found_colony(self, start);

func begin_colony(origin:Vector2i) -> String:
    return StartSite.begin_colony(self, origin);

func _ensure_start_ore(start:Vector2i) -> void:
    StartSite._ensure_start_ore(self, start);

func _clear_nodes(c:Vector2i, radius:int) -> void:
    StartSite._clear_nodes(self, c, radius);

func _start_colony_goods(start:Vector2i) -> void:
    StartSite._start_colony_goods(self, start);

func _spawn_settlers(start:Vector2i) -> void:
    StartSite._spawn_settlers(self, start);

func serialize() -> Dictionary:
    return WorldSave.serialize(self);

func _restore_entities(save:Dictionary) -> void:
    WorldSave._restore_entities(self, save);

func can_road(c:Vector2i) -> bool:
    return RoadWork.can_road(self, c);

func can_plan_road(c:Vector2i) -> bool:
    return RoadWork.can_plan_road(self, c);

func plan_road(c:Vector2i, kind:int = Terrain.Overlay.ROAD) -> bool:
    return RoadWork.plan_road(self, c, kind);

func stake_road(c:Vector2i) -> void:
    RoadWork.stake_road(self, c);

func cancel_road(c:Vector2i) -> void:
    RoadWork.cancel_road(self, c);

func work_road(c:Vector2i, dh:float) -> bool:
    return RoadWork.work_road(self, c, dh);

func is_channel(c:Vector2i) -> bool:
    return RoadWork.is_channel(self, c);

func remove_channel(c:Vector2i) -> void:
    RoadWork.remove_channel(self, c);

func update_irrigation() -> void:
    RoadWork.update_irrigation(self);

func set_road(c:Vector2i, on:bool) -> void:
    RoadWork.set_road(self, c, on);

func water_reach() -> PackedFloat32Array:
    return WaterReach.water_reach(self);

func water_sources_changed() -> void:
    WaterReach.water_sources_changed(self);

func order_tree(c:Vector2i) -> bool:
    return TreeOrders.order_tree(self, c);

func tree_order_at(c:Vector2i) -> TreeOrder:
    return TreeOrders.tree_order_at(self, c);

func cancel_tree_order(c:Vector2i) -> void:
    TreeOrders.cancel_tree_order(self, c);

func _add_order_mark(c:Vector2i) -> void:
    TreeOrders._add_order_mark(self, c);

func _remove_order_mark(c:Vector2i) -> void:
    TreeOrders._remove_order_mark(self, c);

func relocation_block_reason(b:Building) -> String:
    return Relocation.relocation_block_reason(self, b);

func relocate(b:Building, origin:Vector2i, size:Vector2i, facing:int = 0) -> Building:
    return Relocation.relocate(self, b, origin, size, facing);

func _finish_relocation(site:Building) -> void:
    Relocation._finish_relocation(self, site);

func leave_colony(p:Pawn) -> void:
    Citizens.leave_colony(self, p);

func _end_tasks_aimed_at(p:Pawn) -> void:
    Citizens._end_tasks_aimed_at(self, p);

func add_body(p:Pawn, cause:String, at:Vector3) -> Body:
    return Citizens.add_body(self, p, cause, at);

func remove_body(b:Body) -> void:
    Citizens.remove_body(self, b);

func add_pawn(p:Pawn) -> void:
    Citizens.add_pawn(self, p);

func kill_pawn(p:Pawn, cause:String, at_home:bool = false) -> void:
    Citizens.kill_pawn(self, p, cause, at_home);

func pile_at(c:Vector2i) -> GroundPile:
    return GroundPiles.pile_at(self, c);

func drop_pile(item:StringName, n:int, near:Vector2i) -> void:
    GroundPiles.drop_pile(self, item, n, near);

func remove_pile(pl:GroundPile) -> void:
    GroundPiles.remove_pile(self, pl);
