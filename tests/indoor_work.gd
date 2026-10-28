# ----------------------------------------------------------------
# Working indoors
#     A blacksmith at the forge and a teacher at the school are out of
#     sight inside while they work, and back outside afterwards.
#     godot --headless --path . --fixed-fps 60 res://tests/indoor_work.tscn
# ----------------------------------------------------------------
extends Node;

var world:World;
var _fails:int = 0;
var _smith:Pawn;
var _was_inside:bool = false;
var _start:float = 0.0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(3);
    Engine.time_scale = 4.0;
    GameClock.total_hours = 8.0;
    var o:Vector2i = world.town_hall.origin + Vector2i(8, -10);
    for rn in world.nodes.duplicate():
        if Rect2i(o - Vector2i(3, 3), Vector2i(16, 12)).has_point(rn.cell):
            world.remove_node(rn);
    world.terrain.flatten_rect(Rect2i(o - Vector2i(2, 2), Vector2i(18, 14)));
    world.place_building(&"blacksmith", o, Vector2i(3, 3), true);
    world.town_hall.store(&"wood", 20);
    world.town_hall.store(&"iron", 10);
    _smith = world.pawns[0];
    _smith.profession = JobManager.Profession.BLACKSMITH;
    world.jobs.change_profession(JobManager.Profession.BLACKSMITH, 1);
    _start = GameClock.total_hours;

func _process(_delta:float) -> void:
    for p in world.pawns:
        p.hunger = 1.0; p.thirst = 1.0; p.energy = 1.0; p.warmth = 1.0;
    if _smith._inside_work != null:
        _was_inside = true;
        _expect("a smith working inside is hidden", not _smith.visible);
    elif _was_inside and _smith.task != null and _smith.task.kind != &"forge":
        _expect("and visible again afterwards (task: %s)" % _smith.task.kind, _smith.visible);
        _finish();
    if GameClock.total_hours - _start > 20.0:
        _expect("the smith went inside at some point", _was_inside);
        _finish();

func _finish() -> void:
    print("INDOOR WORK %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
