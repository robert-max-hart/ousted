# ----------------------------------------------------------------
# School test
#     A school with a teacher and more children than seats. Checks that
#     children study only during school hours and only while a teacher is
#     there, never exceed the capacity, gain diminishing experience and that
#     adults gain none. Prints PASS or FAIL lines.
#     godot --headless --path . --fixed-fps 60 res://tests/school.tscn
# ----------------------------------------------------------------
extends Node;

const KIDS:int = 14;

var world:World;
var school:Building;
var teacher:Pawn;
var kids:Array[Pawn] = [];
var _start:float;
var _max_attendees:int = 0;
var _teacher_taught:bool = false;
var _done:bool = false;
var _teaching_hours:float = 0.0;
var _study_frames:int = 0;
var _bad_frames:int = 0;                # frames in which a child learned outside school hours or with no teacher
var _last_xp:Dictionary = {};
var _teaching_prev:bool = false;
var _open_prev:bool = false;

func _school_open() -> bool:
    var h:float = GameClock.hour();
    return h >= Defs.SCHOOL_START and h < Defs.SCHOOL_END;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    Engine.time_scale = 4.0;
    Defs.ageing_days_per_year = 40.0;     # slow ageing, so nobody leaves the child stage during the test
    var th:Building = world.town_hall;
    for dz in range(-12, 12, 3):
        var o:Vector2i = th.origin + Vector2i(6, dz);
        if world.can_place(&"school", o, Vector2i(4, 4)) == "":
            school = world.place_building(&"school", o, Vector2i(4, 4), true);
            break;
    for p in world.pawns:
        p.profession = JobManager.Profession.LABORER;
    for i in KIDS:
        var c:Vector2i = world.nav.nearest_walkable(th.origin + Vector2i(i % 5, 6 + i / 5), 6);
        var k:Pawn = Pawn.new();
        k.setup(world, c, world.rng);
        k.age = 6.0 + i * 0.5;
        world._entities.add_child(k);
        world.pawns.append(k);
        kids.append(k);
    world.jobs.sync_targets();
    world.jobs.change_profession(JobManager.Profession.TEACHER, 1);
    for p in world.pawns:
        if p.profession == JobManager.Profession.TEACHER:
            teacher = p;
    GameClock.set_speed(3);
    _start = GameClock.total_hours;
    _expect("a school was placed", school != null);
    _expect("an adult became the teacher", teacher != null and teacher.is_adult());
    _expect("no child became the teacher", kids.all(func(k:Pawn) -> bool: return k.profession == JobManager.Profession.LABORER));
    _expect("xp gain falls as experience rises", Defs.general_xp_gain(0.2, 1.0) < Defs.general_xp_gain(0.0, 1.0));
    var xp:float = 0.0;
    for h in 416:
        xp += Defs.general_xp_gain(xp, 1.0);
    _expect("13 years of full schooling gives about +23%% (got %.1f%%)" % (xp * 100.0), absf(xp - 0.23) < 0.03);

@warning_ignore("integer_division")
func _process(_delta:float) -> void:
    if _done:
        return;
    _max_attendees = maxi(_max_attendees, school.attendees);
    if school.teaching:
        _teacher_taught = true;
    var dh:float = GameClock.game_hours(_delta);
    if school.teaching:
        _teaching_hours += dh;
    for k in kids:
        var gained:bool = k.general_xp > _last_xp.get(k, 0.0) + 1e-9;
        _last_xp[k] = k.general_xp;
        if gained:
            _study_frames += 1;
            # judged against the previous frame too: a bell or a teacher's break can land mid-frame
            if not (_school_open() or _open_prev) or not (school.teaching or _teaching_prev):
                _bad_frames += 1;
    _teaching_prev = school.teaching;
    _open_prev = _school_open();
    if (GameClock.total_hours - _start) / 24.0 < 4.0:
        return;
    _done = true;
    var learned:int = 0;
    var most:float = 0.0;
    for k in kids:
        if k.general_xp > 0.0:
            learned += 1;
        most = maxf(most, k.general_xp);
    _expect("the teacher taught", _teacher_taught);
    _expect("never more pupils than seats (max %d)" % _max_attendees, _max_attendees <= 12);
    _expect("the full 12 seats were used (max %d)" % _max_attendees, _max_attendees == 12);
    _expect("children learned (%d of %d have experience, best +%.1f%%)" % [learned, KIDS, most * 100.0], learned >= 10 and most > 0.0);
    print("INFO: teacher taught %.1f of %.1f school hours; %d study frames, %d outside hours or without a teacher" % [_teaching_hours, 4.0 * (Defs.SCHOOL_END - Defs.SCHOOL_START), _study_frames, _bad_frames]);
    _expect("nobody studied outside school hours or without a teacher (%d of %d frames)" % [_bad_frames, _study_frames], _bad_frames == 0);
    var adults_with_xp:int = 0;
    for p in world.pawns:
        if p.is_adult() and p.general_xp > 0.0:
            adults_with_xp += 1;
    _expect("adults gained no schooling", adults_with_xp == 0);
    _expect("a child's work speed includes schooling", is_equal_approx(kids[0].work_efficiency(), Defs.CHILD_EFFICIENCY * (1.0 + kids[0].general_xp)));
    get_tree().quit();

func _expect(what:String, ok:bool) -> void:
    print("%s: %s" % ["PASS" if ok else "FAIL", what]);
