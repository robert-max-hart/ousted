# ----------------------------------------------------------------
# Miners work inside the mine
#     A miner who is digging steps inside the mine (out of sight, like a
#     blacksmith in the smithy) instead of standing beside it, and comes
#     out to carry the ore to storage.
#     godot --headless --path . --fixed-fps 60 res://tests/mine_inside.tscn
# ----------------------------------------------------------------
extends Node;

var world:World;
var _fails:int = 0;
var _frame:int = 0;
var _start:float = 0.0;
var _mine:Building;
var _m:Pawn;
var _was_inside:bool = false;
var _hidden_while_inside:bool = true;
var _carried_out:bool = false;
var _stone0:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    GameClock.reset();
    GameClock.total_hours = float(2 * GameClock.HOURS_PER_DAY + 8);
    Weather.reset();
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    world.world_seed = 2468;
    add_child(world);

func _process(_delta:float) -> void:
    _frame += 1;
    if _frame == 3:
        var o:Vector2i = TestSite.near(world, Vector2i(-14, 8), Vector2i(7, 7));
        _mine = world.place_building(&"mine", o, Vector2i(5, 5), true);
        _expect("the mine is a workplace to step inside", _mine.def.get("indoor_work", false));
        _m = world.pawns[0];
        _m.profession = JobManager.Profession.MINER;
        world.jobs.sync_targets();
        _stone0 = Stock.amount(&"stone") + Stock.amount(&"iron");
        _start = GameClock.total_hours;
        GameClock.set_speed(3);
        Engine.time_scale = 4.0;
    if _frame > 3:
        for q in world.pawns:
            q.hunger = 1.0; q.thirst = 1.0; q.energy = 1.0; q.warmth = 1.0;
        var inside:bool = _m._inside_work != null and is_same(_m._inside_work, _mine);
        if inside:
            _was_inside = true;
            if _m.visible:
                _hidden_while_inside = false;
        if _was_inside and not inside and _m.carry_amount > 0 and _m.visible:
            _carried_out = true;
        var hours:float = GameClock.total_hours - _start;
        var got:int = Stock.amount(&"stone") + Stock.amount(&"iron") - _stone0;
        if (_carried_out and got > 0) or hours > 80.0:
            Engine.time_scale = 1.0;
            _expect("the miner went inside the mine to dig", _was_inside);
            _expect("and was out of sight while inside", _hidden_while_inside);
            _expect("then came out carrying ore", _carried_out);
            _expect("and the ore reached storage (%d)" % got, got > 0);
            print("MINE INSIDE %s (%.1f hours)" % ["PASS" if _fails == 0 else "FAIL", hours]);
            get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
