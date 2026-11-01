# ----------------------------------------------------------------
# WorldVisuals
#     The look of the world: sky and lighting through the day, the
#     water surface, and rain and snow. A child of World.
# ----------------------------------------------------------------
class_name WorldVisuals extends Node3D;

var world:World;
var _env        :Environment;
var _sky        :ProceduralSkyMaterial;
var _sun        :DirectionalLight3D;
var _moon       :DirectionalLight3D;       # a second light: the moon fades in as the sun fades out (and back), so the light never jumps
var _water      :MeshInstance3D;
var _rain       :CPUParticles3D;
var _snow       :CPUParticles3D;
var _water_mat  :ShaderMaterial;
var snow_cover :float:                  # how much of the ground is under snow, 0 to 1: it builds in snowfall and melts in warm weather (kept in Weather, so it is saved and citizens feel it)
    get: return Weather.snow_depth;
    set(v): Weather.snow_depth = v;
var edge_clouds:MapEdgeClouds;         # the cloud bank and cloud sea round the map's edge
var _flash      :float = 0.0;          # a lightning flash fading out (0 to 1)
var _bolt       :MeshInstance3D;
var _fx_clock:float = 0.0;           # advances with the game's speed (World.fx_speed), so the water stops when paused

func _init(w:World) -> void:
    world = w;

func _process(delta:float) -> void:
    _flash = maxf(0.0, _flash - delta * 6.0);
    _update_lighting();
    _update_precip();
    _update_water(delta);
    _update_snow(delta);

# Re-reads the player's settings (shadows).
func apply_settings() -> void:
    _sun.shadow_enabled = Settings.shadows_on();
    _moon.shadow_enabled = Settings.shadows_on();
    WindSway.enabled = Settings.sway_on();
    WindSway.grass_enabled = Settings.grass_sway_on();
    if _water_mat != null:
        _water_mat.set_shader_parameter("detail", float(Settings.water));
    if edge_clouds != null:
        edge_clouds.apply_settings();
    if world.terrain != null:
        world.terrain.apply_settings();

func setup_environment() -> void:
    _sky = ProceduralSkyMaterial.new();
    var sky:Sky = Sky.new();
    sky.sky_material = _sky;
    _env = Environment.new();
    _env.background_mode = Environment.BG_SKY;
    _env.sky = sky;
    _env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR;
    _env.tonemap_mode = Environment.TONE_MAPPER_FILMIC;
    _env.adjustment_enabled = true;                  # a little richer than the filmic curve alone, which read washed out
    _env.adjustment_saturation = GRADE_SATURATION;
    _env.adjustment_contrast = GRADE_CONTRAST;
    _env.fog_enabled = true;
    _env.fog_density = 0.0012;
    _env.fog_sky_affect = 0.3;
    var we:WorldEnvironment = WorldEnvironment.new();
    we.environment = _env;
    add_child(we);

    _sun = DirectionalLight3D.new();
    _sun.shadow_enabled = Settings.shadows_on();
    _sun.shadow_opacity = 0.8;
    _sun.directional_shadow_max_distance = 140.0;
    add_child(_sun);
    _moon = DirectionalLight3D.new();
    _moon.shadow_enabled = Settings.shadows_on();
    _moon.shadow_opacity = 0.6;
    _moon.directional_shadow_max_distance = 140.0;
    _moon.light_color = Color(0.6, 0.72, 1.0);
    add_child(_moon);

    _water = MeshInstance3D.new();
    _water_mat = ShaderMaterial.new();
    _water_mat.shader = load("res://shaders/water.gdshader") as Shader;
    _water_mat.set_shader_parameter("ripples", WaterTexture.make(world.world_seed));
    _water.material_override = _water_mat;
    apply_settings();
    start_snow_cover();
    edge_clouds = MapEdgeClouds.new();
    world.add_child(edge_clouds);
    edge_clouds.build(world.terrain, world.world_seed);
    _water.position = Vector3(0.0, Terrain.WATER_LEVEL, 0.0);
    _water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
    add_child(_water);
    rebuild_water();

# Snow on the ground (the rules are Weather.update_snow). It follows the game's speed (World.fx_speed) and is saved with the weather; a
# game saved before that, or a new one, starts with the cover its season's temperature suggests.
func start_snow_cover() -> void:
    if Weather.snow_loaded:
        Weather.snow_loaded = false;
    else:
        snow_cover = clampf(-Weather.mean_temperature() / 8.0, 0.0, 1.0);
    _apply_snow();

func _update_snow(delta:float) -> void:
    var hours:float = delta * World.fx_speed() / GameRules.seconds_per_hour();
    if hours <= 0.0:
        return;
    Weather.update_snow(hours);
    _apply_snow();

func _apply_snow() -> void:
    if world.terrain != null:
        world.terrain.set_snow(snow_cover);

# The colour grade over the whole picture (tests/palette_shot compares looks).
const GRADE_SATURATION:float = 1.18;
const GRADE_CONTRAST  :float = 1.06;

# The shader's clock and strength: waves and ripples pick up a little in rain.
const WATER_SWELL:float = 0.035;
const WATER_RIPPLE:float = 0.55;

func _update_water(delta:float) -> void:
    if _water_mat == null:
        return;
    _fx_clock += delta * World.fx_speed();
    _water_mat.set_shader_parameter("clock", _fx_clock);
    var rough:float = 1.0 + 0.8 * Weather.intensity;
    _water_mat.set_shader_parameter("swell", WATER_SWELL * rough);
    _water_mat.set_shader_parameter("ripple", WATER_RIPPLE * rough);
    WindSway.update(_fx_clock, rough, snow_cover);        # trees, bushes and grass share the clock; the wind is stronger in rain

# The water surface is a grid matching the terrain corners. Vertex color fades from shallow to deep
# and from transparent to opaque with depth, so shorelines blend instead of cutting a hard line.
const WATER_SHALLOW :Color = Color(0.36, 0.62, 0.68);
const WATER_DEEP    :Color = Color(0.18, 0.38, 0.55);
const WATER_FADE    :float = 0.6;       # depth (m) at which water becomes fully opaque

func rebuild_water() -> void:
    if _water == null:
        return;
    var xs:PackedFloat32Array = PackedFloat32Array();
    for i in Terrain.SIZE + 1:
        xs.append(float(i));
    var n:int = xs.size();
    var verts:PackedVector3Array = PackedVector3Array();
    var colors:PackedColorArray = PackedColorArray();
    verts.resize(n * n);
    colors.resize(n * n);
    for zi in n:
        for xi in n:
            var depth:float = Terrain.WATER_LEVEL - world.terrain.corner(int(xs[xi]), int(xs[zi]));
            var t:float = smoothstep(0.0, WATER_FADE, depth);
            var col:Color = WATER_SHALLOW.lerp(WATER_DEEP, t);
            col.a = t * 0.78;
            verts[zi * n + xi] = Vector3(xs[xi], 0.0, xs[zi]);
            colors[zi * n + xi] = col;
    var indices:PackedInt32Array = PackedInt32Array();
    indices.resize((n - 1) * (n - 1) * 6);
    var k:int = 0;
    for zi in n - 1:
        for xi in n - 1:
            var a:int = zi * n + xi;
            indices[k] = a;
            indices[k + 1] = a + 1;
            indices[k + 2] = a + n + 1;
            indices[k + 3] = a;
            indices[k + 4] = a + n + 1;
            indices[k + 5] = a + n;
            k += 6;
    var normals:PackedVector3Array = PackedVector3Array();
    normals.resize(n * n);
    normals.fill(Vector3.UP);
    var arrays:Array = [];
    arrays.resize(Mesh.ARRAY_MAX);
    arrays[Mesh.ARRAY_VERTEX] = verts;
    arrays[Mesh.ARRAY_NORMAL] = normals;
    arrays[Mesh.ARRAY_COLOR] = colors;
    arrays[Mesh.ARRAY_INDEX] = indices;
    var mesh:ArrayMesh = ArrayMesh.new();
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays);
    _water.mesh = mesh;

# Light keyframes over the day. Night is lit by a cool moon rather than
# going dark, so the cycle reads as color temperature, not brightness.
#   hour, light color, light energy, ambient color, ambient energy, sky top, sky horizon
const LIGHT_KEYS:Array = [
    [0.0,  Color(0.6, 0.72, 1.0),  0.6,  Color(0.45, 0.55, 0.85), 0.36, Color(0.1, 0.15, 0.32),  Color(0.22, 0.3, 0.5)],
    [4.0,  Color(0.6, 0.72, 1.0),  0.6,  Color(0.45, 0.55, 0.85), 0.36, Color(0.1, 0.15, 0.32),  Color(0.22, 0.3, 0.5)],
    [6.0,  Color(1.0, 0.72, 0.5),  0.64, Color(0.76, 0.68, 0.66), 0.31, Color(0.35, 0.4, 0.62),  Color(0.95, 0.66, 0.46)],
    [9.0,  Color(1.0, 0.98, 0.93), 0.62, Color(0.66, 0.7, 0.76),  0.26,  Color(0.3, 0.5, 0.82),   Color(0.75, 0.8, 0.86)],
    [16.5, Color(1.0, 0.98, 0.93), 0.62, Color(0.66, 0.7, 0.76),  0.26,  Color(0.3, 0.5, 0.82),   Color(0.75, 0.8, 0.86)],
    [19.5, Color(1.0, 0.66, 0.45), 0.64, Color(0.76, 0.66, 0.65), 0.31, Color(0.32, 0.34, 0.58), Color(0.95, 0.58, 0.4)],
    [22.5, Color(0.6, 0.72, 1.0),  0.6,  Color(0.45, 0.55, 0.85), 0.36, Color(0.1, 0.15, 0.32),  Color(0.22, 0.3, 0.5)],
    [24.0, Color(0.6, 0.72, 1.0),  0.6,  Color(0.45, 0.55, 0.85), 0.36, Color(0.1, 0.15, 0.32),  Color(0.22, 0.3, 0.5)],
];
# Each light's colour and energy over the day, as [hour, colour, energy]: the sun is warm and low at the edges of its day and
# only reaches full strength by mid-morning; the moon's curve takes over as the sun's runs out.
const SUN_KEYS:Array = [
    [0.0,  Color(1.0, 0.72, 0.5),  0.0],
    [4.5,  Color(1.0, 0.72, 0.5),  0.0],
    [6.5,  Color(1.0, 0.72, 0.5),  0.5],
    [9.0,  Color(1.0, 0.98, 0.93), 0.62],
    [16.5, Color(1.0, 0.98, 0.93), 0.62],
    [19.0, Color(1.0, 0.66, 0.45), 0.5],
    [21.5, Color(1.0, 0.66, 0.45), 0.0],
    [24.0, Color(1.0, 0.72, 0.5),  0.0],
];
const MOON_KEYS:Array = [
    [0.0,  Color(0.6, 0.72, 1.0), 0.6],
    [4.0,  Color(0.6, 0.72, 1.0), 0.6],
    [7.0,  Color(0.6, 0.72, 1.0), 0.0],
    [18.5, Color(0.6, 0.72, 1.0), 0.0],
    [22.0, Color(0.6, 0.72, 1.0), 0.6],
    [24.0, Color(0.6, 0.72, 1.0), 0.6],
];
const RAIN_GREY:Color = Color(0.55, 0.58, 0.62);

# [colour, energy] at hour h from a list of [hour, colour, energy] keys (smoothly between the neighbours).
func _keyed(keys:Array, h:float) -> Array:
    var k:int = 0;
    while k < keys.size() - 2 and h >= keys[k + 1][0]:
        k += 1;
    var a:Array = keys[k];
    var b:Array = keys[k + 1];
    var t:float = smoothstep(0.0, 1.0, (h - a[0]) / (b[0] - a[0]));
    return [(a[1] as Color).lerp(b[1], t), lerpf(a[2], b[2], t)];

func _update_lighting() -> void:
    var h:float = GameClock.hour();
    var k:int = 0;
    while k < LIGHT_KEYS.size() - 2 and h >= LIGHT_KEYS[k + 1][0]:
        k += 1;
    var a:Array = LIGHT_KEYS[k];
    var b:Array = LIGHT_KEYS[k + 1];
    var t:float = smoothstep(0.0, 1.0, (h - a[0]) / (b[0] - a[0]));
    var wet:float = Weather.intensity;
    var storm:float = Weather.storm_level;
    var gloom:float = lerpf(1.0, 0.4, wet) * lerpf(1.0, 0.6, storm);        # a thunderstorm is darker still

    # the sun crosses the sky by day and the moon by night; each light has its own energy curve (SUN_KEYS, MOON_KEYS), and the
    # curves overlap at dusk and dawn, so one fades out while the other fades in and nothing ever swaps places
    var day_t:float = (h - 5.0) / 16.0;      # 05:00 .. 21:00
    var sun_arc:float = sin(clampf(day_t, 0.0, 1.0) * PI);
    var night_t:float = fposmod(h - 18.0, 24.0) / 13.0;      # the moon travels from 18:00 to 07:00, covering its whole fade in and out
    var moon_arc:float = sin(clampf(night_t, 0.0, 1.0) * PI);
    var sun_el:float = lerpf(6.0, 62.0, sun_arc);
    var moon_el:float = lerpf(6.0, 45.0, moon_arc);
    _sun.rotation = Vector3(-deg_to_rad(sun_el), deg_to_rad(lerpf(110.0, -110.0, clampf(day_t, 0.0, 1.0))), 0.0);
    _moon.rotation = Vector3(-deg_to_rad(moon_el), deg_to_rad(lerpf(110.0, -110.0, clampf(night_t, 0.0, 1.0))), 0.0);
    var sun_now:Array = _keyed(SUN_KEYS, h);
    var moon_now:Array = _keyed(MOON_KEYS, h);
    _sun.light_color = sun_now[0];
    _sun.light_energy = sun_now[1] * gloom + _flash * 0.8;
    _moon.light_energy = moon_now[1] * gloom;
    _sun.visible = _sun.light_energy > 0.005;
    _moon.visible = _moon.light_energy > 0.005;

    var top:Color = (a[5] as Color).lerp(b[5], t);
    var horizon:Color = (a[6] as Color).lerp(b[6], t);
    top = top.lerp(RAIN_GREY * top.get_luminance() * 2.0, 0.6 * wet);
    horizon = horizon.lerp(RAIN_GREY * horizon.get_luminance() * 1.4, 0.6 * wet);
    top = top.darkened(0.35 * storm).lerp(Color(0.9, 0.93, 1.0), 0.7 * _flash);             # (and a flash lights the whole sky)
    horizon = horizon.darkened(0.3 * storm).lerp(Color(0.9, 0.93, 1.0), 0.6 * _flash);
    _sky.sky_top_color = top;
    _sky.sky_horizon_color = horizon;
    _sky.ground_horizon_color = horizon;
    _sky.ground_bottom_color = horizon.darkened(0.5);
    _env.ambient_light_color = (a[3] as Color).lerp(b[3], t);
    _env.ambient_light_energy = lerpf(a[4], b[4], t) * lerpf(1.0, 0.72, wet) * lerpf(1.0, 0.85, storm) + _flash * 2.2;       # rain and snow dim the sky light too, not only the sun; a flash lights up the ground
    _env.fog_light_color = horizon;
    if edge_clouds != null:
        edge_clouds.set_tint(horizon);
    _env.fog_density = lerpf(0.0012, 0.004, wet);

const RAIN_PARTICLES :int = 2500;
const SNOW_PARTICLES :int = 1800;

var _fx_host    :Node3D;       # what the rain and snow emitters hang from (the camera rig; behind the title, a fixed point)

func _make_precip(extents:float) -> CPUParticles3D:
    var p:CPUParticles3D = CPUParticles3D.new();
    p.local_coords = false;
    p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX;
    p.emission_box_extents = Vector3(extents, 0.5, extents);
    p.direction = Vector3.DOWN;
    p.spread = 3.0;
    p.position = Vector3(0, 22, 0);
    p.emitting = false;
    p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
    _fx_host.add_child(p);
    return p;

func _precip_material(color:Color) -> StandardMaterial3D:
    var m:StandardMaterial3D = StandardMaterial3D.new();
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED;
    m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA;
    m.albedo_color = color;
    return m;

func setup_weather_fx(host:Node3D = null) -> void:
    _fx_host = host if host != null else world.camera_rig;
    _rain = _make_precip(35.0);
    _rain.lifetime = 1.1;
    _rain.initial_velocity_min = 18.0;
    _rain.initial_velocity_max = 20.0;
    _rain.gravity = Vector3(0, -9.8, 0);
    var drop:BoxMesh = BoxMesh.new();
    drop.size = Vector3(0.03, 0.5, 0.03);
    drop.material = _precip_material(Color(0.7, 0.75, 0.85, 0.45));
    _rain.mesh = drop;

    _snow = _make_precip(35.0);
    _snow.lifetime = 9.0;
    _snow.initial_velocity_min = 2.0;
    _snow.initial_velocity_max = 2.5;
    _snow.gravity = Vector3(0.3, -0.5, 0);
    var flake:BoxMesh = BoxMesh.new();
    flake.size = Vector3(0.08, 0.08, 0.08);
    flake.material = _precip_material(Color(1, 1, 1, 0.9));
    _snow.mesh = flake;
    if world.is_backdrop:       # behind the title the weather is already in full swing when the picture appears
        _rain.preprocess = _rain.lifetime;
        _snow.preprocess = _snow.lifetime;
    Weather.weather_changed.connect(_on_weather_changed);
    Weather.lightning.connect(_on_lightning);
    _on_weather_changed();

const RAIN_ALPHA :float = 0.45;
const SNOW_ALPHA :float = 0.9;

# Between the freezing and rain-only temperatures the two emitters share the sky: mostly snow near
# 0 C, mostly rain near 3 C. The mix is set hourly (changing an emitter's amount restarts it)...
func _on_weather_changed() -> void:
    if _rain == null:
        return;
    var snow_f:float = Weather.snow_fraction();
    var rain_n:int = maxi(1, int(RAIN_PARTICLES * (1.0 - snow_f) * (1.7 if Weather.storm else 1.0)));
    var snow_n:int = maxi(1, int(SNOW_PARTICLES * snow_f));
    if absi(rain_n - _rain.amount) > 50:
        _rain.amount = rain_n;
    if absi(snow_n - _snow.amount) > 50:
        _snow.amount = snow_n;

# ... while the spell fading in and out is a per-frame alpha ramp.
func _update_precip() -> void:
    if _rain == null:
        return;
    var wet:float = Weather.intensity;
    var snow_f:float = Weather.snow_fraction();
    _rain.speed_scale = World.fx_speed();       # rain and snow stop when the game is paused and run faster when it is sped up
    _snow.speed_scale = World.fx_speed();
    _rain.emitting = wet > 0.01 and snow_f < 1.0;
    _snow.emitting = wet > 0.01 and snow_f > 0.0;
    var rain_mat:StandardMaterial3D = (_rain.mesh as BoxMesh).material as StandardMaterial3D;
    var snow_mat:StandardMaterial3D = (_snow.mesh as BoxMesh).material as StandardMaterial3D;
    rain_mat.albedo_color.a = RAIN_ALPHA * wet * (1.0 + 0.35 * Weather.storm_level);
    snow_mat.albedo_color.a = SNOW_ALPHA * wet;

# --------------------------------
# Lightning

const BOLT_REACH :float = 26.0;        # metres round the point the camera looks at
const BOLT_SECONDS:float = 0.22;

# A flash (twice, a moment apart), a bolt standing on the ground near the view, and the thunder after the time sound takes to arrive.
func _on_lightning(strength:float) -> void:
    if _fx_host == null or not is_inside_tree():
        return;
    _flash = strength;
    var at:Vector3 = _fx_host.global_position;
    var spot:Vector2 = Vector2(at.x, at.z) + Vector2(randf_range(-BOLT_REACH, BOLT_REACH), randf_range(-BOLT_REACH, BOLT_REACH));
    var ground:float = world.terrain.height_at(spot.x, spot.y) if world.terrain != null else 0.0;
    _show_bolt(Vector3(spot.x, ground, spot.y));
    get_tree().create_timer(0.12).timeout.connect(func() -> void: _flash = maxf(_flash, strength * 0.7));
    var distance:float = at.distance_to(Vector3(spot.x, ground, spot.y));
    var delay:float = clampf(distance / 90.0, 0.2, 1.6);           # (the speed of sound, much sped up)
    get_tree().create_timer(delay).timeout.connect(func() -> void: Sfx.ui(&"thunder"));

# A jagged white line from the clouds to the ground, shown for a fraction of a second.
func _show_bolt(ground:Vector3) -> void:
    if _bolt == null:
        _bolt = MeshInstance3D.new();
        _bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
        var m:StandardMaterial3D = StandardMaterial3D.new();
        m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED;
        m.albedo_color = Color(0.92, 0.95, 1.0);
        m.cull_mode = BaseMaterial3D.CULL_DISABLED;
        _bolt.material_override = m;
        _bolt.mesh = ImmediateMesh.new();
        add_child(_bolt);
    var mesh:ImmediateMesh = _bolt.mesh as ImmediateMesh;
    mesh.clear_surfaces();
    var top:float = ground.y + 70.0;
    var path:Array[Vector3] = [];
    var steps:int = 10;
    var start:Vector3 = Vector3(ground.x + randf_range(-6.0, 6.0), top, ground.z + randf_range(-6.0, 6.0));
    for i in range(steps + 1):
        var t:float = float(i) / steps;
        var q:Vector3 = start.lerp(ground, t);
        if i > 0 and i < steps:
            q += Vector3(randf_range(-2.5, 2.5), 0.0, randf_range(-2.5, 2.5)) * (1.0 - t * 0.4);
        path.append(q);
    mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES);        # two crossed ribbons, so the bolt shows from every side
    for side in [Vector3.RIGHT, Vector3.BACK]:
        for i in range(steps):
            var w0:float = lerpf(0.45, 0.18, float(i) / steps);
            var w1:float = lerpf(0.45, 0.18, float(i + 1) / steps);
            var a:Vector3 = path[i];
            var b:Vector3 = path[i + 1];
            for v in [a - side * w0, a + side * w0, b + side * w1, a - side * w0, b + side * w1, b - side * w1]:
                mesh.surface_add_vertex(v);
    mesh.surface_end();
    _bolt.visible = true;
    get_tree().create_timer(BOLT_SECONDS).timeout.connect(func() -> void:
        if is_instance_valid(_bolt):
            _bolt.visible = false);
