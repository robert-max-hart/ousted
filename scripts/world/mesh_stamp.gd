# ----------------------------------------------------------------
# MeshStamp
#     Builds one mesh from copies of other meshes, each moved by a
#     transform (a bridge from cell after cell of deck). Reads the
#     first surface of each source; vertex colours and normals come
#     along. Start it with a stamp, add as many copies as needed,
#     then build().
# ----------------------------------------------------------------
class_name MeshStamp extends RefCounted;

var _verts :PackedVector3Array = PackedVector3Array();
var _norms :PackedVector3Array = PackedVector3Array();
var _colors:PackedColorArray = PackedColorArray();
var _index :PackedInt32Array = PackedInt32Array();

# Adds a copy of `src`, moved by `xf`.
func add(src:Mesh, xf:Transform3D) -> void:
    var arrays:Array = src.surface_get_arrays(0);
    var v:PackedVector3Array = arrays[Mesh.ARRAY_VERTEX];
    var n:PackedVector3Array = arrays[Mesh.ARRAY_NORMAL];
    var c:PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray();
    var idx:PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array();
    var base:int = _verts.size();
    for i in v.size():
        _verts.append(xf * v[i]);
        _norms.append((xf.basis * n[i]).normalized());
        _colors.append(c[i] if i < c.size() else Color.WHITE);
    if idx.is_empty():
        for i in v.size():
            _index.append(base + i);
    else:
        for i in idx:
            _index.append(base + i);

func is_empty() -> bool:
    return _verts.is_empty();

# The mesh of everything added so far, with `mat` on its one surface.
func build(mat:Material) -> ArrayMesh:
    var mesh:ArrayMesh = ArrayMesh.new();
    if _verts.is_empty():
        return mesh;
    var arrays:Array = [];
    arrays.resize(Mesh.ARRAY_MAX);
    arrays[Mesh.ARRAY_VERTEX] = _verts;
    arrays[Mesh.ARRAY_NORMAL] = _norms;
    arrays[Mesh.ARRAY_COLOR] = _colors;
    arrays[Mesh.ARRAY_INDEX] = _index;
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays);
    mesh.surface_set_material(0, mat);
    return mesh;
