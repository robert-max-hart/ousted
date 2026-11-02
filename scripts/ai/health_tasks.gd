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
const PICK_HOURS:float = 0.5;       # picking the greenhouse beds
const HERB_KINDS:Array[StringName] = [&"harvest", &"herb_collect"];       # task kinds of the healer's off-time work (a patient ends them)

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

# --------------------------------
# Herbs: the healer's work between visits. A patient always comes first (Pawn._should_interrupt asks `patient_waiting`).

# Whether a healer on a herb trip should drop it for a patient: someone to tend, and a hut with a place for them.
func patient_waiting(healer:Pawn) -> bool:
    return _hut_for(healer) != null and _patient_for(healer) != null;

func _hut_for(p:Pawn) -> Herbalist:
    var best:Herbalist = null;
    var best_d:float = INF;
    for b in world.buildings:
        if b is Herbalist and b.is_complete() and not p.has_failed(b):
            var d:float = b.position.distance_squared_to(p.position);
            if d < best_d:
                best_d = d;
                best = b;
    return best;

# Herbs are wanted while the hut has room or the colony's stock is under the hut's cap (0 = no cap) and storage has room.
func _wants_herbs(hut:Herbalist) -> bool:
    if hut.herb_room() > 0:
        return true;
    var cap:int = hut.production_cap(&"herbs");
    return (cap <= 0 or Stock.amount(&"herbs") < cap) and Stock.has_room_for(&"herbs");

# The greenhouse beds first, then wild herbs in the hut's radius.
func herb_task(p:Pawn) -> Task:
    var hut:Herbalist = _hut_for(p);
    if hut == null or workers_at(hut) >= hut.def.get("worker_slots", 1) or not _wants_herbs(hut):
        return null;
    var t:Task = null;
    if not hut.claimed and not hut.collectable().is_empty():
        t = _greenhouse_task(p, hut);
    if t == null and hut.settings.get("wild_herbs", true):
        t = harvest_node_task(p, func(rn:ResourceNode) -> bool:
            return rn.kind == &"herb" and rn.is_forageable() and rn.is_mature() and in_radius(hut, rn.cell));
    if t != null:
        t.job = JobManager.Profession.HEALER;
        t.workplace = hut;
    return t;

func _greenhouse_task(_p:Pawn, hut:Herbalist) -> Task:
    hut.claimed = true;
    var t:Task = Task.new(&"herb_collect", "Picking greenhouse herbs");
    t.target = hut;
    t.move_rect(hut.rect(), hut.is_walkable(), "Walking to the greenhouse");
    t.work_for(PICK_HOURS, "Picking greenhouse herbs", func(pw:Pawn) -> void:
        if World.alive(hut):
            var n:int = hut.take_ready(Pawn.CARRY_CAP - (pw.carry_amount if pw.carry_item == &"herbs" else 0));
            if n > 0:
                pw.add_carry(&"herbs", n));
    t.on_end = func(_pw:Pawn) -> void:
        if World.alive(hut):
            hut.claimed = false;
    return t;

# A healer carrying herbs puts what fits into the hut's own store; the rest goes to storage as usual.
func deliver_task(p:Pawn) -> Task:
    if p.carry_item != &"herbs":
        return null;
    var hut:Herbalist = _hut_for(p);
    if hut == null or hut.herb_room() <= 0:
        return null;
    var t:Task = Task.new(&"deliver", "Stocking the herbalist's hut");
    t.target = hut;
    t.move_rect(hut.rect(), hut.is_walkable());
    t.act(func(pw:Pawn) -> bool:
        if not World.alive(hut):
            return false;
        var put:int = mini(hut.herb_room(), pw.carry_amount);
        hut.add_input(&"herbs", put);
        if put >= pw.carry_amount:
            pw.clear_carry();
        else:
            pw.set_carry(&"herbs", pw.carry_amount - put);
        return true);
    return t;
