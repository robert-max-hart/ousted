# ----------------------------------------------------------------
# Cremation run test
#     In a running colony: a full graveyard with a crematorium and coal
#     in the Town Hall. Laborers must fetch the coal on their own, and
#     the oldest graves are then burned, one coal each, until the wanted
#     number of squares is free.
#     godot --headless --path . --fixed-fps 60 res://tests/cremation_run.tscn
# ----------------------------------------------------------------
extends Node;

var world:World;
var yard:Graveyard;
var _coal_start:int;
var _days:int = 0;
var _last_day:int = -1;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    Engine.time_scale = 4.0;
    GameClock.set_speed(3);
    for p in world.pawns:
        p.profession = JobManager.Profession.LABORER;
    world.jobs.sync_targets();
    var th:Building = world.town_hall;
    world.place_building(&"house", th.origin + Vector2i(-8, 2), Vector2i(3, 3), true);
    yard = world.place_building(&"graveyard", th.origin + Vector2i(6, -2), Vector2i(3, 2), true) as Graveyard;
    for i in 6:
        yard.graves[i] = {"name": "G%d" % i, "age": 40, "cause": "old age", "buried_hour": float(i)};
    yard.upgrades_done[&"crematorium"] = true;
    yard.settings["keep_free"] = 3;
    th.store(&"coal", 6);
    _coal_start = Stock.amount(&"coal");
    _expect("coal is in storage", _coal_start == 6);

func _process(_delta:float) -> void:
    var d:int = GameClock.day_index();
    if d == _last_day:
        return;
    _last_day = d;
    _days += 1;
    print("day %d: free graves %d, coal in graveyard %d, coal in storage %d" % [_days, yard.free_slots(), yard.input_amount(&"coal"), Stock.amount(&"coal")]);
    if yard.free_slots() >= 3 or _days >= 6:
        _expect("laborers fetched coal and the graves were freed", yard.free_slots() >= 3);
        _expect("one coal per body: %d graves freed, %d coal used" % [yard.free_slots(), _coal_start - Stock.amount(&"coal") - yard.input_amount(&"coal")], _coal_start - Stock.amount(&"coal") - yard.input_amount(&"coal") == yard.free_slots());
        _expect("the oldest were burned", yard.graves[0] == null and yard.graves[1] == null and yard.graves[2] == null);
        get_tree().quit();

func _expect(what:String, ok:bool) -> void:
    print(("PASS " if ok else "FAIL ") + what);
