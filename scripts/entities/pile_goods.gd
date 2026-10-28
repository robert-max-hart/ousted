# ----------------------------------------------------------------
# PileGoods
#     Crates stacked on a stockpile, so how full it is can be seen:
#     the more it holds, the more crates and the higher they stack.
#     Each item gets its own share of the squares, coloured like the
#     item. Reads the building's stock twice a second and only
#     rebuilds when what it shows would change.
# ----------------------------------------------------------------
class_name PileGoods extends MultiMeshInstance3D;

const MAX_LEVELS    :int = 3;
const CRATE         :float = 0.62;

var _b          :Building;
var _timer      :float = 0.0;
var _shown      :String = "";

func _init(b:Building) -> void:
    _b = b;
    top_level = true;
    var mm:MultiMesh = MultiMesh.new();
    mm.transform_format = MultiMesh.TRANSFORM_3D;
    mm.use_colors = true;
    var box:BoxMesh = BoxMesh.new();
    box.size = Vector3(CRATE, CRATE * 0.8, CRATE);
    mm.mesh = box;
    multimesh = mm;
    var mat:StandardMaterial3D = SurfaceTextures.material(&"planks", Color.WHITE);
    mat.vertex_color_use_as_albedo = true;
    mat.vertex_color_is_srgb = true;
    mat.uv1_world_triplanar = true;
    material_override = mat;

func _process(delta:float) -> void:
    _timer -= delta;
    if _timer > 0.0:
        return;
    _timer = 0.5;
    var done:bool = _b.state == Building.State.COMPLETE;
    visible = done;
    if done:
        _refresh();

func _refresh() -> void:
    var cap:int = maxi(1, _b.capacity());
    var cells:int = _b.size.x * _b.size.y;
    var items:Array = _b.stored.keys();
    items.sort();
    var counts:Array[int] = [];
    var sig:String = "%d:" % cells;
    var total:int = 0;
    for item in items:
        var n:int = roundi(float(_b.stored[item]) / cap * cells * MAX_LEVELS);
        n = maxi(n, 1 if _b.stored[item] > 0 else 0);
        counts.append(n);
        total += n;
        sig += "%s=%d," % [item, n];
    if sig == _shown:
        return;
    _shown = sig;
    total = mini(total, cells * MAX_LEVELS);
    var mm:MultiMesh = multimesh;
    mm.instance_count = total;
    if total == 0:
        return;
    # give each item a block of squares in proportion, then stack its crates over them
    var k:int = 0;
    var cell_at:int = 0;
    var t:Terrain = _b.world.terrain;
    for j in items.size():
        var n:int = counts[j];
        var group:int = clampi(ceili(float(n) / MAX_LEVELS), 1, maxi(1, cells - cell_at));
        var col:Color = Defs.ITEMS[items[j]].get("color", Color.GRAY);
        for m in n:
            if k >= total:
                return;
            var cell_i:int = cell_at + (m % group);
            var level:int = m / group;
            var c:Vector2i = _b.origin + Vector2i(cell_i % _b.size.x, cell_i / _b.size.x);
            var jitter:float = float(hash(Vector3i(c.x, c.y, level)) & 0xff) / 255.0;
            var pos:Vector3 = Vector3(c.x + 0.5 + (jitter - 0.5) * 0.14, t.height_at(c.x + 0.5, c.y + 0.5) + 0.05 + CRATE * 0.4 * (level * 2 + 1) * 0.8, c.y + 0.5 + (jitter - 0.5) * 0.1);
            mm.set_instance_transform(k, Transform3D(Basis(Vector3.UP, (jitter - 0.5) * 0.5), pos));
            mm.set_instance_color(k, col.lerp(Color.WHITE, 0.1 + jitter * 0.12));
            k += 1;
        cell_at += group;
