# ----------------------------------------------------------------
# Idle professionals work as laborers
#     A citizen whose own job has nothing to do falls back to the
#     laborer's whole list (building, roads, ...), not just hauling.
#     godot --headless --path . --fixed-fps 60 res://tests/idle_laborer.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    GameClock.total_hours = 12.0;       # midday: not a sleeping hour
    var o:Vector2i = world.town_hall.origin + Vector2i(8, -10);
    for rn in world.nodes.duplicate():
        if Rect2i(o - Vector2i(3, 3), Vector2i(16, 12)).has_point(rn.cell):
            world.remove_node(rn);
    world.terrain.flatten_rect(Rect2i(o - Vector2i(2, 2), Vector2i(18, 14)));
    for p in world.pawns:
        p.hunger = 1.0; p.thirst = 1.0; p.energy = 1.0; p.warmth = 1.0;
    var site:Building = world.place_building(&"house", o, Vector2i(3, 3));
    for item in site.cost():
        site.delivered[item] = site.cost()[item];
    world.plan_road(o + Vector2i(6, 0));
    var kinds:Dictionary = {};
    for prof in [JobManager.Profession.FARMER, JobManager.Profession.BLACKSMITH, JobManager.Profession.WOODCUTTER, JobManager.Profession.TEACHER, JobManager.Profession.MINER, JobManager.Profession.FORAGER]:
        var p:Pawn = world.pawns[0];
        p.end_task(false);
        p.profession = prof;
        site.builders = 0;
        var t:Task = world.jobs.choose_task(p);
        kinds[prof] = t.kind if t != null else &"none";
        p.end_task(false);
        for q in world.pawns:
            q.end_task(false);
        site.builders = 0;
        world.road_claimed.clear();
    for prof in kinds:
        var name:String = JobManager.PROFESSION_NAMES[prof];
        _expect("a %s with nothing of their own to do works as a laborer (got %s)" % [name.to_lower(), kinds[prof]], kinds[prof] == &"build" or kinds[prof] == &"road" or (kinds[prof] == &"harvest" and [JobManager.Profession.MINER, JobManager.Profession.FORAGER].has(prof)));
    print("IDLE LABORER %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    print(("PASS " if ok else "FAIL ") + what);
    if not ok:
        _fails += 1;
