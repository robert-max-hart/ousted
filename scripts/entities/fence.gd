# ----------------------------------------------------------------
# Fence
#     A fence or low wall drawn around a building's footprint, in
#     world space so it follows the ground (posts stand at the
#     corner heights, rails slope between them). Decoration only:
#     citizens still walk through. One gap on the south side is the
#     gate. It shows while the building is finished and is rebuilt
#     when the terrain changes (Building.on_terrain_changed).
#     Kinds: wood (posts and two rails), stone (a low wall with
#     piers), rope (short posts and one rope, for stockpiles).
# ----------------------------------------------------------------
class_name Fence extends Node3D;

var _b          :Building;
var _kind       :StringName;
var _gap        :int;
var _posts      :MultiMeshInstance3D;
var _rails      :MultiMeshInstance3D;
var _was_done   :bool = false;

func _init(b:Building, kind:StringName, gap:int = 1) -> void:
    _b = b;
    _kind = kind;
    _gap = gap;
    top_level = true;
    var post_size:Vector3 = Vector3(0.1, 0.9, 0.1);
    var rail_size:Vector3 = Vector3(1.0, 0.07, 0.05);
    var tex:StringName = &"planks";
    var tint:Color = Color(0.62, 0.5, 0.36);
    match kind:
        &"stone":
            post_size = Vector3(0.26, 0.62, 0.26);
            rail_size = Vector3(1.0, 0.42, 0.16);
            tex = &"stone";
            tint = Color(0.62, 0.6, 0.57);
        &"field":
            post_size = Vector3(0.08, 0.5, 0.08);
            rail_size = Vector3(1.0, 0.05, 0.04);
        &"rope":
            post_size = Vector3(0.1, 0.6, 0.1);
            rail_size = Vector3(1.0, 0.03, 0.03);
            tint = Color(0.5, 0.4, 0.3);
    _posts = _layer(post_size, tex, tint);
    var rail_tex:StringName = tex;
    var rail_tint:Color = Color(0.74, 0.66, 0.46) if kind == &"rope" else tint;
    _rails = _layer(rail_size, rail_tex, rail_tint);

func _layer(dims:Vector3, tex:StringName, tint:Color) -> MultiMeshInstance3D:
    var box:BoxMesh = BoxMesh.new();
    box.size = dims;
    var mm:MultiMesh = MultiMesh.new();
    mm.transform_format = MultiMesh.TRANSFORM_3D;
    mm.mesh = box;
    var mat:StandardMaterial3D = SurfaceTextures.material(tex, tint);
    mat.uv1_world_triplanar = true;
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
    var post_h:float = (_posts.multimesh.mesh as BoxMesh).size.y;
    var rail_h:float = (_rails.multimesh.mesh as BoxMesh).size.y;
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
    var rails_per:int = 2 if _kind == &"wood" or _kind == &"field" else 1;
    var pm:MultiMesh = _posts.multimesh;
    pm.instance_count = points.size();
    var i:int = 0;
    for p in points:
        pm.set_instance_transform(i, Transform3D(Basis(), Vector3(p.x, t.corner(p.x, p.y) + post_h * 0.5 - 0.05, p.y)));
        i += 1;
    var rm:MultiMesh = _rails.multimesh;
    rm.instance_count = edges.size() * rails_per;
    i = 0;
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
