# ----------------------------------------------------------------
# Baby dies during care test
#     A carer on the way with food for a baby that then dies must have
#     its task ended at once, so no callback holds the freed baby.
#     godot --headless --path . --fixed-fps 60 res://tests/baby_death_care.tscn
# ----------------------------------------------------------------
extends Node;

var world:World;
var carer:Pawn;
var baby:Pawn;
var _frames:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(1);
    var house:Building = world.place_building(&"house", world.town_hall.origin + Vector2i(-8, 2), Vector2i(3, 3), true);
    carer = world.pawns[0];
    carer.age = 30.0;
    world.families.move_home(carer, house);
    baby = world.pawns[1];
    baby.age = 1.0;
    world.families.move_home(baby, house);
    baby.hunger = 0.3;
    var t:Task = world.jobs.needs.care_task(carer);
    _expect("a care task is made", t != null);
    carer.task = t;

func _process(_delta:float) -> void:
    _frames += 1;
    if _frames == 3:
        _expect("the carer is on the task", carer.task != null and carer.task.kind == &"care");
        world.kill_pawn(baby, "exposure");
        _expect("the task ended with the baby", carer.task == null or carer.task.kind != &"care");
    elif _frames == 30:
        _expect("the carer carries on (no crash)", World.alive(carer));
        get_tree().quit();

func _expect(what:String, ok:bool) -> void:
    print(("PASS " if ok else "FAIL ") + what);
