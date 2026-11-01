# ----------------------------------------------------------------
# FireRenderer
#     Draws the flames: for each burning cell a few flickering cones of
#     fire (small for a campfire, big over a tree or a building) in a
#     MultiMesh, rebuilt when the fires change and flickering every
#     frame; smoke rising from a few of the burning cells, a handful of
#     warm lights near the camera that show at night, and the dark scorch
#     on ground that has burnt, fading back to green over some days.
#     A child of World (world.fire_view).
# ----------------------------------------------------------------
class_name FireRenderer extends Node3D;

const MAX_FLAMES:int = 900;
const MAX_SCORCH:int = 1400;
const SMOKE_EMITTERS:int = 6;
const LIGHTS:int = 4;
const LIGHT_EVERY:float = 0.5;         # seconds between choosing which fires the lights stand at
const OUTER:Color = Color(1.0, 0.42, 0.08);
const INNER:Color = Color(1.0, 0.82, 0.3);

var world:World;
var _mm:MultiMesh;
var _flames:Array[Dictionary] = [];       # {pos, size, phase, inner}
var _scorch_mm:MultiMesh;
var _smoke:Array[CPUParticles3D] = [];
var _lights:Array[OmniLight3D] = [];
var _light_at:Array[Vector3] = [];
var _light_timer:float = 0.0;
var _scorch_age_hours:float = -1.0;

func _init(w:World) -> void:
    world = w;

func _ready() -> void:
    var cone:CylinderMesh = CylinderMesh.new();
    cone.top_radius = 0.0;
    cone.bottom_radius = 0.3;
    cone.height = 1.0;
    cone.radial_segments = 5;
    cone.rings = 1;
    var mat:StandardMaterial3D = StandardMaterial3D.new();
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED;
    mat.vertex_color_use_as_albedo = true;
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA;
    mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD;
    mat.albedo_color = Color(1, 1, 1, 0.85);
    cone.material = mat;
    _mm = MultiMesh.new();
    _mm.transform_format = MultiMesh.TRANSFORM_3D;
    _mm.use_colors = true;
    _mm.mesh = cone;
    _mm.instance_count = MAX_FLAMES;
    _mm.visible_instance_count = 0;
    var inst:MultiMeshInstance3D = MultiMeshInstance3D.new();
    inst.multimesh = _mm;
    inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
    inst.extra_cull_margin = 50.0;
    add_child(inst);
    _make_scorch();
    _make_smoke();
    _make_lights();

func _process(delta:float) -> void:
    if world.fires == null:
        return;
    if world.fires.changed:
        world.fires.changed = false;
        _rebuild();
        _rebuild_scorch();
        _assign_smoke();
    _update_lights(delta);
    var speed:float = GameClock.speed() if not world.is_backdrop else 1.0;
    for sm in _smoke:
        sm.speed_scale = speed;
    var n:int = _flames.size();
    if n == 0:
        _mm.visible_instance_count = 0;
        return;
    var t:float = Time.get_ticks_msec() * 0.001 * (1.0 if GameClock.speed() > 0.0 else 0.0) + 0.0;
    for i in n:
        var f:Dictionary = _flames[i];
        var flick:float = 0.8 + 0.25 * sin(t * 9.0 + f["phase"]) + 0.12 * sin(t * 17.0 + f["phase"] * 2.3);
        var s:float = f["size"] * flick;
        var sway:float = 0.06 * sin(t * 5.0 + f["phase"]);
        var xf:Transform3D = Transform3D(Basis().scaled(Vector3(s * 0.9, s * (1.3 if not f["inner"] else 0.9), s * 0.9)), f["pos"] + Vector3(sway, 0.0, sway * 0.7));
        _mm.set_instance_transform(i, xf);
        _mm.set_instance_color(i, INNER if f["inner"] else OUTER);
    _mm.visible_instance_count = n;

# The flames from the fires: a big and a small cone on each cell, over what burns there.
func _rebuild() -> void:
    _flames.clear();
    for c in world.fires.cells:
        var fc:Fires.FireCell = world.fires.cells[c];
        var x:float = c.x + 0.5;
        var z:float = c.y + 0.5;
        var ground:float = world.terrain.height_at(x, z);
        var height:float = 0.0;
        var size:float = 0.8;
        if fc.kind == Fires.Kind.CAMP:
            size = 0.55;
        else:
            var rn:ResourceNode = world.node_at[world.idx(c)];
            if rn != null and rn.is_tree():
                height = 1.2;
                size = 1.5;
            elif fc.building != null:
                height = 1.3;
                size = 1.3;
        var h:int = hash(c);
        for k in 2:
            if _flames.size() >= MAX_FLAMES:
                return;
            var jitter:Vector3 = Vector3((posmod(h >> (k * 4), 7) - 3) * 0.06, 0.0, (posmod(h >> (k * 4 + 2), 7) - 3) * 0.06);
            _flames.append({"pos": Vector3(x, ground + height, z) + jitter, "size": size * (1.0 if k == 0 else 0.6), "phase": float(posmod(h, 100)) * 0.17 + k * 1.9, "inner": k == 1});

# --------------------------------
# Scorch: dark patches on burnt ground

func _make_scorch() -> void:
    var quad:QuadMesh = QuadMesh.new();
    quad.size = Vector2(1.05, 1.05);
    quad.orientation = PlaneMesh.FACE_Y;
    var mat:StandardMaterial3D = StandardMaterial3D.new();
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA;
    mat.vertex_color_use_as_albedo = true;
    mat.albedo_color = Color(1, 1, 1, 1);
    mat.roughness = 1.0;
    mat.cull_mode = BaseMaterial3D.CULL_DISABLED;
    quad.material = mat;
    _scorch_mm = MultiMesh.new();
    _scorch_mm.transform_format = MultiMesh.TRANSFORM_3D;
    _scorch_mm.use_colors = true;
    _scorch_mm.mesh = quad;
    _scorch_mm.instance_count = MAX_SCORCH;
    _scorch_mm.visible_instance_count = 0;
    var inst:MultiMeshInstance3D = MultiMeshInstance3D.new();
    inst.multimesh = _scorch_mm;
    inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
    inst.extra_cull_margin = 80.0;
    add_child(inst);

# One dark square on each burnt cell, fainter the longer ago it burnt.
func _rebuild_scorch() -> void:
    var n:int = 0;
    var span:float = Fires.SCORCH_DAYS * GameClock.HOURS_PER_DAY;
    for c in world.fires.scorch:
        if n >= MAX_SCORCH:
            break;
        var age:float = (GameClock.total_hours - float(world.fires.scorch[c])) / span;
        if age >= 1.0 or age < 0.0:
            continue;
        var x:float = c.x + 0.5;
        var z:float = c.y + 0.5;
        _scorch_mm.set_instance_transform(n, Transform3D(Basis(), Vector3(x, world.terrain.height_at(x, z) + 0.05, z)));
        _scorch_mm.set_instance_color(n, Color(0.07, 0.05, 0.04, 0.72 * (1.0 - age)));
        n += 1;
    _scorch_mm.visible_instance_count = n;

# --------------------------------
# Smoke

func _make_smoke() -> void:
    var puff:SphereMesh = SphereMesh.new();
    puff.radius = 0.4;
    puff.height = 0.8;
    puff.radial_segments = 6;
    puff.rings = 3;
    var mat:StandardMaterial3D = StandardMaterial3D.new();
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA;
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED;
    mat.albedo_color = Color(0.2, 0.19, 0.19, 0.55);
    puff.material = mat;
    for i in SMOKE_EMITTERS:
        var p:CPUParticles3D = CPUParticles3D.new();
        p.mesh = puff;
        p.amount = 16;
        p.lifetime = 4.5;
        p.direction = Vector3.UP;
        p.spread = 18.0;
        p.initial_velocity_min = 1.2;
        p.initial_velocity_max = 2.0;
        p.gravity = Vector3(0.5, 0.0, 0.2);          # a breeze
        p.scale_amount_min = 0.8;
        p.scale_amount_max = 1.8;
        p.emitting = false;
        p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
        add_child(p);
        _smoke.append(p);

# Smoke over the biggest fires: a tree, a building, then the rest, a few of them (they are picked by cell so they do not jump about).
func _assign_smoke() -> void:
    var picks:Array[Vector3] = [];
    var keys:Array = world.fires.cells.keys();
    keys.sort_custom(func(a:Vector2i, b:Vector2i) -> bool:
        var fa:Fires.FireCell = world.fires.cells[a];
        var fb:Fires.FireCell = world.fires.cells[b];
        var wa:int = (1 if fa.kind == Fires.Kind.WILD else 0) * 2 + (1 if fa.building != null else 0);
        var wb:int = (1 if fb.kind == Fires.Kind.WILD else 0) * 2 + (1 if fb.building != null else 0);
        return wa > wb or (wa == wb and hash(a) < hash(b)));
    var step:int = maxi(1, keys.size() / SMOKE_EMITTERS);
    var i:int = 0;
    while i < keys.size() and picks.size() < SMOKE_EMITTERS:
        var c:Vector2i = keys[i];
        var fc:Fires.FireCell = world.fires.cells[c];
        var rn:ResourceNode = world.node_at[world.idx(c)];
        var h:float = 1.5 if (fc.building != null or (rn != null and rn.is_tree())) else 0.5;
        picks.append(Vector3(c.x + 0.5, world.terrain.height_at(c.x + 0.5, c.y + 0.5) + h, c.y + 0.5));
        i += step;
    for k in _smoke.size():
        var sm:CPUParticles3D = _smoke[k];
        sm.emitting = k < picks.size();
        if k < picks.size():
            sm.position = picks[k];

# --------------------------------
# Warm light from the fires nearest the camera: strong at night, faint by day

func _make_lights() -> void:
    for i in LIGHTS:
        var l:OmniLight3D = OmniLight3D.new();
        l.light_color = Color(1.0, 0.55, 0.2);
        l.omni_range = 10.0;
        l.light_energy = 0.0;
        l.shadow_enabled = false;
        l.visible = false;
        add_child(l);
        _lights.append(l);

func _update_lights(delta:float) -> void:
    _light_timer -= delta;
    if _light_timer <= 0.0:
        _light_timer = LIGHT_EVERY;
        _choose_light_spots();
    var h:float = GameClock.hour();
    var dark:float = 1.0 - smoothstep(5.0, 8.0, h) * (1.0 - smoothstep(18.0, 21.0, h));
    var t:float = Time.get_ticks_msec() * 0.001;
    for k in _lights.size():
        var l:OmniLight3D = _lights[k];
        l.visible = k < _light_at.size();
        if k < _light_at.size():
            l.position = _light_at[k];
            l.light_energy = (0.35 + 1.7 * dark) * (0.85 + 0.15 * sin(t * 11.0 + k * 2.0) + 0.08 * sin(t * 23.0 + k));

func _choose_light_spots() -> void:
    _light_at.clear();
    if not world.fires.active():
        return;
    var cam:Camera3D = get_viewport().get_camera_3d();
    if cam == null:
        return;
    var from:Vector3 = cam.global_position;
    var keys:Array = world.fires.cells.keys();
    keys.sort_custom(func(a:Vector2i, b:Vector2i) -> bool:
        return Vector2(a.x - from.x, a.y - from.z).length_squared() < Vector2(b.x - from.x, b.y - from.z).length_squared());
    var spread:Array[Vector2i] = [];
    for c in keys:
        var far_enough:bool = true;
        for o in spread:
            if Vector2(c - o).length() < 5.0:
                far_enough = false;
                break;
        if far_enough:
            spread.append(c);
            _light_at.append(Vector3(c.x + 0.5, world.terrain.height_at(c.x + 0.5, c.y + 0.5) + 1.6, c.y + 0.5));
        if spread.size() >= LIGHTS:
            break;
