# ----------------------------------------------------------------
# HerdTasks
#     Collecting what farm animals give: eggs, milk and manure.
#     (Feeding is the generic input fetching, see ProductionTasks.)
# ----------------------------------------------------------------
class_name HerdTasks extends TaskBase;

const COLLECT_HOURS:float = 0.5;

# The nearest pasture with enough ready to be worth a trip (and somewhere to put it), as a task for a farmer.
func collect_task(p:Pawn) -> Task:
    var best:Building = null;
    var best_d:float = INF;
    var pc:Vector2 = Vector2(p.position.x, p.position.z);
    for b in world.buildings:
        if not (b is Pasture or b is Apiary) or not b.is_complete() or b.claimed or p.has_failed(b):
            continue;
        var ready:Dictionary = b.collectable();
        if ready.is_empty() or not Stock.has_room_for(ready["item"]):
            continue;
        var d:float = pc.distance_squared_to(b.center_cell());
        if d < best_d:
            best_d = d;
            best = b;
    if best == null:
        return null;
    var pasture:Building = best;
    var ready:Dictionary = pasture.collectable();
    var item:StringName = ready["item"];
    pasture.claimed = true;
    var what:String = Defs.item_name(item).to_lower();
    var t:Task = Task.new(&"herd", "Collecting %s" % what);
    t.job = JobManager.Profession.FARMER;
    t.target = pasture;
    t.move_rect(pasture.rect(), pasture.is_walkable(), "Walking to the %s" % pasture.display_name().to_lower());
    t.work_for(COLLECT_HOURS, "Collecting %s" % what, func(pw:Pawn) -> void:
        if World.alive(pasture):
            var n:int = pasture.take_ready(item, Pawn.CARRY_CAP - (pw.carry_amount if pw.carry_item == item else 0));
            if n > 0:
                pw.add_carry(item, n));
    t.on_end = func(_pw:Pawn) -> void:
        if World.alive(pasture):
            pasture.claimed = false;
    return t;
