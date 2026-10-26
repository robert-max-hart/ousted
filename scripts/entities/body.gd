# ----------------------------------------------------------------
# Body
#     A dead citizen lying where they died until someone carries them to
#     a grave. Kin get the first chance to carry. An unburied body
#     vanishes after Defs.BODY_LINGER_DAYS.
# ----------------------------------------------------------------
class_name Body extends Node3D;

var world       :World;
var id          :int = 0;
var person      :String = "";
var age         :int = 0;
var cause       :String = "";
var died_hour   :float = 0.0;
var kin         :Array[Pawn] = [];        # who was close to them when they died (may be dead since)
var claimed_by  :Pawn = null;             # on the way to carry it, or carrying it
var carried     :bool = false;
var removed     :bool = false;

func setup(w:World, body_id:int, d:Dictionary, at:Vector3) -> void:
    world = w;
    id = body_id;
    person = d["name"];
    age = d["age"];
    cause = d["cause"];
    died_hour = d["died_hour"];
    position = Vector3(at.x, w.terrain.height_at(at.x, at.z), at.z);
    name = "Body_%d" % id;
    var mesh:CapsuleMesh = CapsuleMesh.new();
    mesh.radius = 0.16;
    mesh.height = 0.95;
    var mi:MeshInstance3D = MeshInstance3D.new();
    mi.mesh = mesh;
    var mat:StandardMaterial3D = StandardMaterial3D.new();
    mat.albedo_color = Color(0.72, 0.68, 0.62);
    mi.material_override = mat;
    mi.rotation.z = PI * 0.5;       # lying down
    mi.position.y = 0.18;
    add_child(mi);

func cell() -> Vector2i:
    return world.terrain.world_to_cell(position);

func _process(_delta:float) -> void:
    if carried:
        if World.alive(claimed_by):
            position = claimed_by.position + Vector3(0, 0.9, 0);
            rotation.y = claimed_by.rotation.y;
        else:
            drop();

# Put down where it is (the carrier stopped, or died).
func drop() -> void:
    carried = false;
    claimed_by = null;
    position.y = world.terrain.height_at(position.x, position.z);

func living_kin() -> Array[Pawn]:
    var out:Array[Pawn] = [];
    for k in kin:
        if World.alive(k) and not k.removed and k.is_adult():
            out.append(k);
    return out;

# Kin may carry at once; anyone else only when the family window has passed or no family is left.
func can_be_taken_by(p:Pawn) -> bool:
    if removed or claimed_by != null or not p.is_adult():
        return false;
    var family:Array[Pawn] = living_kin();
    if family.has(p):
        return true;
    return family.is_empty() or GameClock.total_hours >= died_hour + Defs.BODY_FAMILY_FIRST_HOURS;

func expired() -> bool:
    return not carried and claimed_by == null and GameClock.total_hours >= died_hour + Defs.BODY_LINGER_DAYS * GameClock.HOURS_PER_DAY;

func to_dict() -> Dictionary:
    var kin_ids:Array = [];
    for k in kin:
        if World.alive(k):
            kin_ids.append(world.pawns.find(k));
    return {"id": id, "name": person, "age": age, "cause": cause, "died_hour": died_hour, "position": position, "kin": kin_ids};
