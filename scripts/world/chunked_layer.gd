# ----------------------------------------------------------------
# ChunkedLayer
#     One kind of thing drawn many times (a tree model, a rock), split
#     into a multimesh per 48 by 48 block of the map. A single multimesh
#     for the whole map is one object to the renderer: it cannot cull
#     the trees nobody is looking at. In blocks, the ones outside the
#     view are skipped, and those beyond the draw distance setting are
#     hidden (visibility range). Blocks are made when first needed.
# ----------------------------------------------------------------
class_name ChunkedLayer extends RefCounted;

const BLOCK:float = 48.0;             # cells to a side
const REACH:float = 40.0;             # a block's half-diagonal and a margin: added to the draw distance, which counts to the block's middle

var mesh        :Mesh;
var _parent     :Node3D;
var _chunks     :Dictionary = {};     # Vector2i -> MultiMeshInstance3D
var _used       :Dictionary = {};     # blocks filled since begin()
var _distance   :float = 0.0;
var _shown      :bool = true;

func _init(parent:Node3D, m:Mesh) -> void:
    _parent = parent;
    mesh = m;

static func block_of(cell:Vector2i) -> Vector2i:
    return Vector2i(floori(cell.x / BLOCK), floori(cell.y / BLOCK));

# Starts a refill: every block is unused until it is filled.
func begin() -> void:
    _used.clear();

# The multimesh of a block, sized to `count` instances.
func fill(block:Vector2i, count:int) -> MultiMesh:
    _used[block] = true;
    var mmi:MultiMeshInstance3D = _chunks.get(block);
    if mmi == null:
        var mm:MultiMesh = MultiMesh.new();
        mm.transform_format = MultiMesh.TRANSFORM_3D;
        mm.use_colors = true;
        mm.mesh = mesh;
        mmi = MultiMeshInstance3D.new();
        mmi.multimesh = mm;
        mmi.visible = _shown;
        _parent.add_child(mmi);
        _chunks[block] = mmi;
        _apply_distance(mmi);
    mmi.multimesh.instance_count = count;
    return mmi.multimesh;

# Ends a refill: the blocks nothing was put in are emptied.
func finish() -> void:
    for block in _chunks:
        if not _used.has(block):
            (_chunks[block] as MultiMeshInstance3D).multimesh.instance_count = 0;

func total() -> int:
    var n:int = 0;
    for block in _chunks:
        n += (_chunks[block] as MultiMeshInstance3D).multimesh.instance_count;
    return n;

func chunk_count() -> int:
    var n:int = 0;
    for block in _chunks:
        if (_chunks[block] as MultiMeshInstance3D).multimesh.instance_count > 0:
            n += 1;
    return n;

func set_shown(on:bool) -> void:
    _shown = on;
    for block in _chunks:
        (_chunks[block] as MultiMeshInstance3D).visible = on;

func is_shown() -> bool:
    return _shown;

# Hides the blocks farther than `metres` from the camera (0: never).
func set_distance(metres:float) -> void:
    _distance = metres;
    for block in _chunks:
        _apply_distance(_chunks[block]);

func _apply_distance(mmi:MultiMeshInstance3D) -> void:
    mmi.visibility_range_end = _distance + REACH if _distance > 0.0 else 0.0;
    mmi.visibility_range_end_margin = 4.0 if _distance > 0.0 else 0.0;

# Removes the blocks (when the models are swapped for another set).
func free_all() -> void:
    for block in _chunks:
        (_chunks[block] as MultiMeshInstance3D).queue_free();
    _chunks.clear();
    _used.clear();
