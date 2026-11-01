# ----------------------------------------------------------------
# ModelDetail
#     The Model detail setting (Settings.model_detail: Full or Reduced) for everything made of model files: trees, plants and crops follow it
#     in their own renderers, and this swaps the rest of the world at once: buildings, citizens, animals, fences and gates, headstones and the
#     goods in stockpiles. Each set has a `_low` sibling folder under assets/models (made by tools/make_models.py with fewer sides on round
#     parts, and for buildings without the smallest details). Every mesh in the world that came from one of the folders is swapped for its
#     twin of the same name, and the static caches the models are loaded through are dropped so what is made later uses the right set.
#     Parts made by stamping tiles together (a bridge's deck, a stockpile's platform) pick the set when they are next built.
# ----------------------------------------------------------------
class_name ModelDetail extends RefCounted;

const SETS:Array[String] = [
    "res://assets/models/buildings/", "res://assets/models/citizens/", "res://assets/models/animals/",
    "res://assets/models/structures/", "res://assets/models/goods/",
];

static var _applied_low:bool = false;

# Called when settings change: swaps the world's meshes if the detail changed.
static func apply(world:World) -> void:
    var low:bool = Settings.models_reduced();
    if low == _applied_low:
        return;
    _applied_low = low;
    Animals.drop_caches();
    PawnRig.drop_caches();
    PileGoods.drop_caches();
    if world != null and is_instance_valid(world):
        swap_world(world);

# Called when a world is built: it is made with the set the player chose, so there is nothing to swap in it (and the caches are cleared in case
# the setting was changed while no world was running).
static func note_start() -> void:
    _applied_low = Settings.models_reduced();
    Animals.drop_caches();
    PawnRig.drop_caches();
    PileGoods.drop_caches();

# Puts the chosen set in place of the other on every model mesh under `root`. Returns how many meshes were swapped.
static func swap_world(root:Node) -> int:
    var swapped:int = 0;
    for n in root.find_children("*", "", true, false):
        if n is MeshInstance3D:
            var mi:MeshInstance3D = n;
            var m:Mesh = twin(mi.mesh);
            if m != mi.mesh:
                mi.mesh = m;
                swapped += 1;
        elif n is MultiMeshInstance3D:
            var mmi:MultiMeshInstance3D = n;
            if mmi.multimesh != null:
                var m:Mesh = twin(mmi.multimesh.mesh);
                if m != mmi.multimesh.mesh:
                    mmi.multimesh.mesh = m;
                    swapped += 1;
    return swapped;

# The mesh in the set the player chose that stands for `mesh` (the same file name in the other folder), or `mesh` itself if it is not a model file of the sets above.
static func twin(mesh:Mesh) -> Mesh:
    if mesh == null or mesh.resource_path == "":
        return mesh;
    var path:String = mesh.resource_path;
    for base in SETS:
        var low_base:String = base.trim_suffix("/") + "_low/";
        if path.begins_with(base) or path.begins_with(low_base):
            var want:String = Settings.model_dir(base) + path.get_file();
            if want == path:
                return mesh;
            return load(want) as Mesh if ResourceLoader.exists(want) else mesh;
    return mesh;
