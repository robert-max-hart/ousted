# ----------------------------------------------------------------
# World
#     Root of the game scene. Builds the terrain, environment, camera,
#     UI and starting colony, and owns all entities plus the per-cell
#     occupancy used for placement and pathfinding.
# ----------------------------------------------------------------
class_name World extends Node3D;

static var instance:World = null;

const START_PAWNS       :int = 6;
const START_STOCK       :Dictionary = {&"wood": 40, &"stone": 20, &"iron": 4, &"wheat": 90, &"berries": 30};
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
var tools       :PlayerTools;
var hud         :HUD;
var camera_rig  :RTSCamera;
var renderer    :ResourceRenderer;
var rng         :RandomNumberGenerator = RandomNumberGenerator.new();

var buildings   :Array[Building] = [];
var pawns       :Array[Pawn] = [];
var nodes       :Array[ResourceNode] = [];
var occupant    :Array = [];        # Building per cell, or null
var node_at     :Array = [];        # ResourceNode per cell, or null
var soil_fertility:PackedFloat32Array;
var town_hall   :Building;

var _entities   :Node3D;
var _env        :Environment;
var _sky        :ProceduralSkyMaterial;
var _sun        :DirectionalLight3D;
var _rain       :CPUParticles3D;
var _rain_mat   :StandardMaterial3D;

static func alive(o:Variant) -> bool:
    return o != null and is_instance_valid(o) and not o.removed;

func _ready() -> void:
    instance = self;
    if world_seed == 0:
        world_seed = randi() % 1000000;
    rng.seed = world_seed;
    print("Ousted world seed: %d" % world_seed);

    terrain = Terrain.new();
    terrain.name = "Terrain";
    add_child(terrain);
    terrain.generate(world_seed);
    terrain.changed.connect(_on_terrain_changed);

    var n:int = Terrain.SIZE * Terrain.SIZE;
    occupant.resize(n);
    node_at.resize(n);
    _init_soil();
    nav = NavGrid.new();
    nav.setup(Terrain.SIZE);
    _refresh_nav_rect(Rect2i(0, 0, Terrain.SIZE, Terrain.SIZE));

    _setup_environment();
    _entities = Node3D.new();
    _entities.name = "Entities";
    add_child(_entities);
    renderer = ResourceRenderer.new();
    renderer.name = "Nature";
    add_child(renderer);
    jobs = JobManager.new(self);

    _spawn_nature();
    var start:Vector2i = _find_start_cell();
    _clear_nodes(start, 10);
    town_hall = place_building(&"town_hall", start - Vector2i(2, 2), Vector2i(4, 4), true);
    Stock.reset(START_STOCK);
    _spawn_settlers(start);

    camera_rig = RTSCamera.new();
    camera_rig.name = "CameraRig";
    add_child(camera_rig);
    camera_rig.focus_on(town_hall.position);
    _setup_weather_fx();

    tools = PlayerTools.new();
    tools.name = "Tools";
    add_child(tools);
    hud = HUD.new();
    hud.name = "HUD";
    add_child(hud);

    GameClock.hour_changed.connect(_on_hour);
    GameClock.day_changed.connect(_on_day);
    GameClock.season_changed.connect(_on_season);
    Weather.weather_changed.connect(_on_weather_changed);
    _on_season(GameClock.season());
    _on_weather_changed();
    notify("Your settlers have arrived. Spring has begun.");

func _process(_delta:float) -> void:
    _update_lighting();

func idx(c:Vector2i) -> int:
    return c.y * Terrain.SIZE + c.x;

func notify(msg:String) -> void:
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
# Resource nodes

func add_node(kind:StringName, c:Vector2i) -> ResourceNode:
    var rn:ResourceNode = ResourceNode.new(kind, c, rng);
    nodes.append(rn);
    node_at[idx(c)] = rn;
    _refresh_nav(c);
    renderer.mark_dirty();
    return rn;

func remove_node(rn:ResourceNode) -> void:
    if rn.removed:
        return;
    rn.removed = true;
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
func can_place(def_id:StringName, origin:Vector2i, size:Vector2i) -> String:
    var r:Rect2i = Rect2i(origin, size);
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
    var limit:float = MAX_BUILD_SLOPE * (2.0 if Defs.BUILDINGS[def_id].get("field", false) else 1.0);
    if hr.y - hr.x > limit:
        return "Ground is too steep (flatten it first)";
    return "";

func place_building(def_id:StringName, origin:Vector2i, size:Vector2i, prebuilt:bool = false) -> Building:
    var def:Dictionary = Defs.BUILDINGS[def_id];
    var r:Rect2i = Rect2i(origin, size);
    var is_field:bool = def.get("field", false);
    if not is_field:
        terrain.flatten_rect(r);
    var b:Building = Field.new() if is_field else Building.new();
    for z in range(r.position.y, r.end.y):
        for x in range(r.position.x, r.end.x):
            var c:Vector2i = Vector2i(x, z);
            occupant[idx(c)] = b;
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
    if b == town_hall:
        notify("The Town Hall can't be demolished.");
        return;
    if refund:
        var share:float = 1.0 if not b.is_complete() else 0.5;
        for item in b.delivered:
            Stock.add(item, floori(b.delivered[item] * share));
    for p in b.residents:
        p.home = null;
    # cancel work aimed at it now, while task callbacks can still see it
    for p in pawns:
        if p.task != null and is_same(p.task.target, b):
            p.end_task(false);
    var r:Rect2i = b.rect();
    for z in range(r.position.y, r.end.y):
        for x in range(r.position.x, r.end.x):
            occupant[idx(Vector2i(x, z))] = null;
            if b is Field:
                terrain.set_overlay(Vector2i(x, z), Terrain.Overlay.NONE);
    b.removed = true;
    buildings.erase(b);
    _refresh_nav_rect(r);
    b.queue_free();

func is_site_clear(b:Building) -> bool:
    var r:Rect2i = b.rect();
    for z in range(r.position.y, r.end.y):
        for x in range(r.position.x, r.end.x):
            if node_at[idx(Vector2i(x, z))] != null:
                return false;
    return true;

func on_building_completed(b:Building) -> void:
    if b is Field:
        for z in range(b.origin.y, b.origin.y + b.size.y):
            for x in range(b.origin.x, b.origin.x + b.size.x):
                terrain.set_overlay(Vector2i(x, z), Terrain.Overlay.TILLED);
    if b.def.has("beds") and b != town_hall:
        for p in pawns:
            if b.residents.size() >= b.def["beds"]:
                break;
            if p.home == null:
                p.home = b;
                b.residents.append(p);
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

func nearest_storage(pos:Vector3) -> Building:
    return nearest_building(pos, func(b:Building) -> bool:
        return b.is_complete() and b.def.get("storage", false));

func shelter_for(p:Pawn) -> Building:
    if alive(p.home) and p.home.is_complete():
        return p.home;
    return nearest_building(p.position, func(b:Building) -> bool:
        return b.is_complete() and b.def.has("beds"));

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

func kill_pawn(p:Pawn, cause:String) -> void:
    if p.removed:
        return;
    p.removed = true;
    p.end_task(false);
    if p.home != null:
        p.home.residents.erase(p);
    pawns.erase(p);
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
    for b in buildings:
        if b.rect().intersects(r):
            b.on_terrain_changed();

# --------------------------------
# Time

func _on_hour(_h:int) -> void:
    for b in buildings:
        b.on_hour();

func _on_day(_d:int) -> void:
    for b in buildings:
        b.on_day();
    var s:int = GameClock.season();
    if s == GameClock.Season.SPRING or s == GameClock.Season.SUMMER:
        for rn in nodes:
            if rn.regrows and rn.amount < rn.max_amount:
                rn.amount += 1;
        renderer.mark_dirty();

func _on_season(s:int) -> void:
    terrain.set_season(s);
    renderer.set_season(s);
    if GameClock.total_hours > GameClock.START_HOUR + 1.0:
        notify("%s has arrived." % GameClock.SEASON_NAMES[s]);

# --------------------------------
# Environment, lighting, weather visuals

func _setup_environment() -> void:
    _sky = ProceduralSkyMaterial.new();
    var sky:Sky = Sky.new();
    sky.sky_material = _sky;
    _env = Environment.new();
    _env.background_mode = Environment.BG_SKY;
    _env.sky = sky;
    _env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR;
    _env.tonemap_mode = Environment.TONE_MAPPER_FILMIC;
    _env.fog_enabled = true;
    _env.fog_density = 0.0012;
    _env.fog_sky_affect = 0.3;
    var we:WorldEnvironment = WorldEnvironment.new();
    we.environment = _env;
    add_child(we);

    _sun = DirectionalLight3D.new();
    _sun.shadow_enabled = true;
    _sun.shadow_opacity = 0.8;
    _sun.directional_shadow_max_distance = 140.0;
    add_child(_sun);

    var water:MeshInstance3D = MeshInstance3D.new();
    var plane:PlaneMesh = PlaneMesh.new();
    plane.size = Vector2(Terrain.SIZE + 200, Terrain.SIZE + 200);
    water.mesh = plane;
    var wm:StandardMaterial3D = StandardMaterial3D.new();
    wm.albedo_color = Color(0.18, 0.38, 0.55, 0.78);
    wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA;
    wm.roughness = 0.15;
    wm.metallic = 0.2;
    water.material_override = wm;
    water.position = Vector3(Terrain.SIZE * 0.5, Terrain.WATER_LEVEL, Terrain.SIZE * 0.5);
    water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
    add_child(water);

# Light keyframes over the day. Night is lit by a cool moon rather than
# going dark, so the cycle reads as color temperature, not brightness.
#   hour, light color, light energy, ambient color, ambient energy, sky top, sky horizon
const LIGHT_KEYS:Array = [
    [0.0,  Color(0.6, 0.72, 1.0),  0.6,  Color(0.45, 0.55, 0.85), 0.36, Color(0.1, 0.15, 0.32),  Color(0.22, 0.3, 0.5)],
    [4.5,  Color(0.6, 0.72, 1.0),  0.6,  Color(0.45, 0.55, 0.85), 0.36, Color(0.1, 0.15, 0.32),  Color(0.22, 0.3, 0.5)],
    [6.0,  Color(1.0, 0.72, 0.5),  0.64, Color(0.76, 0.68, 0.66), 0.31, Color(0.35, 0.4, 0.62),  Color(0.95, 0.66, 0.46)],
    [8.0,  Color(1.0, 1.0, 1.0),   0.7,  Color(0.7, 0.72, 0.75),  0.3,  Color(0.3, 0.5, 0.82),   Color(0.75, 0.8, 0.86)],
    [18.0, Color(1.0, 1.0, 1.0),   0.7,  Color(0.7, 0.72, 0.75),  0.3,  Color(0.3, 0.5, 0.82),   Color(0.75, 0.8, 0.86)],
    [20.0, Color(1.0, 0.66, 0.45), 0.64, Color(0.76, 0.66, 0.65), 0.31, Color(0.32, 0.34, 0.58), Color(0.95, 0.58, 0.4)],
    [21.5, Color(0.6, 0.72, 1.0),  0.6,  Color(0.45, 0.55, 0.85), 0.36, Color(0.1, 0.15, 0.32),  Color(0.22, 0.3, 0.5)],
    [24.0, Color(0.6, 0.72, 1.0),  0.6,  Color(0.45, 0.55, 0.85), 0.36, Color(0.1, 0.15, 0.32),  Color(0.22, 0.3, 0.5)],
];
const RAIN_GREY:Color = Color(0.55, 0.58, 0.62);

func _update_lighting() -> void:
    var h:float = GameClock.hour();
    var k:int = 0;
    while k < LIGHT_KEYS.size() - 2 and h >= LIGHT_KEYS[k + 1][0]:
        k += 1;
    var a:Array = LIGHT_KEYS[k];
    var b:Array = LIGHT_KEYS[k + 1];
    var t:float = smoothstep(0.0, 1.0, (h - a[0]) / (b[0] - a[0]));
    var gloom:float = 1.0 if not Weather.is_raining else 0.6;

    # the sun crosses the sky by day and the moon by night, along one
    # continuous arc so the light never jumps at the handover
    var day_t:float = (h - 5.0) / 16.0;      # 05:00 .. 21:00
    var is_day:bool = day_t >= 0.0 and day_t <= 1.0;
    var night_t:float = fposmod(h - 21.0, 24.0) / 8.0;
    var arc:float = sin((day_t if is_day else night_t) * PI);
    var elevation:float = lerpf(6.0, 62.0 if is_day else 45.0, arc);
    var azimuth:float = lerpf(110.0, -110.0, day_t) if is_day else lerpf(-110.0, 110.0, night_t);
    _sun.rotation = Vector3(-deg_to_rad(elevation), deg_to_rad(azimuth), 0.0);
    _sun.light_color = (a[1] as Color).lerp(b[1], t);
    _sun.light_energy = lerpf(a[2], b[2], t) * gloom;

    var top:Color = (a[5] as Color).lerp(b[5], t);
    var horizon:Color = (a[6] as Color).lerp(b[6], t);
    if Weather.is_raining:
        top = top.lerp(RAIN_GREY * top.get_luminance() * 2.0, 0.6);
        horizon = horizon.lerp(RAIN_GREY * horizon.get_luminance() * 1.4, 0.6);
    _sky.sky_top_color = top;
    _sky.sky_horizon_color = horizon;
    _sky.ground_horizon_color = horizon;
    _sky.ground_bottom_color = horizon.darkened(0.5);
    _env.ambient_light_color = (a[3] as Color).lerp(b[3], t);
    _env.ambient_light_energy = lerpf(a[4], b[4], t);
    _env.fog_light_color = horizon;
    _env.fog_density = 0.0012 if not Weather.is_raining else 0.004;

func _setup_weather_fx() -> void:
    _rain = CPUParticles3D.new();
    _rain.amount = 2500;
    _rain.local_coords = false;
    _rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX;
    _rain.emission_box_extents = Vector3(35, 0.5, 35);
    _rain.direction = Vector3.DOWN;
    _rain.spread = 3.0;
    _rain.position = Vector3(0, 22, 0);
    _rain.emitting = false;
    var drop:BoxMesh = BoxMesh.new();
    drop.size = Vector3(0.03, 0.5, 0.03);
    _rain_mat = StandardMaterial3D.new();
    _rain_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED;
    _rain_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA;
    drop.material = _rain_mat;
    _rain.mesh = drop;
    _rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
    camera_rig.add_child(_rain);

func _on_weather_changed() -> void:
    if _rain == null:
        return;
    _rain.emitting = Weather.is_raining;
    if Weather.is_snowing():
        _rain.lifetime = 9.0;
        _rain.initial_velocity_min = 2.0;
        _rain.initial_velocity_max = 2.5;
        _rain.gravity = Vector3(0.3, -0.5, 0);
        (_rain.mesh as BoxMesh).size = Vector3(0.08, 0.08, 0.08);
        _rain_mat.albedo_color = Color(1, 1, 1, 0.9);
    else:
        _rain.lifetime = 1.1;
        _rain.initial_velocity_min = 18.0;
        _rain.initial_velocity_max = 20.0;
        _rain.gravity = Vector3(0, -9.8, 0);
        (_rain.mesh as BoxMesh).size = Vector3(0.03, 0.5, 0.03);
        _rain_mat.albedo_color = Color(0.7, 0.75, 0.85, 0.45);
