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
#     gate post.
#     Kinds: wood (posts and two rails), field (low, for crop fields),
#     stone (a low wall with piers), rope (short posts and one rope,
#     for stockpiles).
# ----------------------------------------------------------------
class_name Fence extends Node3D;

const DIR:String = "res://assets/models/structures/";

var _b          :Building;
var _kind       :StringName;
var _gap        :int;
var _posts      :MultiMeshInstance3D;
var _rails      :MultiMeshInstance3D;
var _gates      :MultiMeshInstance3D;
var _was_done   :bool = false;

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

func _layer(part:StringName, tex:StringName, tint:Color) -> MultiMeshInstance3D:
    var mm:MultiMesh = MultiMesh.new();
    mm.transform_format = MultiMesh.TRANSFORM_3D;
    mm.mesh = load("%sfence_%s_%s.obj" % [DIR, _kind, part]) as Mesh;
    var mat:StandardMaterial3D = SurfaceTextures.material(tex, tint);
    mat.uv1_world_triplanar = true;
    mat.vertex_color_use_as_albedo = true;           # the models shade their parts (nails, stone courses, caps)
    var mmi:MultiMeshInstance3D = MultiMeshInstance3D.new();
    mmi.multimesh = mm;
    mmi.material_override = mat;
    add_child(mmi);
    return mmi;

func _process(_delta:float) -> void:
    var done:bool = _b.state == Building.State.COMPLETE;
    visible = done;
    if done and not _was_done:
        rebuild();
    _was_done = done;

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
