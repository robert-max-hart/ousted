# ----------------------------------------------------------------
# SchoolTasks
#     The school day: the teacher teaching and children studying.
# ----------------------------------------------------------------
class_name SchoolTasks extends TaskBase;

const TEACHER_EARLY :float = 0.5;   # hours before school starts that the teacher heads over

# Whether it is school time for this citizen: a child, or the teacher, with a school standing.
func calls(p:Pawn) -> bool:
    if not (school_hours() or (p.profession == JobManager.Profession.TEACHER and GameClock.hour() >= Defs.SCHOOL_START - TEACHER_EARLY and GameClock.hour() < Defs.SCHOOL_END)):
        return false;
    if not (p.is_child() or p.profession == JobManager.Profession.TEACHER):
        return false;
    for b in world.buildings:
        if b.is_complete() and b.def.has("school_capacity"):
            return true;
    return false;

func school_hours() -> bool:
    var h:float = GameClock.hour();
    return h >= Defs.SCHOOL_START and h < Defs.SCHOOL_END;

# A teacher works the school during school hours as long as there are children to teach.
func teach_task(p:Pawn) -> Task:
    var h:float = GameClock.hour();
    if h < Defs.SCHOOL_START - TEACHER_EARLY or h >= Defs.SCHOOL_END:     # the teacher is in place when the bell rings
        return null;
    var has_children:bool = false;
    for pw in world.pawns:
        if pw.is_child():
            has_children = true;
            break;
    if not has_children:
        return null;
    var sites:Array[Building] = [];
    for b in world.buildings:
        if b.is_complete() and b.def.has("school_capacity") and workers_at(b) < b.def.get("worker_slots", 1):
            sites.append(b);
    sites.sort_custom(func(a:Building, c:Building) -> bool:
        return a.position.distance_squared_to(p.position) < c.position.distance_squared_to(p.position));
    if sites.is_empty():
        return null;
    var school:Building = sites[0];
    var t:Task = Task.new(&"teach", "Teaching");
    t.job = JobManager.Profession.TEACHER;
    t.target = school;
    t.workplace = school;
    t.move_rect(school.rect(), school.is_walkable(), "Walking to school");
    t.act(func(_pw:Pawn) -> bool:
        school.teaching = true;
        return true);
    var teach_tick:Callable = func(teacher:Pawn, _dh:float) -> bool:
        if World.alive(school):
            school.teaching_mult = Defs.teacher_multiplier(teacher.experience(JobManager.Profession.TEACHER), teacher.general_xp);
        if not World.alive(school) or GameClock.hour() >= Defs.SCHOOL_END or GameClock.hour() < Defs.SCHOOL_START - TEACHER_EARLY:
            return true;
        for pw in world.pawns:
            if pw.is_child():
                return false;
        return true;
    t.work(teach_tick, "Teaching");
    t.on_end = func(_pw:Pawn) -> void:
        if World.alive(school):
            school.teaching = false;
    return t;

# A child goes to a school with a free seat while it is school hours and the colony has a teacher. School
# comes before child labor; if the teacher never turns up, the child gives up and works instead.
func school_task(p:Pawn) -> Task:
    if not school_hours() or count(JobManager.Profession.TEACHER) == 0:
        return null;
    var school:Building = world.nearest_building(p.position, func(b:Building) -> bool:
        return b.is_complete() and b.def.has("school_capacity") and b.attendees < b.def["school_capacity"] and not p.has_failed(b));
    if school == null:
        return null;
    school.attendees += 1;
    var t:Task = Task.new(&"school", "Going to school");
    t.target = school;
    t.move_rect(school.rect(), school.is_walkable(), "Going to school");
    var st:Dictionary = {"waited": 0.0};
    var study:Callable = func(pw:Pawn, dh:float) -> bool:
        if not World.alive(school) or not school_hours():
            return true;
        if not school.teaching:
            st["waited"] += dh;
            if st["waited"] > 1.5:
                pw.avoid(school, 3.0);
                return true;
            return false;
        pw.learn(dh, school.teaching_mult);
        return false;
    t.work(study, "Studying");
    t.on_end = func(_pw:Pawn) -> void:
        if World.alive(school):
            school.attendees = maxi(0, school.attendees - 1);
    return t;
