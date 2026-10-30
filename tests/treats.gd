# ----------------------------------------------------------------
# Treats
#     Citizens eat honey now and then for a mood boost that lasts days:
#     only when the last boost has worn off, so the stock is not all
#     used at once; the policy switches it off.
#     godot --headless --path . --fixed-fps 60 res://tests/treats.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;
var world:World;
var _start:float = 0.0;
var _phase:int = 0;
var _eaten:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    Weather.drought_enabled = false;
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    Weather._day_offset = 0.0;
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON * 1 + 2) * GameClock.HOURS_PER_DAY + 8.0;
    Weather._update_temperature();
    var p:Pawn = world.pawns[0];
    _expect("honey is a treat and not a food", Defs.is_treat(&"honey") and not Defs.is_food(&"honey"));
    world.town_hall.store(&"honey", 10);
    _expect("the best treat is honey", Stock.best_treat() == &"honey");
    _expect("a citizen who never had one is made to wait a while", p.treat_ready == 0.0);
    _expect("the wait is set the first time they are asked", not p.wants_treat() or p.treat_ready > 0.0);
    var mood0:float = p.target_mood();
    p.treat_ready = 1.0;
    _expect("a citizen with no boost wants one", p.wants_treat());
    var h0:float = 0.5;
    p.hunger = h0;
    p.enjoy_treat(&"honey", Defs.ITEMS[&"honey"]["treat"]);
    _expect("it feeds a little (%.2f)" % p.hunger, p.hunger > h0 and p.hunger < h0 + 0.15);
    _expect("it lifts the mood target (%.2f to %.2f)" % [mood0, p.target_mood()], p.target_mood() > mood0 + 0.1 or p.target_mood() >= 1.0);
    var named:bool = false;
    for f in p.happiness_factors():
        named = named or str(f[0]).begins_with("Enjoyed honey");
    _expect("the factor is listed", named);
    _expect("and they want no more while it lasts", not p.wants_treat());
    GameClock.total_hours += 3.0 * GameClock.HOURS_PER_DAY;
    _expect("still boosted after three days", p.treat_boost_now() > 0.0 and not p.wants_treat());
    GameClock.total_hours += 1.5 * GameClock.HOURS_PER_DAY;
    _expect("the boost wears off after four", p.treat_boost_now() == 0.0);
    GameClock.total_hours += 1.5 * GameClock.HOURS_PER_DAY;
    _expect("and then they want another", p.wants_treat());
    var d:Dictionary = p.to_dict();
    p.treat_until = 0.0;
    p.restore(world, d);
    _expect("the boost is saved", p.treat_until > 0.0 and p.treat_item == &"honey");
    # in play: a day or so with the policy on, then off
    for q in world.pawns:
        q.treat_until = 0.0;
        q.treat_ready = 1.0;
    world.policies.set_on(&"treats", false);
    var t:Task = world.jobs.needs.treat_task(world.pawns[1]);
    _expect("with the policy off nobody goes for one", t == null);
    world.policies.set_on(&"treats", true);
    GameClock.set_speed(3);
    Engine.time_scale = 4.0;
    _start = GameClock.total_hours;
    _phase = 1;

func _physics_process(_delta:float) -> void:
    if _phase != 1:
        return;
    for p in world.pawns:
        p.hunger = 1.0; p.thirst = 1.0; p.energy = 1.0; p.warmth = 1.0;
    if GameClock.total_hours - _start > 20.0:
        var left:int = Stock.amount(&"honey");
        var boosted:int = 0;
        for p in world.pawns:
            if p.treat_boost_now() > 0.0:
                boosted += 1;
        _expect("citizens ate some honey on their own (%d left, %d boosted)" % [left, boosted], left < 10 and boosted >= 1);
        _expect("but each only one (%d of 10 used by %d citizens)" % [10 - left, world.pawns.size()], 10 - left <= world.pawns.size());
        print("TREATS %s" % ("PASS" if _fails == 0 else "FAIL"));
        get_tree().quit(1 if _fails > 0 else 0);
        _phase = 2;

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
