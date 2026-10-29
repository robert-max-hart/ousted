# ----------------------------------------------------------------
# GuidedHerd
#     The animals a citizen is leading from the Trading Post to a
#     pasture: small models that trail behind the leader along the
#     path they have just walked. Visual only; TradeTasks owns the
#     count and puts the animals into the pasture (or back at the post).
# ----------------------------------------------------------------
class_name GuidedHerd extends Node3D;

const TRAIL_STEP:float = 0.3;        # metres between remembered leader positions
const LAG:int = 3;                   # trail samples between one animal and the next

var _leader     :Node3D;
var _animals    :Array[Node3D] = [];
var _trail      :Array[Vector3] = [];

static func lead(world:World, kind:StringName, n:int, leader:Node3D) -> GuidedHerd:
    var h:GuidedHerd = GuidedHerd.new();
    world.add_child(h);
    h._leader = leader;
    h.name = "GuidedHerd";
    var mesh:ArrayMesh = Pasture._mesh_for(kind);
    for i in n:
        var mi:MeshInstance3D = MeshInstance3D.new();
        mi.mesh = mesh;
        mi.material_override = CropMeshes.material();
        mi.scale = Vector3.ONE * (0.9 if kind == &"cow" else 1.0);
        h.add_child(mi);
        h._animals.append(mi);
        mi.position = leader.position;
    h._trail.append(leader.position);
    return h;

func _process(_delta:float) -> void:
    if _leader == null or not is_instance_valid(_leader):
        return;
    if _trail.is_empty() or Vector2(_leader.position.x - _trail[-1].x, _leader.position.z - _trail[-1].z).length() >= TRAIL_STEP:
        _trail.append(_leader.position);
        if _trail.size() > 60:
            _trail.pop_front();
    for i in _animals.size():
        var idx:int = maxi(0, _trail.size() - 1 - (i + 1) * LAG);
        var at:Vector3 = _trail[idx];
        var ahead:Vector3 = _trail[mini(_trail.size() - 1, idx + 1)];
        var a:Node3D = _animals[i];
        a.position = a.position.lerp(at, 0.35);
        var dir:Vector2 = Vector2(ahead.x - at.x, ahead.z - at.z);
        if dir.length() > 0.01:
            a.rotation.y = lerp_angle(a.rotation.y, atan2(dir.x, dir.y) - PI * 0.5, 0.2);
