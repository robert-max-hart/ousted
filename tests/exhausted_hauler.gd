# ----------------------------------------------------------------
# Exhausted hauler
#     A citizen with no energy left who is carrying goods must drop them
#     off and go to bed. It used to loop for ever: the energy check
#     interrupted every task each frame while the drop-off came before
#     sleep, so the delivery never reached its last step (found in a
#     playtest save, see docs/notes/m8.md). Checked by day, with the
#     load full and not full.
#     godot --headless --path . --fixed-fps 60 res://tests/exhausted_hauler.tscn
# ----------------------------------------------------------------
extends Node;

var world:World;
var _fails:int = 0;
var _frame:int = 0;
var _start:float = 0.0;
var _p:Pawn;
var _q:Pawn;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    GameClock.reset();
    GameClock.total_hours = float(2 * GameClock.HOURS_PER_DAY + 11);        # late morning
    Weather.reset();
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    world.world_seed = 777;
    add_child(world);

func _process(_delta:float) -> void:
    _frame += 1;
    if _frame == 3:
        _p = world.pawns[0];
        _q = world.pawns[1];
        var site:Vector2i = TestSite.near(world, Vector2i(-6, 8), Vector2i(4, 4));
        world.place_building(&"stockpile", site, Vector2i(4, 4), true);          # the only store: the citizens start a walk from it
        var far:Vector2i = TestSite.near(world, Vector2i(-20, 8), Vector2i(4, 4));
        _p.position = world.terrain.cell_center(far);
        _q.position = world.terrain.cell_center(far + Vector2i(1, 1));
        for who in [_p, _q]:
            who.task = null;
            who.profession = JobManager.Profession.LABORER;
            who.energy = 0.0;
            who.hunger = 1.0;
            who.thirst = 1.0;
            who.warmth = 1.0;
        _p.set_carry(&"wood", Pawn.CARRY_CAP);        # a full load
        _q.set_carry(&"wood", 3);                      # room for more: it must not go chopping to top it up
        _start = GameClock.total_hours;
        GameClock.set_speed(3);
        Engine.time_scale = 4.0;
    if _frame > 3:
        for who in [_p, _q]:
            who.hunger = 1.0; who.thirst = 1.0; who.warmth = 1.0;
        var hours:float = GameClock.total_hours - _start;
        var done:bool = _p.carry_amount == 0 and _q.carry_amount == 0 and (_p.sleeping or _p.energy > 0.2) and (_q.sleeping or _q.energy > 0.2);
        if done or hours > 6.0:
            _expect("both dropped their loads (%d, %d left)" % [_p.carry_amount, _q.carry_amount], _p.carry_amount == 0 and _q.carry_amount == 0);
            _expect("and went to bed or are rested (%s sleeping %s energy %.2f, %s sleeping %s energy %.2f)" % [_p.first_name, _p.sleeping, _p.energy, _q.first_name, _q.sleeping, _q.energy], done);
            Engine.time_scale = 1.0;
            print("EXHAUSTED HAULER %s (%.1f hours)" % ["PASS" if _fails == 0 else "FAIL", hours]);
            get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
