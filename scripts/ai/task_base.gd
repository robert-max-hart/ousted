# ----------------------------------------------------------------
# TaskBase
#     What the task makers share: the world, counting and finding
#     workers, and gathering a resource node. JobManager and its
#     helpers (needs, school, production tasks) all extend this.
# ----------------------------------------------------------------
class_name TaskBase extends RefCounted;

var world:World;

func _init(w:World) -> void:
    world = w;

func count(prof:int) -> int:
    var n:int = 0;
    for p in world.pawns:
        if p.profession == prof:
            n += 1;
    return n;

# The job a gathered resource counts as: trees are woodcutting, rock and ore mining, anything else gathering.
func _node_job(rn:ResourceNode) -> int:
    if rn.kind == &"tree":
        return JobManager.Profession.WOODCUTTER;
    if rn.item == &"iron" or rn.item == &"stone":
        return JobManager.Profession.MINER;
    return JobManager.Profession.GATHERER;

func workers_at(b:Building) -> int:
    var n:int = 0;
    for pw in world.pawns:
        if pw.task != null and is_same(pw.task.workplace, b):
            n += 1;
    return n;

func in_radius(b:Building, c:Vector2i) -> bool:
    return b.center_cell().distance_to(Vector2(c) + Vector2(0.5, 0.5)) <= b.radius();

func harvest_node_task(p:Pawn, pred:Callable, max_dist:float = INF) -> Task:
    var best:ResourceNode = null;
    var best_d:float = max_dist * max_dist;
    var pc:Vector2 = Vector2(p.position.x, p.position.z);
    var room:Dictionary = {};     # item -> whether any storage has space (checked once per item)
    for rn in world.nodes:
        if rn.reserved_by != null or rn.amount <= 0 or not pred.call(rn) or p.has_failed(rn):
            continue;
        if not room.has(rn.item):
            room[rn.item] = Stock.has_room_for(rn.item);
        if not room[rn.item]:
            continue;
        var d:float = pc.distance_squared_to(Vector2(rn.cell) + Vector2(0.5, 0.5));
        if d < best_d:
            best = rn;
            best_d = d;
    if best == null:
        return null;
    var rn:ResourceNode = best;
    rn.reserved_by = p;
    var st:Dictionary = {"acc": 0.0};
    var verb:String = rn.def.get("verb", "Gathering");
    var t:Task = Task.new(&"harvest", "%s (%s)" % [verb, rn.display_name()]);
    t.job = _node_job(rn);
    t.target = rn;
    t.move_cell(rn.cell, "Walking to %s" % rn.display_name().to_lower());
    t.work(func(pw:Pawn, dh:float) -> bool:
        if rn.removed or rn.amount <= 0:
            return true;
        st["acc"] += dh;
        while st["acc"] >= rn.work_per_unit and rn.amount > 0 and pw.carry_amount < Pawn.CARRY_CAP:
            st["acc"] -= rn.work_per_unit;
            rn.amount -= 1;
            pw.add_carry(rn.item, 1);
            world.node_changed(rn);
        return rn.amount <= 0 or pw.carry_amount >= Pawn.CARRY_CAP);
    t.on_end = func(_pw:Pawn) -> void:
        rn.reserved_by = null;
        if rn.amount <= 0 and not rn.regrows and not rn.removed:
            world.remove_node(rn);
    return t;
