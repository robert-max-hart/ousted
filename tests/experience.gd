# ----------------------------------------------------------------
# Experience test
#     Checks the job experience curve, the teacher quality multiplier,
#     picking by experience for the profession targets, a save round
#     trip and that working citizens earn experience.
#     godot --headless --path . --fixed-fps 60 res://tests/experience.tscn
# ----------------------------------------------------------------
extends Node;

var world:World;
var _start_hours:float;
var _checked:bool = false;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    Engine.time_scale = 4.0;
    GameClock.set_speed(3);
    _start_hours = GameClock.total_hours;
    _check_curves();
    _check_picking();

func _check_curves() -> void:
    _expect("job xp gain falls as experience rises", Defs.job_xp_gain(0.2, 1.0) < Defs.job_xp_gain(0.0, 1.0));
    var xp:float = 0.0;
    var hours:int = 0;
    while xp < 0.25:
        xp += Defs.job_xp_gain(xp, 1.0);
        hours += 1;
    _expect("+25%% job experience takes %d work hours" % hours, hours > 200 and hours < 1000);
    _expect("beginner teacher has no bonus", is_equal_approx(Defs.teacher_multiplier(0.0, 0.0), 1.0));
    _expect("veteran teacher is 1.5x", is_equal_approx(Defs.teacher_multiplier(0.3, 0.23), 1.5));
    _expect("schooling alone helps a new teacher", Defs.teacher_multiplier(0.0, 0.2) > 1.2);
    _expect("teacher bonus is capped", is_equal_approx(Defs.teacher_multiplier(2.0, 2.0), 1.5));

func _check_picking() -> void:
    var jobs:JobManager = world.jobs;
    var original:Array[int] = [];
    for p in world.pawns:
        original.append(p.profession);
        p.profession = JobManager.Profession.LABORER;
        p.job_xp.clear();
        p.age = 30.0;
    jobs.sync_targets();
    var f:int = JobManager.Profession.FARMER;
    world.pawns[2].job_xp[f] = 0.1;
    world.pawns[4].job_xp[f] = 0.2;
    jobs.change_profession(f, 1);
    _expect("adding takes the most experienced laborer", world.pawns[4].profession == f and world.pawns[2].profession == JobManager.Profession.LABORER);
    jobs.change_profession(f, 1);
    _expect("then the next most experienced", world.pawns[2].profession == f);
    jobs.change_profession(f, 1);
    _expect("ties fall back to list order", world.pawns[0].profession == f);
    jobs.change_profession(f, -1);
    _expect("removing takes the least experienced", world.pawns[0].profession == JobManager.Profession.LABORER and world.pawns[4].profession == f);
    var d:Dictionary = world.pawns[4].to_dict();
    var copy:Pawn = Pawn.new();
    copy.restore(world, d);
    _expect("job experience survives a save", is_equal_approx(copy.experience(f), 0.2));
    copy.free();
    for i in world.pawns.size():
        world.pawns[i].profession = original[i];
        world.pawns[i].job_xp.clear();
    jobs.sync_targets();

func _process(_delta:float) -> void:
    var days:float = (GameClock.total_hours - _start_hours) / 24.0;
    if days < 3.0 or _checked:
        return;
    _checked = true;
    var earned:int = 0;
    for p in world.pawns:
        if not p.job_xp.is_empty():
            earned += 1;
            print("EXP: %s %s" % [p.first_name, p.job_xp]);
    _expect("citizens at work earned experience (%d of %d)" % [earned, world.pawns.size()], earned > 0);
    get_tree().quit();

func _expect(what:String, ok:bool) -> void:
    print("%s: %s" % ["PASS" if ok else "FAIL", what]);
