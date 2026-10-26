# ----------------------------------------------------------------
# BurialTasks
#     Carrying the dead to a grave. Kin go first (any profession); after
#     a few hours, or when no family is left, laborers do it.
# ----------------------------------------------------------------
class_name BurialTasks extends TaskBase;

# The nearest body this citizen may take, to a graveyard with a free square.
func bury_task(p:Pawn) -> Task:
    if not p.is_adult() or world.bodies.is_empty():
        return null;
    var yard:Graveyard = _free_graveyard(p);
    if yard == null:
        return null;
    var body:Body = null;
    var best_d:float = INF;
    for b in world.bodies:
        if not b.can_be_taken_by(p) or p.has_failed(b):
            continue;
        if not b.living_kin().has(p) and p.profession != JobManager.Profession.LABORER:
            continue;
        var d:float = (b.position - p.position).length_squared();
        if d < best_d:
            best_d = d;
            body = b;
    if body == null:
        return null;
    var slot:int = yard.reserve_slot(p, body.cell());
    if slot < 0:
        return null;
    body.claimed_by = p;
    var t:Task = Task.new(&"bury", "Burying %s" % body.person, false);
    t.target = body;
    t.workplace = yard;
    t.move_cell(body.cell(), "Going to %s" % body.person);
    t.act(func(_pw:Pawn) -> bool:
        if body.removed:
            return false;
        body.carried = true;
        return true);
    t.move_cell(yard.plot_cell(slot), "Carrying %s to the graveyard" % body.person);
    var st:Dictionary = {"buried": false};
    t.work_for(0.6, "Burying %s" % body.person, func(_pw:Pawn) -> void:
        yard.bury(slot, body);
        world.families.soften_grief(body.id);
        st["buried"] = true);
    # the body is only freed here, once the task is over, so no callback outlives it
    t.on_end = func(_pw:Pawn) -> void:
        if World.alive(yard):
            yard.release_slot(slot, p);
        if st["buried"]:
            world.remove_body(body);
        elif body.claimed_by == p:
            body.drop();
    return t;

func _free_graveyard(p:Pawn) -> Graveyard:
    var best:Graveyard = null;
    var best_d:float = INF;
    for b in world.buildings:
        if b is Graveyard and b.is_complete() and b.free_slots() > 0:
            var d:float = (b.position - p.position).length_squared();
            if d < best_d:
                best_d = d;
                best = b;
    return best;
