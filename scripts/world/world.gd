# ----------------------------------------------------------------
# World
#     Root of the game scene. Builds the terrain, environment, camera,
#     UI and starting colony, and owns all entities plus the per-cell
#     occupancy used for placement and pathfinding.
# ----------------------------------------------------------------
class_name World extends Node3D;

static var instance:World = null;
static var pending_load:Dictionary = {};     # set by SaveGame before a World is created from a save

const START_PAWNS       :int = 6;
const START_STOCK       :Dictionary = {&"wood": 40, &"stone": 20, &"iron": 4, &"wheat": 130, &"berries": 30, &"firewood": 30};
const START_PROFESSIONS :Array[int] = [
    JobManager.Profession.BUILDER, JobManager.Profession.BUILDER,
    JobManager.Profession.FARMER, JobManager.Profession.GATHERER,
];
const MAX_BUILD_SLOPE   :float = 2.5;
const MAX_WALK_SLOPE    :float = 2.2;

@export var world_seed:int = 0;     # 0 = random each run

var terrain     :Terrain;
var nav         :NavGrid;
var jobs        :JobManager;
var policies    :Policies = Policies.new();
var ledger      :Ledger = Ledger.new();
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

var buildings   :Array[Building] = [];
var pawns       :Array[Pawn] = [];
var nodes       :Array[ResourceNode] = [];
var piles       :Array[GroundPile] = [];
var occupant    :Array = [];        # Building per cell, or null
var node_at     :Array = [];        # ResourceNode per cell, or null
var soil_fertility:PackedFloat32Array;
var town_hall   :Building;

var _entities   :Node3D;
var wetness     :float = 0.5;       # 0..1 how wet the ground is (rain wets, warmth dries); trees grow on it
var saplings    :Array[ResourceNode] = [];
var death_log   :Array = [];        # {name, age, cause, when, profession}, oldest first
var planting    :Dictionary = {};   # cells a pawn is walking to plant a tree on
var _storage_warned:bool = false;
var _spoiled_today:int = 0;

static func alive(o:Variant) -> bool:
    return o != null and is_instance_valid(o) and not o.removed;

func _ready() -> void:
    instance = self;
    var save:Dictionary = pending_load;
    pending_load = {};
    var loading:bool = not save.is_empty();
    if loading:
        world_seed = save["seed"];
    elif world_seed == 0:
        world_seed = randi() % 1000000;
    rng.seed = world_seed;
    print("Ousted world seed: %d" % world_seed);

    terrain = Terrain.new();
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
    _entities = Node3D.new();
    _entities.name = "Entities";
    add_child(_entities);
    renderer = ResourceRenderer.new();
    renderer.name = "Nature";
    add_child(renderer);
    jobs = JobManager.new(self);
    families = Families.new(self);
    policies.changed.connect(jobs.on_policy_changed);

    if loading:
        _restore_entities(save);
    else:
        _spawn_nature();
        var start:Vector2i = _find_start_cell();
        _clear_nodes(start, 10);
        town_hall = place_building(&"town_hall", start - Vector2i(2, 2), Vector2i(4, 4), true);
        _start_colony_goods(start);
        Defs.ageing_days_per_year = 4.0;
        _spawn_settlers(start);
        jobs.sync_targets();

    camera_rig = RTSCamera.new();
    camera_rig.name = "CameraRig";
    add_child(camera_rig);
    if loading:
        camera_rig.restore_state(save["camera"]);
    else:
        camera_rig.focus_on(town_hall.position);
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
    _apply_season(GameClock.season());
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
            soil_fertility[z * Terrain.SIZE + x] = clampf(0.7 + noise.get_noise_2d(x, z) * 0.5, 0.2, 1.0);

func _spawn_nature() -> void:
    var forest:FastNoiseLite = FastNoiseLite.new();
    forest.seed = world_seed + 3;
    forest.frequency = 0.025;
    for z in Terrain.SIZE:
        for x in Terrain.SIZE:
            var c:Vector2i = Vector2i(x, z);
            if terrain.is_water(c) or terrain.cell_height(c) < Terrain.WATER_LEVEL + 0.4:
                continue;
            var slope:float = terrain.cell_slope(c);
            var f:float = forest.get_noise_2d(x, z);
            var r:float = rng.randf();
            if slope > 1.0 and r < 0.06:
                add_node(&"ore" if rng.randf() < 0.18 else &"rock", c);
            elif slope < 1.4 and f > 0.15 and r < 0.45:
                add_node(&"tree", c);
            elif slope < 1.0 and f > -0.1 and f < 0.15 and r < 0.025:
                add_node(&"bush", c);
            elif slope < 1.0 and r < 0.004:
                add_node(&"rock", c);
    renderer.mark_dirty();

# Picks the flattest dry spot nearest the map center.
@warning_ignore("integer_division")
func _find_start_cell() -> Vector2i:
    var center:Vector2i = Vector2i(Terrain.SIZE / 2, Terrain.SIZE / 2);
    var best:Vector2i = center;
    var best_score:float = INF;
    for z in range(16, Terrain.SIZE - 16, 2):
        for x in range(16, Terrain.SIZE - 16, 2):
            var c:Vector2i = Vector2i(x, z);
            var r:Rect2i = Rect2i(c - Vector2i(5, 5), Vector2i(10, 10));
            var hr:Vector2 = terrain.rect_height_range(r);
            if hr.x < Terrain.WATER_LEVEL + 0.5:
                continue;
            var score:float = (hr.y - hr.x) * 4.0 + Vector2(c - center).length() * 0.1;
            if score < best_score:
                best_score = score;
                best = c;
    return best;

func _clear_nodes(c:Vector2i, radius:int) -> void:
    for rn in nodes.duplicate():
        if Vector2(rn.cell - c).length() <= radius:
            remove_node(rn);

# A citizen too unhappy to stay walks away: no body, and half the grief.
func leave_colony(p:Pawn) -> void:
    if p.removed:
        return;
    p.removed = true;
    p.end_task(false);
    if p.carry_amount > 0:
        drop_pile(p.carry_item, p.carry_amount, p.cell());
        p.clear_carry();
    if p.home != null:
        p.home.residents.erase(p);
    pawns.erase(p);
    families.on_death(p, -1);
    jobs.reconcile();
    notify("%s has left the colony, unhappy." % p.first_name);
    if tools != null and tools.selected == p:
        tools.select(null);
    p.queue_free();

func add_body(p:Pawn, cause:String, at:Vector3) -> Body:
    var b:Body = Body.new();
    b.setup(self, _next_body_id, {"name": p.first_name, "age": int(p.age), "cause": cause, "died_hour": GameClock.total_hours}, at);
    _next_body_id += 1;
    b.kin = families.kin_of(p);
    _entities.add_child(b);
    bodies.append(b);
    return b;

func remove_body(b:Body) -> void:
    if b.removed:
        return;
    b.removed = true;
    bodies.erase(b);
    b.queue_free();

func add_pawn(p:Pawn) -> void:
    _entities.add_child(p);
    pawns.append(p);

# The starting upgrades of the chosen difficulty, then the starting goods: into the Town Hall's store room as far as it
# goes, the rest in a supply cart beside it (gone once empty).
func _start_colony_goods(start:Vector2i) -> void:
    for id in Defs.DIFFICULTIES[Defs.difficulty]["town_hall"]:
        town_hall.upgrades_done[id] = true;
    var left:Dictionary = {};
    for item in START_STOCK:
        var rest:int = START_STOCK[item] - town_hall.store(item, START_STOCK[item]);
        if rest > 0:
            left[item] = rest;
    if left.is_empty():
        return;
    var size:Vector2i = Defs.BUILDINGS[&"cart"]["size"];
    for r in range(3, 14):
        for dz in range(-r, r + 1):
            for dx in range(-r, r + 1):
                if maxi(absi(dx), absi(dz)) != r:
                    continue;
                var o:Vector2i = start + Vector2i(dx, dz);
                if can_place(&"cart", o, size) == "" and _rect_free_of_nodes(Rect2i(o, size)):
                    var cart:Building = place_building(&"cart", o, size, true);
                    for item in left:
                        cart.store(item, left[item]);
                    return;

func _spawn_settlers(start:Vector2i) -> void:
    var used:Array[String] = [];
    for i in START_PAWNS:
        var c:Vector2i = nav.nearest_walkable(start + Vector2i(rng.randi_range(-4, 4), 3 + rng.randi_range(0, 2)), 6);
        var p:Pawn = Pawn.new();
        p.setup(self, c, rng, used);
        used.append(p.first_name);
        if i < START_PROFESSIONS.size():
            p.profession = START_PROFESSIONS[i];
        _entities.add_child(p);
        pawns.append(p);

# --------------------------------
# Save and load (see SaveGame)

# Everything needed to rebuild this world. Citizens' tasks are not saved: they restart idle.
func serialize() -> Dictionary:
    var node_list:Array = [];
    for rn in nodes:
        node_list.append(rn.to_array());
    var building_list:Array = [];
    for b in buildings:
        building_list.append(b.to_dict());
    var pawn_list:Array = [];
    for p in pawns:
        pawn_list.append(p.to_dict());
    var body_list:Array = [];
    for b in bodies:
        body_list.append(b.to_dict());
    var pile_list:Array = [];
    for pl in piles:
        pile_list.append(pl.to_dict());
    return {
        "seed": world_seed, "rng_state": rng.state, "wetness": wetness,
        "clock": GameClock.save_state(), "weather": Weather.save_state(),
        "heights": terrain.heights, "overlay": terrain.overlay, "soil": soil_fertility,
        "deaths": death_log, "ageing_days_per_year": Defs.ageing_days_per_year, "targets": jobs.targets, "policies": policies.to_dict(), "ledger": ledger.to_dict(), "nodes": node_list, "buildings": building_list, "pawns": pawn_list, "piles": pile_list, "bodies": body_list, "next_body_id": _next_body_id,
        "camera": camera_rig.save_state() if camera_rig != null else {},
        "summary": {"date": "%s, %s" % [GameClock.date_string(), GameClock.time_string()], "pop": pawns.size()},
    };

# Rebuilds nature, buildings, piles and citizens from a save. The terrain and soil are loaded by the caller.
func _restore_entities(save:Dictionary) -> void:
    soil_fertility = save["soil"];
    wetness = save["wetness"];
    Defs.ageing_days_per_year = save.get("ageing_days_per_year", 4.0);
    for a in save["nodes"]:
        var rn:ResourceNode = ResourceNode.from_array(a, rng);
        nodes.append(rn);
        node_at[idx(rn.cell)] = rn;
        if rn.growth < 1.0:
            saplings.append(rn);
    for bd in save["buildings"]:
        var b:Building = place_building(bd["id"], bd["origin"], bd["size"], false, true);
        b.restore_dict(bd);
        if bd["id"] == &"town_hall" and b.is_complete():
            town_hall = b;
    for i in buildings.size():
        var bd2:Dictionary = save["buildings"][i];
        if bd2.get("reloc_from", -1) >= 0:
            buildings[i].relocating_from = buildings[bd2["reloc_from"]];
        if bd2.get("reloc_to", -1) >= 0:
            buildings[i].relocating_to = buildings[bd2["reloc_to"]];
    for pd in save["piles"]:
        var pl:GroundPile = GroundPile.new();
        pl.setup(self, pd["item"], pd["amount"], pd["cell"]);
        pl._spoil_acc = pd["spoil_acc"];
        _entities.add_child(pl);
        piles.append(pl);
    for pd in save["pawns"]:
        var p:Pawn = Pawn.new();
        p.restore(self, pd);
        _entities.add_child(p);
        pawns.append(p);
        if pd["home"] >= 0 and pd["home"] < buildings.size():
            p.home = buildings[pd["home"]];
            p.home.residents.append(p);
    for i in pawns.size():
        var pd:Dictionary = save["pawns"][i];
        var partner_i:int = pd.get("partner", -1);
        if partner_i >= 0 and partner_i < pawns.size():
            pawns[i].partner = pawns[partner_i];
        for pi in pd.get("parents", []):
            if pi >= 0 and pi < pawns.size():
                pawns[i].parents.append(pawns[pi]);
    _next_body_id = save.get("next_body_id", 1);
    for bd in save.get("bodies", []):
        var b:Body = Body.new();
        b.setup(self, bd["id"], bd, bd["position"]);
        for ki in bd["kin"]:
            if ki >= 0 and ki < pawns.size():
                b.kin.append(pawns[ki]);
        _entities.add_child(b);
        bodies.append(b);
    _refresh_nav_rect(Rect2i(0, 0, Terrain.SIZE, Terrain.SIZE));
    renderer.mark_dirty();
    rng.state = save["rng_state"];
    death_log = save.get("deaths", []);
    policies.restore(save.get("policies", {}));
    ledger.restore(save.get("ledger", {}));
    var saved_targets:Variant = save.get("targets", null);       # saves made before targets existed
    if saved_targets != null:
        jobs.targets = saved_targets;
    else:
        jobs.sync_targets();

# --------------------------------
# Resource nodes

func add_node(kind:StringName, c:Vector2i) -> ResourceNode:
    var rn:ResourceNode = ResourceNode.new(kind, c, rng);
    nodes.append(rn);
    node_at[idx(c)] = rn;
    _refresh_nav(c);
    renderer.mark_dirty();
    return rn;

# Plants a new tree that grows up over time. Returns it, or null if the cell is not usable.
func plant_tree(c:Vector2i) -> ResourceNode:
    if not can_plant_tree(c):
        return null;
    var rn:ResourceNode = add_node(&"tree", c);
    rn.make_sapling();
    saplings.append(rn);
    return rn;

# Free, dry, gentle ground that is not road or field, and not touching another tree.
func can_plant_tree(c:Vector2i) -> bool:
    if not terrain.in_bounds(c) or terrain.is_water(c) or terrain.cell_height(c) < Terrain.WATER_LEVEL + 0.4:
        return false;
    if occupant[idx(c)] != null or node_at[idx(c)] != null or terrain.get_overlay(c) != Terrain.Overlay.NONE:
        return false;
    if terrain.cell_slope(c) > 1.2 or planting.has(c):
        return false;
    for dz in range(-1, 2):
        for dx in range(-1, 2):
            var n:Vector2i = c + Vector2i(dx, dz);
            if terrain.in_bounds(n) and node_at[idx(n)] != null and (node_at[idx(n)] as ResourceNode).kind == &"tree":
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
    var season:float = 0.25 if GameClock.season() == GameClock.Season.WINTER else 1.0;
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

func _update_wetness() -> void:
    wetness += 0.03 * Weather.intensity;
    wetness -= (0.004 + maxf(0.0, Weather.temperature) * 0.0003) * (1.0 - Weather.intensity);
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

func node_changed(_rn:ResourceNode) -> void:
    renderer.mark_dirty();

func set_designated(rn:ResourceNode, on:bool) -> void:
    if rn.designated != on:
        rn.designated = on;
        renderer.mark_dirty();

# --------------------------------
# Buildings

# Returns "" when placement is allowed, otherwise a reason.
# relocating: the building is being moved, so a unique one may be placed again.
func can_place(def_id:StringName, origin:Vector2i, size:Vector2i, relocating:bool = false) -> String:
    var r:Rect2i = Rect2i(origin, size);
    if Defs.BUILDINGS[def_id].get("unique", false) and not relocating:
        for b in buildings:
            if b.def_id == def_id:
                return "There is only one %s" % Defs.BUILDINGS[def_id]["name"];
    if not Rect2i(0, 0, Terrain.SIZE, Terrain.SIZE).encloses(r):
        return "Out of bounds";
    for z in range(r.position.y, r.end.y):
        for x in range(r.position.x, r.end.x):
            var c:Vector2i = Vector2i(x, z);
            if terrain.is_water(c):
                return "Can't build on water";
            if occupant[idx(c)] != null:
                return "Something is already built here";
    var hr:Vector2 = terrain.rect_height_range(r);
    var limit:float = MAX_BUILD_SLOPE * (2.0 if Defs.BUILDINGS[def_id].get("drag_size", false) else 1.0);
    if hr.y - hr.x > limit:
        return "Ground is too steep (flatten it first)";
    return "";

# restoring: put a saved building back as it was (no flattening, clearing or overlay changes).
func place_building(def_id:StringName, origin:Vector2i, size:Vector2i, prebuilt:bool = false, restoring:bool = false) -> Building:
    var def:Dictionary = Defs.BUILDINGS[def_id];
    var r:Rect2i = Rect2i(origin, size);
    var is_field:bool = def.get("field", false);
    if not def.get("drag_size", false) and not restoring:
        terrain.flatten_rect(r);
    var b:Building = Field.new() if is_field else Graveyard.new() if def.get("graveyard", false) else Building.new();
    for z in range(r.position.y, r.end.y):
        for x in range(r.position.x, r.end.x):
            var c:Vector2i = Vector2i(x, z);
            occupant[idx(c)] = b;
            if restoring:
                continue;
            terrain.set_overlay(c, Terrain.Overlay.NONE);
            var rn:ResourceNode = node_at[idx(c)];
            if rn != null:
                # bushes are just uprooted; trees and rocks need clearing by laborers
                if rn.regrows:
                    remove_node(rn);
                else:
                    set_designated(rn, true);
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
    for p in pawns:
        if p.task != null and (is_same(p.task.target, b) or is_same(p.task.workplace, b)):
            p.end_task(false);
    var r:Rect2i = b.rect();
    for z in range(r.position.y, r.end.y):
        for x in range(r.position.x, r.end.x):
            occupant[idx(Vector2i(x, z))] = null;
            if b is Field:
                terrain.set_overlay(Vector2i(x, z), Terrain.Overlay.NONE);
    b.removed = true;
    buildings.erase(b);
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
func relocation_block_reason(b:Building) -> String:
    if not b.def.get("relocatable", true):
        return "Can't be moved";
    if not b.is_complete():
        return "Not finished";
    if b.upgrading != &"":
        return "Upgrade in progress";
    if b.relocating_to != null and alive(b.relocating_to):
        return "Already being moved";
    if b.relocating_from != null:
        return "This is the new site";
    if b.is_storage() and not b.is_empty():
        return "Empty it first";
    return "";

# Starts building the same thing at a new spot for a share of the cost (Defs.RELOCATE_COST_MULT). The old building keeps
# working, takes nothing new, and is replaced once the new one is finished.
func relocate(b:Building, origin:Vector2i, size:Vector2i) -> Building:
    if relocation_block_reason(b) != "" or can_place(b.def_id, origin, size, true) != "":
        return null;
    var site:Building = place_building(b.def_id, origin, size);
    site.cost_mult = Defs.RELOCATE_COST_MULT;
    site.relocating_from = b;
    b.relocating_to = site;
    notify("Moving the %s: a new one is being built." % b.display_name());
    return site;

# The new building takes over: settings, filters, upgrades, fuel, inputs, residents, what is stored, and the Town Hall role.
func _finish_relocation(site:Building) -> void:
    var old:Building = site.relocating_from;
    site.relocating_from = null;
    old.relocating_to = null;
    site.settings = old.settings.duplicate();
    site.forbidden = old.forbidden.duplicate();
    site.upgrades_done = old.upgrades_done.duplicate();
    site.dig_progress = old.dig_progress.duplicate();
    site.fuel = old.fuel;
    old.fuel = 0;
    site.inputs = old.inputs.duplicate();
    old.inputs.clear();
    site.stored = old.stored.duplicate();
    old.stored.clear();
    for p in old.residents.duplicate():
        families.move_home(p, site);
    if old == town_hall:
        town_hall = site;
    old.in_reserved = 0;
    old.out_reserved.clear();
    remove_building(old, false);

func on_building_completed(b:Building) -> void:
    if b is Field:
        for z in range(b.origin.y, b.origin.y + b.size.y):
            for x in range(b.origin.x, b.origin.x + b.size.x):
                terrain.set_overlay(Vector2i(x, z), Terrain.Overlay.TILLED);
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
func nearest_storage_for(item:StringName, pos:Vector3) -> Building:
    return nearest_building(pos, func(b:Building) -> bool:
        return b.can_store(item));

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

func pile_at(c:Vector2i) -> GroundPile:
    for pl in piles:
        if pl.cell == c:
            return pl;
    return null;

# Leaves n units on the ground at the nearest suitable cell (merging with a pile of the same item).
func drop_pile(item:StringName, n:int, near:Vector2i) -> void:
    if n <= 0:
        return;
    for radius in 6:
        for dz in range(-radius, radius + 1):
            for dx in range(-radius, radius + 1):
                if maxi(absi(dx), absi(dz)) != radius:
                    continue;
                var c:Vector2i = near + Vector2i(dx, dz);
                if not terrain.in_bounds(c) or terrain.is_water(c) or occupant[idx(c)] != null or node_at[idx(c)] != null:
                    continue;
                var existing:GroundPile = pile_at(c);
                if existing != null:
                    if existing.item == item:
                        existing.add(n);
                        return;
                    continue;
                var pl:GroundPile = GroundPile.new();
                pl.setup(self, item, n, c);
                _entities.add_child(pl);
                piles.append(pl);
                return;
    notify("No room to put down %d %s." % [n, Defs.item_name(item)]);

func remove_pile(pl:GroundPile) -> void:
    if pl.removed:
        return;
    # hidden now; the collecting task frees it when it ends (see JobManager._collect_task)
    pl.removed = true;
    pl.visible = false;
    piles.erase(pl);

# --------------------------------
# Roads

func can_road(c:Vector2i) -> bool:
    return terrain.in_bounds(c) and not terrain.is_water(c) and occupant[idx(c)] == null and node_at[idx(c)] == null;

func set_road(c:Vector2i, on:bool) -> void:
    if on and not can_road(c):
        return;
    if not on and terrain.get_overlay(c) != Terrain.Overlay.ROAD:
        return;
    terrain.set_overlay(c, Terrain.Overlay.ROAD if on else Terrain.Overlay.NONE);
    _refresh_nav(c);

# --------------------------------
# Pawns

# at_home: a natural death (old age) happens in bed when the citizen has a home.
@warning_ignore("integer_division")
func kill_pawn(p:Pawn, cause:String, at_home:bool = false) -> void:
    if p.removed:
        return;
    p.removed = true;
    p.end_task(false);
    var spot:Vector3 = p.position;
    if at_home and alive(p.home):
        spot = terrain.cell_center(p.home.origin + Vector2i(p.home.size.x / 2, p.home.size.y));     # just outside the door
    if p.carry_amount > 0:
        drop_pile(p.carry_item, p.carry_amount, terrain.world_to_cell(spot));
        p.clear_carry();
    ledger.deaths_today += 1;
    death_log.append({"name": p.first_name, "age": int(p.age), "cause": cause, "when": "%s, %s" % [GameClock.date_string(), GameClock.time_string()], "profession": p.profession_name()});
    if p.home != null:
        p.home.residents.erase(p);
    var body:Body = add_body(p, cause, spot);
    pawns.erase(p);
    families.on_death(p, body.id);
    jobs.reconcile();
    notify("%s has died of %s." % [p.first_name, cause]);
    if tools != null and tools.selected == p:
        tools.select(null);
    p.queue_free();

# --------------------------------
# Navigation

func _refresh_nav_rect(r:Rect2i) -> void:
    r = r.intersection(Rect2i(0, 0, Terrain.SIZE, Terrain.SIZE));
    for z in range(r.position.y, r.end.y):
        for x in range(r.position.x, r.end.x):
            _refresh_nav(Vector2i(x, z));

func _refresh_nav(c:Vector2i) -> void:
    var i:int = idx(c);
    var solid:bool = terrain.is_water(c) or terrain.cell_slope(c) > MAX_WALK_SLOPE;
    var weight:float = 1.0;
    var b:Building = occupant[i];
    if b != null and not b.is_walkable():
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
            _spoiled_today += b.spoil_tick(1.0);
    for pl in piles.duplicate():
        _spoiled_today += pl.spoil_tick(1.0);
        if pl.amount <= 0 and not pl.removed and pl.reserved_by == null:
            remove_pile(pl);
            pl.queue_free();
    _update_wetness();
    _grow_trees();
    _check_storage_full();

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
    ledger.on_day(self);
    for b in buildings:
        b.on_day();
    families.on_day();
    if _spoiled_today >= 5:
        notify("%d units of food spoiled yesterday." % _spoiled_today);
    _spoiled_today = 0;
    var s:int = GameClock.season();
    if s == GameClock.Season.SPRING or s == GameClock.Season.SUMMER:
        for rn in nodes:
            if rn.regrows and rn.amount < rn.max_amount:
                rn.amount += 1;
        renderer.mark_dirty();

func _apply_season(s:int) -> void:
    terrain.set_season(s);
    renderer.set_season(s);

func _on_season(s:int) -> void:
    _apply_season(s);
    if GameClock.total_hours > GameClock.START_HOUR + 1.0:
        notify("%s has arrived." % GameClock.SEASON_NAMES[s]);
        SaveGame.autosave(self);
