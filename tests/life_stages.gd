# ----------------------------------------------------------------
# Life stages test
#     Checks the ageing curves, a baby staying home, a child working
#     as a laborer at reduced speed, citizens ageing at the set rate
#     and an old citizen dying of old age. Prints PASS or FAIL lines.
#     godot --headless --path . --fixed-fps 60 res://tests/life_stages.tscn
# ----------------------------------------------------------------
extends Node;

var world:World;
var _baby:Pawn;
var _child:Pawn;
var _elder:Pawn;
var _adult:Pawn;
var _adult_start_age:float;
var _start_hours:float;
var _checked:bool = false;
var _early_checked:bool = false;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    Engine.time_scale = 4.0;
    GameClock.set_speed(3);
    _check_curves();
    _adult = world.pawns[0];
    _baby = world.pawns[1];
    _child = world.pawns[2];
    _elder = world.pawns[3];
    _adult.age = 30.0;
    _adult_start_age = 30.0;
    _baby.age = 2.0;
    _child.age = 10.0;
    _child.profession = JobManager.Profession.LABORER;     # (children are born laborers; the test's starter was a farmer)
    world.jobs.change_profession(JobManager.Profession.FARMER, 5);     # far more than there are adults: a child must not be drafted
    _elder.age = 98.0;
    Defs.ageing_days_per_year = 2.0;                       # faster, so the elder dies within the test
    _start_hours = GameClock.total_hours;

func _check_curves() -> void:
    _expect("efficiency at 40 is 1", is_equal_approx(Defs.age_efficiency(40.0), 1.0));
    _expect("efficiency at 60 is 1", is_equal_approx(Defs.age_efficiency(60.0), 1.0));
    _expect("efficiency at 75 is 0.95", is_equal_approx(Defs.age_efficiency(75.0), 0.95));
    _expect("efficiency at 90 is 0.4", is_equal_approx(Defs.age_efficiency(90.0), 0.4));
    _expect("efficiency at 67.5 is 0.975", is_equal_approx(Defs.age_efficiency(67.5), 0.975));
    _expect("efficiency stays 0.4 past 90", is_equal_approx(Defs.age_efficiency(110.0), 0.4));
    Defs.ageing_days_per_year = 4.0;
    _expect("no death before 60", Defs.old_age_death_per_hour(59.0) == 0.0);
    var per_year:float = 1.0 - pow(1.0 - Defs.old_age_death_per_hour(75.0), 4.0 * 24.0);
    _expect("10%% a year at 75 (got %.3f)" % per_year, absf(per_year - 0.10) < 0.001);
    _expect("death rises with age", Defs.old_age_death_per_hour(70.0) < Defs.old_age_death_per_hour(90.0));
    var w:Pawn = Pawn.new();
    w.age = 4.9;
    _expect("4.9 is a baby", w.is_baby());
    w.age = 5.0;
    _expect("5 is a child", not w.is_baby() and not w.is_adult());
    w.age = 17.9;
    _expect("17.9 is a child", not w.is_adult());
    w.age = 18.0;
    _expect("18 is an adult", w.is_adult());
    w.free();

func _process(_delta:float) -> void:
    var days:float = (GameClock.total_hours - _start_hours) / 24.0;
    if days >= 2.0 and not _early_checked:
        # the baby is only a baby until 5 (3 days from age 2 at 2 days a year), so check it first
        _early_checked = true;
        _expect("baby is indoors", World.alive(_baby) and _baby.is_baby() and _baby.indoors);
        _expect("baby needs held steady (hunger %.2f)" % _baby.hunger, _baby.hunger > 0.99 and _baby.thirst > 0.99);
        _expect("baby is not working", _baby.task == null or _baby.task.kind == &"stay_home");
        _expect("child was not drafted into a profession", _child.profession == JobManager.Profession.LABORER);
    if days < 8.0 or _checked:
        return;
    _checked = true;
    var years:float = days / Defs.ageing_days_per_year;
    _expect("adult aged %.2f years in %.1f days at 2 days a year (expected %.2f)" % [_adult.age - _adult_start_age, days, years], absf(_adult.age - _adult_start_age - years) < 0.2);
    _expect("child works at half speed", is_equal_approx(_child.work_efficiency(), 0.5));
    _expect("elder died of old age", not World.alive(_elder) and world.death_log.size() > 0 and world.death_log[0]["cause"] == "old age");
    _expect("adult is still alive", World.alive(_adult));
    print("LIFE: elder's death record: ", world.death_log);
    get_tree().quit();

func _expect(what:String, ok:bool) -> void:
    print("%s: %s" % ["PASS" if ok else "FAIL", what]);
