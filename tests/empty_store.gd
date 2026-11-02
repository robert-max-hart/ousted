# ----------------------------------------------------------------
# Empty it out
#     A store the player marks "emptying" is cleared by citizens (its
#     goods go to other stores), takes nothing new, and can then be
#     demolished, which is refused while goods are in it. The flag is
#     saved with the building.
#     godot --headless --path . --fixed-fps 60 res://tests/empty_store.tscn
# ----------------------------------------------------------------
extends Node;

var world:World;
var _fails:int = 0;
var _frame:int = 0;
var _start:float = 0.0;
var _a:Building;
var _b:Building;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    GameClock.reset();
    GameClock.total_hours = float(2 * GameClock.HOURS_PER_DAY + 8);
    Weather.reset();
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    world.world_seed = 31337;
    add_child(world);

func _process(_delta:float) -> void:
    _frame += 1;
    if _frame == 3:
        var oa:Vector2i = TestSite.near(world, Vector2i(-12, 8), Vector2i(6, 6));
        _a = world.place_building(&"stockpile", oa, Vector2i(4, 4), true);
        var ob:Vector2i = TestSite.near(world, Vector2i(12, 8), Vector2i(6, 6));
        _b = world.place_building(&"stockpile", ob, Vector2i(4, 4), true);
        _a.store(&"stone", 40);
        _a.store(&"wood", 25);
        world.remove_building(_a, false);
        _expect("a store with goods in it cannot be demolished", World.alive(_a) and _a.used() == 65);
        _a.emptying = true;
        _expect("an emptying store takes nothing new", not _a.can_store(&"wood"));
        _expect("and it is the worst place for what it holds (rank %.0f)" % _a.storage_rank(&"wood"), _a.storage_rank(&"wood") >= 100.0);
        var d:Dictionary = _a.to_dict();
        _expect("the flag is saved", d.get("emptying", false) == true);
        for q in world.pawns:
            q.profession = JobManager.Profession.LABORER;
        _start = GameClock.total_hours;
        GameClock.set_speed(3);
        Engine.time_scale = 4.0;
    if _frame > 3:
        for q in world.pawns:
            q.hunger = 1.0; q.thirst = 1.0; q.energy = 1.0; q.warmth = 1.0;
        var hours:float = GameClock.total_hours - _start;
        if (_a.used() == 0 and _a.in_reserved == 0 and _a.is_empty()) or hours > 30.0:
            Engine.time_scale = 1.0;
            _expect("the store was emptied (%d left after %.0f hours)" % [_a.used(), hours], _a.used() == 0);
            _expect("its goods are in the other store (%d)" % _b.used(), _b.used() >= 65 or Stock.amount(&"stone") >= 40);
            _expect("nothing was stored back into it while emptying", _a.used() == 0);
            world.remove_building(_a, false);
            _expect("and now it can be demolished", not World.alive(_a));
            print("EMPTY STORE %s (%.1f hours)" % ["PASS" if _fails == 0 else "FAIL", hours]);
            get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
