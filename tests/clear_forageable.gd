# ----------------------------------------------------------------
# Clearing foragable plants
#     A berry bush, mushrooms and a hazel marked for clearing (as when
#     a building goes over them) must get removed by laborers, with
#     the food stores empty and also with them full.
#     godot --headless --path . --fixed-fps 60 res://tests/clear_forageable.tscn
# ----------------------------------------------------------------
extends Node;

var world:World;
var _fails:int = 0;
var _phase:int = 0;
var _start:float = 0.0;
var _marked:Array[ResourceNode] = [];

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(3);
    Engine.time_scale = 4.0;
    _begin(false);

func _begin(full:bool) -> void:
    var o:Vector2i = TestSite.near(world, Vector2i(8, -10), Vector2i(16, 12));
    for rn in world.nodes.duplicate():
        if Rect2i(o - Vector2i(3, 3), Vector2i(16, 12)).has_point(rn.cell):
            world.remove_node(rn);
    if full:
        for b in world.buildings:
            if b.is_storage():
                b.store(&"wheat", b.capacity());
    _marked.clear();
    var i:int = 0;
    for kind in [&"bush", &"mushroom", &"hazel"]:
        var rn:ResourceNode = world.add_node(kind, o + Vector2i(i * 2, 0));
        rn.growth = 1.0;
        rn.amount = maxi(rn.amount, 3);
        world.mark_for_clearing(rn);
        _marked.append(rn);
        i += 1;
    _start = GameClock.total_hours;

func _process(_delta:float) -> void:
    var left:int = _marked.filter(func(rn:ResourceNode) -> bool: return not rn.removed).size();
    var hours:float = GameClock.total_hours - _start;
    for p in world.pawns:
        p.hunger = 1.0; p.thirst = 1.0; p.energy = 1.0; p.warmth = 1.0;
    if left == 0 or hours > 30.0:
        _expect("%s: every marked foragable was cleared (%d left after %.0f h)" % ["full stores" if _phase == 1 else "empty stores", left, hours], left == 0);
        _phase += 1;
        if _phase == 2:
            print("CLEAR FORAGEABLE %s" % ("PASS" if _fails == 0 else "FAIL"));
            get_tree().quit(1 if _fails > 0 else 0);
            return;
        _begin(true);

func _expect(what:String, ok:bool) -> void:
    print(("PASS " if ok else "FAIL ") + what);
    if not ok:
        _fails += 1;
