# ----------------------------------------------------------------
# RoadDetail
#     Scatters small stones over road cells (a few per cell, always
#     in the same places for the same cell), so roads read as rough
#     ground up close. One MultiMesh, rebuilt when the terrain changes.
# ----------------------------------------------------------------
class_name RoadDetail extends Node3D;

const PER_CELL  :int = 3;
const STONES    :Array[Color] = [Color(0.48, 0.42, 0.35), Color(0.36, 0.32, 0.28), Color(0.56, 0.48, 0.38), Color(0.28, 0.26, 0.24)];

var _world      :World;
var _mmi        :MultiMeshInstance3D;
var _dirty      :bool = true;

func _init(w:World) -> void:
    _world = w;
    var stone:SphereMesh = SphereMesh.new();
    stone.radius = 0.06;
    stone.height = 0.07;
    stone.radial_segments = 5;
    stone.rings = 2;
    var mat:StandardMaterial3D = StandardMaterial3D.new();
    mat.vertex_color_use_as_albedo = true;
    mat.vertex_color_is_srgb = true;
    mat.roughness = 1.0;
    var mm:MultiMesh = MultiMesh.new();
    mm.transform_format = MultiMesh.TRANSFORM_3D;
    mm.use_colors = true;
    mm.mesh = stone;
    _mmi = MultiMeshInstance3D.new();
    _mmi.multimesh = mm;
    _mmi.material_override = mat;
    _mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
    add_child(_mmi);

func _ready() -> void:
    _world.terrain.ground_changed.connect(func(_r:Rect2i) -> void: _dirty = true);       # a road laid or removed, or the ground reshaped

func _process(_delta:float) -> void:
    if _dirty:
        _dirty = false;
        _rebuild();

func _rebuild() -> void:
    var t:Terrain = _world.terrain;
    var cells:Array[Vector2i] = [];
    for z in Terrain.SIZE:
        for x in Terrain.SIZE:
            if t.overlay[z * Terrain.SIZE + x] == Terrain.Overlay.ROAD:
                cells.append(Vector2i(x, z));
    var mm:MultiMesh = _mmi.multimesh;
    mm.instance_count = cells.size() * PER_CELL;
    var n:int = 0;
    for c in cells:
        for k in PER_CELL:
            var h:int = (c.x * 73856093) ^ (c.y * 19349663) ^ (k * 83492791);
            var fx:float = float(h & 255) / 255.0;
            var fz:float = float((h >> 8) & 255) / 255.0;
            var fs:float = float((h >> 16) & 255) / 255.0;
            var x:float = c.x + 0.1 + fx * 0.8;
            var z:float = c.y + 0.1 + fz * 0.8;
            var s:float = 0.7 + fs * 0.9;
            mm.set_instance_transform(n, Transform3D(Basis(Vector3.UP, fx * TAU).scaled(Vector3(s, s, s)), Vector3(x, t.height_at(x, z) + 0.01, z)));
            mm.set_instance_color(n, STONES[(h >> 24) & 3]);
            n += 1;
