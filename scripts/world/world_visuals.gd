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
var _water      :MeshInstance3D;
var _rain       :CPUParticles3D;
var _snow       :CPUParticles3D;

func _init(w:World) -> void:
    world = w;

func _process(_delta:float) -> void:
    _update_lighting();
    _update_precip();

func setup_environment() -> void:
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

    _water = MeshInstance3D.new();
    var wm:StandardMaterial3D = StandardMaterial3D.new();
    wm.vertex_color_use_as_albedo = true;
    wm.vertex_color_is_srgb = true;
    wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA;
    wm.roughness = 0.15;
    wm.metallic = 0.2;
    _water.material_override = wm;
    _water.position = Vector3(0.0, Terrain.WATER_LEVEL, 0.0);
    _water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
    add_child(_water);
    rebuild_water();

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
    var wet:float = Weather.intensity;
    var gloom:float = lerpf(1.0, 0.6, wet);

    # the sun crosses the sky by day and the moon by night, along one
    # continuous arc so the light never jumps at the handover
    var day_t:float = (h - 5.0) / 16.0;      # 05:00 .. 21:00
    var is_day:bool = day_t >= 0.0 and day_t <= 1.0;
    var night_t:float = fposmod(h - 21.0, 24.0) / 8.0;
    var arc:float = sin((day_t if is_day else night_t) * PI);
    var elevation:float = lerpf(6.0, 62.0 if is_day else 45.0, arc);
    var azimuth:float = lerpf(110.0, -110.0, day_t) if is_day else lerpf(110.0, -110.0, night_t);
    _sun.rotation = Vector3(-deg_to_rad(elevation), deg_to_rad(azimuth), 0.0);
    _sun.light_color = (a[1] as Color).lerp(b[1], t);
    _sun.light_energy = lerpf(a[2], b[2], t) * gloom;

    var top:Color = (a[5] as Color).lerp(b[5], t);
    var horizon:Color = (a[6] as Color).lerp(b[6], t);
    top = top.lerp(RAIN_GREY * top.get_luminance() * 2.0, 0.6 * wet);
    horizon = horizon.lerp(RAIN_GREY * horizon.get_luminance() * 1.4, 0.6 * wet);
    _sky.sky_top_color = top;
    _sky.sky_horizon_color = horizon;
    _sky.ground_horizon_color = horizon;
    _sky.ground_bottom_color = horizon.darkened(0.5);
    _env.ambient_light_color = (a[3] as Color).lerp(b[3], t);
    _env.ambient_light_energy = lerpf(a[4], b[4], t);
    _env.fog_light_color = horizon;
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
    _on_weather_changed();

const RAIN_ALPHA :float = 0.45;
const SNOW_ALPHA :float = 0.9;

# Between the freezing and rain-only temperatures the two emitters share the sky: mostly snow near
# 0 C, mostly rain near 3 C. The mix is set hourly (changing an emitter's amount restarts it)...
func _on_weather_changed() -> void:
    if _rain == null:
        return;
    var snow_f:float = Weather.snow_fraction();
    var rain_n:int = maxi(1, int(RAIN_PARTICLES * (1.0 - snow_f)));
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
    rain_mat.albedo_color.a = RAIN_ALPHA * wet;
    snow_mat.albedo_color.a = SNOW_ALPHA * wet;
