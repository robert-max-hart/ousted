# ----------------------------------------------------------------
# HealthTasks
#     The healer's work: a Herbalist's Hut sends its healer to the sickest
#     citizen who is resting and has not been tended lately. They take a
#     herb from the hut if it has one (a visit with herbs heals much
#     better) and tend the patient where they rest for an hour and a half.
#     Held by JobManager (as `health`); holds no reference back to it.
# ----------------------------------------------------------------
class_name HealthTasks extends TaskBase;

const TEND_HOURS:float = 1.5;

var _claimed:Dictionary = {};       # patient -> the healer on the way

func heal_task(p:Pawn) -> Task:
    var huts:Array[Building] = [];
    for b in world.buildings:
        if b.is_complete() and b.def.get("healing", false) and workers_at(b) < b.def.get("worker_slots", 1):
            huts.append(b);
    huts.sort_custom(func(a:Building, c:Building) -> bool:
        return a.position.distance_squared_to(p.position) < c.position.distance_squared_to(p.position));
    for hut in huts:
        var patient:Pawn = _patient_for(p);
        if patient == null:
            return null;
        return _tend(p, hut, patient);
    return null;

func _patient_for(healer:Pawn) -> Pawn:
    var best:Pawn = null;
    var best_key:float = -INF;
    for q in world.pawns:
        if q == healer or q.removed or q.illness < 0.15 or Illness.is_cared_for(q) or healer.has_failed(q):
            continue;
        if _claimed.has(q) and is_instance_valid(_claimed[q]) and _claimed[q] != healer:
            continue;
        if not Illness.must_rest(q) and q.illness < Illness.REST_ABOVE:
            continue;
        var key:float = q.illness * 100.0 - q.position.distance_to(healer.position) * 0.1;
        if key > best_key:
            best_key = key;
            best = q;
    return best;

func _tend(p:Pawn, hut:Building, patient:Pawn) -> Task:
    var st:Dictionary = {"herbs": false};
    var t:Task = Task.new(&"heal", "Tending %s" % patient.first_name, false);
    t.job = JobManager.Profession.HEALER;
    t.workplace = hut;
    t.target = patient;
    _claimed[patient] = p;
    if hut.input_amount(&"herbs") > 0:
        t.move_rect(hut.rect(), hut.is_walkable(), "Fetching herbs");
        t.act(func(_pw:Pawn) -> bool:
            if World.alive(hut) and hut.input_amount(&"herbs") > 0:
                hut.take_input(&"herbs", 1);
                st["herbs"] = true;
            return true);
    if World.alive(patient.home) and patient.home.is_complete():
        t.move_rect(patient.home.rect(), false, "Going to %s" % patient.first_name);
    else:
        t.move_cell(patient.cell(), "Going to %s" % patient.first_name);
    t.work_for(TEND_HOURS, "Tending %s" % patient.first_name, func(_pw:Pawn) -> void:
        _claimed.erase(patient);
        if patient.removed or patient.illness <= 0.0:
            return;
        patient.care_until = GameClock.total_hours + Illness.CARE_HOURS;
        patient.care_quality = 1.0 if st["herbs"] else 0.0);
    t.on_cancel = func(_pw:Pawn) -> void:
        _claimed.erase(patient);
        if st["herbs"] and World.alive(hut):
            hut.add_input(&"herbs", 1);       # the herb was not used
    return t;
