# ----------------------------------------------------------------
# Policies test
#     Checks the child labor rule: with it allowed a child with no
#     school works, forbidden the child goes home (and a running
#     work task ends at once), allowed again it works. Also checks
#     the rule is saved.
#     godot --headless --path . --fixed-fps 60 res://tests/policies.tscn
# ----------------------------------------------------------------
extends Node;

const WORK_KINDS:Array[StringName] = [&"harvest", &"build", &"haul", &"farm", &"collect", &"fuel", &"dig", &"forge", &"plant", &"supply"];

var world:World;
var _child:Pawn;
var _phase:int = 0;
var _phase_start:float;
var _work_frames:int = 0;
var _home_frames:int = 0;
var _start:float;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";        # room to store what the laborers clear: full storage would leave the child idle
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    Engine.time_scale = 4.0;
    GameClock.set_speed(3);
    Defs.ageing_days_per_year = 400.0;      # the child stays a child
    for p in world.pawns:
        p.profession = JobManager.Profession.LABORER;
        p.age = 30.0;
    world.jobs.sync_targets();
    world.place_building(&"house", TestSite.spot(world, Vector2i(3, 3), Vector2i(-8, 2)), Vector2i(3, 3), true);     # the child needs a bed: nobody sleeps in the Town Hall
    _child = world.pawns[2];
    _child.age = 10.0;
    _designate_work();
    _expect("child labor is allowed by default", world.policies.is_on(&"child_labor"));
    _start = GameClock.total_hours;
    _phase_start = _start;

# Marks the 40 nearest untouched nodes for clearing, so laborers always have something to do. Adults clear them
# quickly, so this runs again at the start of each phase.
func _designate_work() -> void:
    var near:Array = world.nodes.filter(func(n:ResourceNode) -> bool: return not n.designated and not n.is_auto());
    near.sort_custom(func(a:ResourceNode, b:ResourceNode) -> bool:
        return Vector2(a.cell - world.town_hall.origin).length() < Vector2(b.cell - world.town_hall.origin).length());
    for i in mini(40, near.size()):
        world.set_designated(near[i], true);

func _process(_delta:float) -> void:
    if not World.alive(_child):
        return;
    var elapsed:float = GameClock.total_hours - _phase_start;
    var kind:StringName = _child.task.kind if _child.task != null else &"";
    if GameClock.is_night() or _child.energy < 0.2 or _child.hunger < 0.4 or _child.thirst < 0.45 or _child.warmth < 0.35:
        return;       # needs and sleep come before work or staying home
    if _phase == 0:
        if WORK_KINDS.has(kind):
            _work_frames += 1;
        if elapsed > 60.0 or (_work_frames > 0 and elapsed > 6.0):
            _expect("allowed: the child worked (%d frames)" % _work_frames, _work_frames > 0);
            world.policies.set_on(&"child_labor", false);
            _expect("forbidding ends a running work task", not WORK_KINDS.has(_child.task.kind) if _child.task != null else true);
            _designate_work();
            _phase = 1;
            _phase_start = GameClock.total_hours;
            _work_frames = 0;
    elif _phase == 1:
        if elapsed < 1.0:
            return;
        if WORK_KINDS.has(kind):
            _work_frames += 1;
        if kind == &"stay_home":
            _home_frames += 1;
        if elapsed > 24.0:
            _expect("forbidden: the child did no work (%d frames)" % _work_frames, _work_frames == 0);
            _expect("forbidden: the child stayed home (%d frames)" % _home_frames, _home_frames > 0);
            var saved:Dictionary = world.serialize();
            _expect("the rule is saved", saved["policies"].get(&"child_labor", true) == false);
            var p:Policies = Policies.new();
            p.restore(saved["policies"]);
            _expect("the rule loads back", not p.is_on(&"child_labor"));
            p.restore({});
            _expect("an old save keeps the default", p.is_on(&"child_labor"));
            world.policies.set_on(&"child_labor", true);
            _designate_work();
            _phase = 2;
            _phase_start = GameClock.total_hours;
            _work_frames = 0;
    elif _phase == 2:
        if WORK_KINDS.has(kind):
            _work_frames += 1;
        if elapsed > 40.0:
            _expect("allowed again: the child worked (%d frames)" % _work_frames, _work_frames > 0);
            get_tree().quit();

func _expect(what:String, ok:bool) -> void:
    print("%s: %s" % ["PASS" if ok else "FAIL", what]);
