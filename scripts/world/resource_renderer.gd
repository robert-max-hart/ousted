# ----------------------------------------------------------------
# ResourceRenderer
#     Draws every ResourceNode through one MultiMesh per kind, plus
#     floating markers over designated nodes. Rebuilds lazily.
# ----------------------------------------------------------------
class_name ResourceRenderer extends Node3D;

const DESIGNATED_TINT:Color = Color(1.0, 0.8, 0.45);
const CANOPY_BY_SEASON:Array[Color] = [
    Color(0.16, 0.38, 0.18), Color(0.15, 0.35, 0.16), Color(0.2, 0.34, 0.16), Color(0.55, 0.62, 0.6),
];
const BUSH_BY_SEASON:Array[Color] = [
    Color(0.3, 0.55, 0.22), Color(0.28, 0.5, 0.2), Color(0.55, 0.42, 0.2), Color(0.45, 0.42, 0.38),
];

var _layers     :Dictionary = {};   # kind -> MultiMeshInstance3D
var _markers    :MultiMeshInstance3D;
var _canopy_mat :StandardMaterial3D;
var _bush_mat   :StandardMaterial3D;
var _dirty      :bool = true;

func _ready() -> void:
    _canopy_mat = _make_material(CANOPY_BY_SEASON[0]);
    _bush_mat = _make_material(BUSH_BY_SEASON[0]);
    var trunk_mat:StandardMaterial3D = _make_material(Color(0.4, 0.27, 0.17));

    var tree:ArrayMesh = ArrayMesh.new();
    var trunk:CylinderMesh = CylinderMesh.new();
    trunk.top_radius = 0.1;
    trunk.bottom_radius = 0.16;
    trunk.height = 1.4;
    trunk.radial_segments = 6;
    _add_part(tree, trunk, Transform3D(Basis(), Vector3(0, 0.7, 0)), trunk_mat);
    var canopy:CylinderMesh = CylinderMesh.new();
    canopy.top_radius = 0.0;
    canopy.bottom_radius = 0.95;
    canopy.height = 2.8;
    canopy.radial_segments = 7;
    _add_part(tree, canopy, Transform3D(Basis(), Vector3(0, 2.4, 0)), _canopy_mat);

    var rock_shape:SphereMesh = SphereMesh.new();
    rock_shape.radius = 0.7;
    rock_shape.height = 1.0;
    rock_shape.radial_segments = 6;
    rock_shape.rings = 3;
    var rock:ArrayMesh = ArrayMesh.new();
    _add_part(rock, rock_shape, Transform3D(Basis(), Vector3(0, 0.25, 0)), _make_material(Color(0.55, 0.54, 0.52)));
    var ore:ArrayMesh = ArrayMesh.new();
    _add_part(ore, rock_shape, Transform3D(Basis(), Vector3(0, 0.25, 0)), _make_material(Color(0.58, 0.36, 0.3)));

    var bush_shape:SphereMesh = SphereMesh.new();
    bush_shape.radius = 0.45;
    bush_shape.height = 0.7;
    bush_shape.radial_segments = 8;
    bush_shape.rings = 4;
    var bush:ArrayMesh = ArrayMesh.new();
    _add_part(bush, bush_shape, Transform3D(Basis(), Vector3(0, 0.3, 0)), _bush_mat);

    var cap_shape:SphereMesh = SphereMesh.new();
    cap_shape.radius = 0.22;
    cap_shape.height = 0.3;
    cap_shape.radial_segments = 6;
    cap_shape.rings = 3;
    var mushroom:ArrayMesh = ArrayMesh.new();
    _add_part(mushroom, cap_shape, Transform3D(Basis(), Vector3(-0.2, 0.1, 0.1)), _make_material(Color(0.72, 0.5, 0.3)));
    _add_part(mushroom, cap_shape, Transform3D(Basis(), Vector3(0.15, 0.1, -0.1)), _make_material(Color(0.8, 0.35, 0.25)));
    _add_part(mushroom, cap_shape, Transform3D(Basis(), Vector3(0.05, 0.1, 0.25)), _make_material(Color(0.72, 0.5, 0.3)));
    var hazel_shape:SphereMesh = SphereMesh.new();
    hazel_shape.radius = 0.6;
    hazel_shape.height = 1.1;
    hazel_shape.radial_segments = 8;
    hazel_shape.rings = 4;
    var hazel:ArrayMesh = ArrayMesh.new();
    _add_part(hazel, hazel_shape, Transform3D(Basis(), Vector3(0, 0.5, 0)), _make_material(Color(0.5, 0.52, 0.2)));

    _layers[&"tree"] = _make_layer(tree);
    _layers[&"rock"] = _make_layer(rock);
    _layers[&"ore"] = _make_layer(ore);
    _layers[&"bush"] = _make_layer(bush);
    _layers[&"mushroom"] = _make_layer(mushroom);
    _layers[&"hazel"] = _make_layer(hazel);

    var marker_shape:SphereMesh = SphereMesh.new();
    marker_shape.radius = 0.18;
    marker_shape.height = 0.36;
    marker_shape.radial_segments = 4;
    marker_shape.rings = 2;
    var marker_mat:StandardMaterial3D = StandardMaterial3D.new();
    marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED;
    marker_mat.albedo_color = Color(1.0, 0.6, 0.1);
    var marker:ArrayMesh = ArrayMesh.new();
    _add_part(marker, marker_shape, Transform3D(), marker_mat);
    _markers = _make_layer(marker);
    _markers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;

func mark_dirty() -> void:
    _dirty = true;

func set_season(s:int) -> void:
    _canopy_mat.albedo_color = CANOPY_BY_SEASON[s];
    _bush_mat.albedo_color = BUSH_BY_SEASON[s];

func _process(_delta:float) -> void:
    if _dirty:
        _dirty = false;
        _rebuild();

func _rebuild() -> void:
    var world:World = World.instance;
    var by_kind:Dictionary = {};
    for k in _layers:
        by_kind[k] = [];
    var marked:Array[ResourceNode] = [];
    for rn in world.nodes:
        by_kind[rn.kind].append(rn);
        if rn.designated:
            marked.append(rn);

    for k in _layers:
        var list:Array = by_kind[k];
        var mm:MultiMesh = (_layers[k] as MultiMeshInstance3D).multimesh;
        mm.instance_count = list.size();
        for i in list.size():
            var rn:ResourceNode = list[i];
            var s:float = rn.scale;
            if not rn.is_mature():
                s *= lerpf(0.25, 1.0, rn.growth);
            var tint:Color = Color.WHITE;
            if rn.regrows:
                # bushes shrink and dull as they are picked clean
                var ratio:float = float(rn.amount) / rn.max_amount;
                s *= 0.7 + 0.3 * ratio;
                tint = Color(1.0, lerpf(0.8, 1.0, 1.0 - ratio), lerpf(0.8, 1.0, 1.0 - ratio));
            if rn.designated:
                tint = DESIGNATED_TINT;
            mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rn.yaw).scaled(Vector3.ONE * s), _node_position(world, rn)));
            mm.set_instance_color(i, tint);

    var mmm:MultiMesh = _markers.multimesh;
    mmm.instance_count = marked.size();
    for i in marked.size():
        var top:float = 4.2 if marked[i].kind == &"tree" else 1.6;
        mmm.set_instance_transform(i, Transform3D(Basis(), _node_position(world, marked[i]) + Vector3(0, top, 0)));
        mmm.set_instance_color(i, Color.WHITE);

func _node_position(world:World, rn:ResourceNode) -> Vector3:
    var x:float = rn.cell.x + 0.5 + rn.offset.x;
    var z:float = rn.cell.y + 0.5 + rn.offset.y;
    return Vector3(x, world.terrain.height_at(x, z), z);

func _make_material(c:Color) -> StandardMaterial3D:
    var m:StandardMaterial3D = StandardMaterial3D.new();
    m.albedo_color = c;
    m.vertex_color_use_as_albedo = true;    # multiplies in the per-instance tint
    m.vertex_color_is_srgb = true;
    m.roughness = 0.95;
    return m;

func _make_layer(mesh:Mesh) -> MultiMeshInstance3D:
    var mm:MultiMesh = MultiMesh.new();
    mm.transform_format = MultiMesh.TRANSFORM_3D;
    mm.use_colors = true;
    mm.mesh = mesh;
    var mmi:MultiMeshInstance3D = MultiMeshInstance3D.new();
    mmi.multimesh = mm;
    add_child(mmi);
    return mmi;

# Bakes a primitive into target as a new surface, offset by xf.
static func _add_part(target:ArrayMesh, prim:PrimitiveMesh, xf:Transform3D, mat:Material) -> void:
    var arrays:Array = prim.get_mesh_arrays();
    var verts:PackedVector3Array = arrays[Mesh.ARRAY_VERTEX];
    var normals:PackedVector3Array = arrays[Mesh.ARRAY_NORMAL];
    for i in verts.size():
        verts[i] = xf * verts[i];
        normals[i] = (xf.basis * normals[i]).normalized();
    arrays[Mesh.ARRAY_VERTEX] = verts;
    arrays[Mesh.ARRAY_NORMAL] = normals;
    arrays[Mesh.ARRAY_TANGENT] = null;
    target.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays);
    target.surface_set_material(target.get_surface_count() - 1, mat);
