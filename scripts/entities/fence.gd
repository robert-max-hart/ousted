# ----------------------------------------------------------------
# Fence
#     A fence or low wall drawn around a building's footprint, in
#     world space so it follows the ground (posts stand at the
#     corner heights, rails slope between them). Decoration only:
#     citizens still walk through. One gap on the south side is the
#     gate, marked by a taller post at each end. It shows while the
#     building is finished and is rebuilt when the terrain changes
#     (Building.on_terrain_changed). The pieces are models
#     (assets/models/structures, made by tools/make_structures.py):
#     a post, a one-cell rail that is stretched to the slope, and a
#     gate post, and for wood, field and stone fences a gate leaf
#     that swings open (inwards) while a citizen is near it.
#     Kinds: wood (posts and two rails), field (low, for crop fields),
#     stone (a low wall with piers), rope (short posts and one rope,
#     for stockpiles).
# ----------------------------------------------------------------
class_name Fence extends Node3D;

const DIR:String = "res://assets/models/structures/";
const OPEN_ANGLE :float = 1.35;      # radians the gate leaf swings open
const OPEN_NEAR  :float = 2.0;       # metres from the gate a citizen makes it open
const SWING_RATE :float = 3.5;       # radians a second


var _b          :Building;
var _kind       :StringName;
var _gap        :int;
var _posts      :MultiMeshInstance3D;
var _rails      :MultiMeshInstance3D;
var _gates      :MultiMeshInstance3D;
var _was_done   :bool = false;
var _leaf       :MeshInstance3D = null;       # the gate itself (none for a rope fence or a wider gap)
var _hinge      :Vector3 = Vector3.ZERO;
var _mouth      :Vector2 = Vector2.ZERO;      # the middle of the gap, on the ground plan (where citizens pass)
var _swing      :float = 0.0;                 # 0 shut to OPEN_ANGLE open
var _look_t     :float = 0.0;

func _init(b:Building, kind:StringName, gap:int = 1) -> void:
    _b = b;
    _kind = kind;
    _gap = gap;
    top_level = true;
    var tex:StringName = &"planks";
    var tint:Color = Color(0.62, 0.5, 0.36);
    match kind:
        &"stone":
            tex = &"stone";
            tint = Color(0.62, 0.6, 0.57);
        &"rope":
            tint = Color(0.5, 0.4, 0.3);
    _posts = _layer(&"post", tex, tint);
    _gates = _layer(&"gate", tex, tint);
    _rails = _layer(&"rail", tex, Color(0.74, 0.66, 0.46) if kind == &"rope" else tint);
    if gap == 1 and kind != &"rope":
        _leaf = MeshInstance3D.new();
        _leaf.mesh = load("%sfence_%s_leaf.obj" % [Settings.model_dir(DIR), kind]) as Mesh;
        _leaf.material_override = SurfaceTextures.snowy_parts_material() if kind == &"stone" else SurfaceTextures.snowy_material(tex, tint, true, true);       # (the iron gate keeps its own colours)
        add_child(_leaf);

func _layer(part:StringName, tex:StringName, tint:Color) -> MultiMeshInstance3D:
    var mm:MultiMesh = MultiMesh.new();
    mm.transform_format = MultiMesh.TRANSFORM_3D;
    mm.mesh = load("%sfence_%s_%s.obj" % [Settings.model_dir(DIR), _kind, part]) as Mesh;
    var mat:ShaderMaterial = SurfaceTextures.snowy_material(tex, tint, true, true);       # (the models shade their parts: nails, stone courses, caps; snow lies on the tops)
    var mmi:MultiMeshInstance3D = MultiMeshInstance3D.new();
    mmi.multimesh = mm;
    mmi.material_override = mat;
    add_child(mmi);
    return mmi;

func _process(delta:float) -> void:
    var done:bool = _b.state == Building.State.COMPLETE;
    visible = done;
    if done and not _was_done:
        rebuild();
    _was_done = done;
    if done and _leaf != null:
        _swing_gate(delta);

# The gate opens while a citizen is near the gap and shuts again after (it freezes with the game when paused).
func _swing_gate(delta:float) -> void:
    _look_t -= delta;
    var want:float = _swing;
    if _look_t <= 0.0:
        _look_t = 0.2;
        _near = false;
        for p in _b.world.pawns:
            if not p.removed and not p.indoors and Vector2(p.position.x, p.position.z).distance_to(_mouth) < OPEN_NEAR:
                _near = true;
                break;
    want = OPEN_ANGLE if _near else 0.0;
    var dt:float = delta * minf(World.fx_speed(), 3.0);
    _swing = move_toward(_swing, want, SWING_RATE * dt);
    _leaf.rotation.y = _swing;          # (positive turns +x toward -z: into the enclosure)

var _near:bool = false;

func rebuild() -> void:
    var t:Terrain = _b.world.terrain;
    var r:Rect2i = _b.rect();
    var post_aabb:AABB = _posts.multimesh.mesh.get_aabb();
    var gate_aabb:AABB = _gates.multimesh.mesh.get_aabb();
    var rail_h:float = _rails.multimesh.mesh.get_aabb().size.y;
    var gate:int = r.position.x + r.size.x / 2 - _gap / 2;
    # edges as pairs of corner points
    var edges:Array = [];
    for x in range(r.position.x, r.end.x):
        edges.append([Vector2i(x, r.position.y), Vector2i(x + 1, r.position.y)]);
        if x < gate or x >= gate + _gap:
            edges.append([Vector2i(x, r.end.y), Vector2i(x + 1, r.end.y)]);
    for z in range(r.position.y, r.end.y):
        edges.append([Vector2i(r.position.x, z), Vector2i(r.position.x, z + 1)]);
        edges.append([Vector2i(r.end.x, z), Vector2i(r.end.x, z + 1)]);
    var points:Dictionary = {};
    for e in edges:
        points[e[0]] = true;
        points[e[1]] = true;
    var gate_posts:Array[Vector2i] = [];
    if _kind == &"wood" or _kind == &"stone":
        gate_posts.append(Vector2i(gate, r.end.y));
        gate_posts.append(Vector2i(gate + _gap, r.end.y));
    var rails_per:int = 2 if _kind == &"wood" or _kind == &"field" else 1;
    var pm:MultiMesh = _posts.multimesh;
    var gm:MultiMesh = _gates.multimesh;
    gm.instance_count = 0;
    var plain:Array[Vector2i] = [];
    var tall:Array[Vector2i] = [];
    for p in points:
        if p in gate_posts:
            tall.append(p);
        else:
            plain.append(p);
    pm.instance_count = plain.size();
    for i in plain.size():
        pm.set_instance_transform(i, _post_at(t, plain[i], -post_aabb.position.y));
    gm.instance_count = tall.size();
    for i in tall.size():
        gm.set_instance_transform(i, _post_at(t, tall[i], -gate_aabb.position.y));
    if _leaf != null:
        # hinged on the west gate post, which stands at the gap's west edge, shutting across to the east one
        var hp:Vector2i = Vector2i(gate, r.end.y);
        _hinge = Vector3(hp.x + 0.07, t.corner(hp.x, hp.y) - 0.05, hp.y);
        _leaf.position = _hinge;
        _mouth = Vector2(gate + _gap * 0.5, r.end.y + 0.3);
    var rm:MultiMesh = _rails.multimesh;
    rm.instance_count = edges.size() * rails_per;
    var post_h:float = post_aabb.size.y;
    var i:int = 0;
    for e in edges:
        var a:Vector3 = Vector3(e[0].x, t.corner(e[0].x, e[0].y), e[0].y);
        var b:Vector3 = Vector3(e[1].x, t.corner(e[1].x, e[1].y), e[1].y);
        var along:Vector3 = b - a;
        var xaxis:Vector3 = along.normalized();
        var zaxis:Vector3 = xaxis.cross(Vector3.UP).normalized();
        var yaxis:Vector3 = zaxis.cross(xaxis);
        var basis:Basis = Basis(xaxis * along.length(), yaxis, zaxis);
        var mid:Vector3 = (a + b) * 0.5;
        var heights:Array = [0.32, 0.62] if _kind == &"wood" else [0.18, 0.4] if _kind == &"field" else [rail_h * 0.5 - 0.05 if _kind == &"stone" else post_h * 0.85];
        for hgt in heights:
            rm.set_instance_transform(i, Transform3D(basis, mid + Vector3(0, hgt, 0)));
            i += 1;

# A post at a corner of the ground, standing on it (the model's foot is `below` under its origin), turned a little at random so they are not all alike.
func _post_at(t:Terrain, p:Vector2i, below:float) -> Transform3D:
    var yaw:float = float(hash(p) & 0xff) / 255.0 * 0.6;
    return Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, t.corner(p.x, p.y) + below - 0.05, p.y));
