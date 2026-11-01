# ----------------------------------------------------------------
# Animals
#     The farm animals' models (assets/models/animals, made by
#     tools/make_animals.py): per kind a body, a head and the legs,
#     and how each moves. Legs and heads are moved by
#     shaders/animal.gdshader (the herds are multimeshes, so each
#     animal brings its own timing as instance custom data); `whole`
#     is the same animal in one static piece, for the ones being led
#     to a pasture. RIG has the pivots and the gaits.
# ----------------------------------------------------------------
class_name Animals extends RefCounted;

const DIR:String = "res://assets/models/animals/";
const PARTS:Array[StringName] = [&"body", &"head", &"legs"];

# hip_y and leg_x: where the legs pivot; quad: four legs (diagonal pairs) or two; leg_amp (radians) and leg_speed: the gait;
# head_pivot, nod_amp and nod_speed: how the head dips (a chicken pecks fast and short, a cow grazes slow and deep).
const RIG:Dictionary = {
    &"chicken": {"hip_y": 0.12, "leg_x": 0.0, "quad": 0.0, "leg_amp": 0.8, "leg_speed": 11.0, "head_pivot": Vector3(0.12, 0.3, 0.0), "nod_amp": 0.95, "nod_speed": 5.5},
    &"sheep":   {"hip_y": 0.3, "leg_x": 0.16, "quad": 1.0, "leg_amp": 0.4, "leg_speed": 5.0, "head_pivot": Vector3(0.26, 0.5, 0.0), "nod_amp": 0.75, "nod_speed": 1.4},
    &"cow":     {"hip_y": 0.52, "leg_x": 0.32, "quad": 1.0, "leg_amp": 0.32, "leg_speed": 3.6, "head_pivot": Vector3(0.4, 0.86, 0.0), "nod_amp": 0.85, "nod_speed": 1.0},
};

static var _meshes:Dictionary = {};
static var _mats:Dictionary = {};
static var _whole:Dictionary = {};

static func part(kind:StringName, which:StringName) -> Mesh:
    var key:String = "%s_%s" % [kind, which];
    if not _meshes.has(key):
        _meshes[key] = load("%sanimal_%s.obj" % [Settings.model_dir(DIR), key]) as Mesh;
    return _meshes[key];

# Forgets the loaded meshes (the model detail changed).
static func drop_caches() -> void:
    _meshes.clear();
    _whole.clear();

# The material for a part: the body is plain vertex colours; legs and head use the animal shader with this kind's gait.
static func material(kind:StringName, which:StringName) -> Material:
    if which == &"body":
        return CropMeshes.material();
    var key:String = "%s_%s" % [kind, which];
    if not _mats.has(key):
        var rig:Dictionary = RIG[kind];
        var m:ShaderMaterial = ShaderMaterial.new();
        m.shader = load("res://shaders/animal.gdshader") as Shader;
        m.set_shader_parameter("mode", 0 if which == &"legs" else 1);
        m.set_shader_parameter("hip_y", rig["hip_y"]);
        m.set_shader_parameter("leg_x", rig["leg_x"]);
        m.set_shader_parameter("quadruped", rig["quad"]);
        m.set_shader_parameter("leg_amp", rig["leg_amp"]);
        m.set_shader_parameter("leg_speed", rig["leg_speed"]);
        m.set_shader_parameter("head_pivot", rig["head_pivot"]);
        m.set_shader_parameter("nod_amp", rig["nod_amp"]);
        m.set_shader_parameter("nod_speed", rig["nod_speed"]);
        WindSway.track(m);                    # it gets the shared clock with the swaying trees
        _mats[key] = m;
    return _mats[key];

# The whole animal as one static mesh (body, head and legs), for the ones led along the road.
static func whole(kind:StringName) -> ArrayMesh:
    if not _whole.has(kind):
        var mesh:ArrayMesh = ArrayMesh.new();
        for which in PARTS:
            mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, part(kind, which).surface_get_arrays(0));
            mesh.surface_set_material(mesh.get_surface_count() - 1, CropMeshes.material());
        _whole[kind] = mesh;
    return _whole[kind];

# A multimesh layer for one part of a kind of animal (colours kept on, as the Compatibility renderer needs; custom data for the timing).
static func make_layer(kind:StringName, which:StringName) -> MultiMeshInstance3D:
    var mm:MultiMesh = MultiMesh.new();
    mm.transform_format = MultiMesh.TRANSFORM_3D;
    mm.use_colors = true;
    mm.use_custom_data = true;
    mm.mesh = part(kind, which);
    var mmi:MultiMeshInstance3D = MultiMeshInstance3D.new();
    mmi.multimesh = mm;
    mmi.material_override = material(kind, which);
    return mmi;

# The coat colour of the i'th animal of a herd (the body and head take it; the legs keep their own colours).
static func coat(kind:StringName, i:int) -> Color:
    if kind == &"chicken":
        return [Color(1, 1, 1), Color(0.85, 0.65, 0.45), Color(0.95, 0.9, 0.8)][i % 3];
    if kind == &"sheep":
        return [Color(0.96, 0.94, 0.88), Color(0.9, 0.88, 0.82), Color(0.62, 0.57, 0.52)][i % 3];
    return [Color(0.8, 0.6, 0.4), Color(0.95, 0.95, 0.92), Color(0.55, 0.4, 0.3), Color(0.4, 0.34, 0.3)][i % 4];
