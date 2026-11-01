# ----------------------------------------------------------------
# MapEdgeClouds
#     Hides the edge of the map. The land is a slab in empty sky, so past its edge there was nothing but the
#     default sky, and a hard cut where the ground stops. This adds
#       - a sea of cloud (shaders/cloud_floor.gdshader) a few metres under the lowest ground and out to the
#         horizon, where it thins into the sky;
#       - a bank of cloud billows along all four edges (shaders/cloud_bank.gdshader): rows of big squashed
#         spheres, tallest and closest at the edge, which rise a little above the ground there and so cover the
#         cut from the side, from above and from outside; further rows ease down into the sea.
#     All of it is drawn in one multimesh and two materials; the clouds follow the sky's horizon colour
#     (set_tint, called by WorldVisuals) and move with the game clock (WindSway.track). Purely scenery.
# ----------------------------------------------------------------
class_name MapEdgeClouds extends Node3D;

const FLOOR_Y   :float = -3.5;            # the top of the cloud sea (the lowest ground is about -1)
const STEP      :float = 5.0;             # metres between the stations along an edge
const OVERRUN   :float = 14.0;            # how far past each corner the stations go, so the corners are covered
# The rows of the bank: how far outside the edge it stands (m), the puff radius range (m), the height above the ground at the edge, and how many per station.
const ROWS:Array = [
    {"out": 2.0, "r": [5.0, 6.5], "up": 1.4, "n": 2},
    {"out": 9.5, "r": [6.0, 8.5], "up": 2.6, "n": 2},
    {"out": 21.0, "r": [7.0, 11.0], "up": 1.6, "n": 1},
    {"out": 36.0, "r": [9.0, 14.0], "up": 0.5, "n": 1},
    {"out": 62.0, "r": [12.0, 18.0], "up": -1.5, "n": 1},
];

var _bank_mat   :ShaderMaterial;
var _floor_mat  :ShaderMaterial;
var _puffs      :MultiMeshInstance3D;
var _floor      :MeshInstance3D;
var puffs       :Array = [];              # [centre, radius, half height] of every billow (the render server keeps no multimesh data headless, so tests read this)

func build(terrain:Terrain, world_seed:int) -> void:
    name = "MapEdgeClouds";
    var rng:RandomNumberGenerator = RandomNumberGenerator.new();
    rng.seed = world_seed + 4242;
    var size:float = Terrain.SIZE;
    _bank_mat = ShaderMaterial.new();
    _bank_mat.shader = load("res://shaders/cloud_bank.gdshader") as Shader;
    var lumps:Texture2D = _lump_texture(world_seed);
    _bank_mat.set_shader_parameter("lumps", lumps);
    WindSway.track(_bank_mat);
    _floor_mat = ShaderMaterial.new();
    _floor_mat.shader = load("res://shaders/cloud_floor.gdshader") as Shader;
    _floor_mat.set_shader_parameter("centre", Vector2(size * 0.5, size * 0.5));
    _floor_mat.set_shader_parameter("lumps", lumps);
    WindSway.track(_floor_mat);

    var plane:PlaneMesh = PlaneMesh.new();
    plane.size = Vector2(2600.0, 2600.0);
    _floor = MeshInstance3D.new();
    _floor.mesh = plane;
    _floor.material_override = _floor_mat;
    _floor.position = Vector3(size * 0.5, FLOOR_Y, size * 0.5);
    _floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
    add_child(_floor);

    var sphere:SphereMesh = SphereMesh.new();
    sphere.radius = 1.0;
    sphere.height = 2.0;
    sphere.radial_segments = 20;
    sphere.rings = 10;
    var mm:MultiMesh = MultiMesh.new();
    mm.transform_format = MultiMesh.TRANSFORM_3D;
    mm.use_colors = true;                 # kept for the shade (and the Compatibility renderer needs it on)
    mm.use_custom_data = true;
    mm.mesh = sphere;
    var list:Array = [];
    for side in 4:
        var t:float = -OVERRUN;
        while t <= size + OVERRUN:
            for row in ROWS:
                for k in int(row["n"]):
                    list.append(_puff(terrain, rng, side, t + rng.randf_range(-STEP * 0.4, STEP * 0.4), row, k));
            t += STEP;
    mm.instance_count = list.size();
    for i in list.size():
        var xf:Transform3D = list[i][0];
        puffs.append([xf.origin, xf.basis.get_scale().x, xf.basis.get_scale().y]);
        mm.set_instance_transform(i, list[i][0]);
        mm.set_instance_color(i, list[i][1]);
        mm.set_instance_custom_data(i, list[i][2]);
    _puffs = MultiMeshInstance3D.new();
    _puffs.multimesh = mm;
    _puffs.material_override = _bank_mat;
    _puffs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
    _puffs.extra_cull_margin = 60.0;      # the bank is one object round the whole map: do not cull it when only part is in view
    add_child(_puffs);
    apply_settings();

# One billow: its transform, shade and phase. `side` 0 to 3 is north, east, south, west; `t` is where along the edge.
func _puff(terrain:Terrain, rng:RandomNumberGenerator, side:int, t:float, row:Dictionary, k:int) -> Array:
    var size:float = Terrain.SIZE;
    var edge:Vector2;
    var out:Vector2;
    match side:
        0: edge = Vector2(t, 0.0); out = Vector2(0, -1);
        1: edge = Vector2(size, t); out = Vector2(1, 0);
        2: edge = Vector2(t, size); out = Vector2(0, 1);
        _: edge = Vector2(0.0, t); out = Vector2(-1, 0);
    var along:Vector2 = Vector2(-out.y, out.x);
    # the highest ground at the edge along this billow's stretch of it, and a little further in: the bank must rise over what stands behind it too
    var ground:float = 0.0;
    for dt in [-STEP, -STEP * 0.5, 0.0, STEP * 0.5, STEP]:
        for inward in [0.0, 3.0]:
            var q:Vector2 = edge + Vector2(-out.y, out.x) * dt - out * inward;
            ground = maxf(ground, terrain.height_at(clampf(q.x, 0.0, size), clampf(q.y, 0.0, size)));
    var radius:float = rng.randf_range(row["r"][0], row["r"][1]);
    var depth:float = float(row["out"]) + rng.randf_range(-1.2, 1.2) + k * radius * 0.55;
    var pos:Vector2 = edge + out * depth + along * (k * rng.randf_range(-2.0, 2.0));
    var top:float = (ground if float(row["out"]) < 30.0 else 0.0) + float(row["up"]) + rng.randf_range(-0.6, 1.6);
    var bottom:float = FLOOR_Y - 1.0;
    var half:float = maxf((top - bottom) * 0.5, 1.5);
    var basis:Basis = Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(radius * rng.randf_range(1.0, 1.4), half, radius * rng.randf_range(0.85, 1.15)));
    var shade:float = rng.randf_range(0.86, 1.0);
    return [Transform3D(basis, Vector3(pos.x, (top + bottom) * 0.5, pos.y)), Color(shade, shade, shade), Color(rng.randf() * TAU, 0, 0, 0)];

# A seamless lumpy noise for the sea of cloud.
func _lump_texture(world_seed:int) -> Texture2D:
    var noise:FastNoiseLite = FastNoiseLite.new();
    noise.seed = world_seed + 99;
    noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH;
    noise.frequency = 0.012;
    noise.fractal_octaves = 3;
    var img:Image = noise.get_seamless_image(256, 256, false, false, 0.1, true);
    return ImageTexture.create_from_image(img);

# The cloud colour of the moment: the sky's horizon colour, lightened the more daylight there is (so a night sky gives dark clouds).
func set_tint(horizon:Color) -> void:
    var day:float = clampf(horizon.get_luminance() * 2.4, 0.0, 1.0);
    _bank_mat.set_shader_parameter("tint", horizon.lerp(Color(1, 1, 1), 0.38 * day));
    _floor_mat.set_shader_parameter("tint", horizon.lerp(Color(1, 1, 1), 0.2 * day));

# The wispy edges follow the player's setting.
func apply_settings() -> void:
    if _bank_mat != null:
        _bank_mat.set_shader_parameter("wispy", 1.0 if Settings.wispy_clouds_on() else 0.0);

func puff_count() -> int:
    return _puffs.multimesh.instance_count;

func floor_height() -> float:
    return _floor.position.y;
