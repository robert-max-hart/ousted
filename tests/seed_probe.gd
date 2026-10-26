# ----------------------------------------------------------------
# Seed finding probe
#     A hard start (wheat only) with a Forager's Hut, foragers and a
#     gatherer picking wild food for a number of days. Prints the day
#     each seed is found and how many foraging trips that took.
#     godot --headless --path . --fixed-fps 60 res://tests/seed_probe.tscn -- <days> [foragers] [gatherers] [difficulty]
# ----------------------------------------------------------------
extends Node;

var world:World;
var _days:int = 64;
var _known:int = 1;
var _last_day:int = -1;
var _log:PackedStringArray = [];

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    var args:PackedStringArray = OS.get_cmdline_user_args();
    _days = args[0].to_int();
    var foragers:int = args[1].to_int() if args.size() > 1 else 2;
    var gatherers:int = args[2].to_int() if args.size() > 2 else 1;
    Defs.difficulty = StringName(args[3]) if args.size() > 3 else &"hard";
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    var th:Building = world.town_hall;
    var hut:Building = null;
    for dz in range(-14, 15, 2):
        if hut == null and world.can_place(&"forager", th.origin + Vector2i(6, dz), Vector2i(3, 3)) == "":
            hut = world.place_building(&"forager", th.origin + Vector2i(6, dz), Vector2i(3, 3), true);
    for dz in range(-20, 21, 2):       # a hard start has a full Town Hall: foragers need somewhere to put what they pick
        for dx in range(-20, 21, 2):
            if world.can_place(&"stockpile", th.origin + Vector2i(dx, dz), Vector2i(6, 6)) == "" and world._rect_free_of_nodes(Rect2i(th.origin + Vector2i(dx, dz), Vector2i(6, 6))) and absi(dx) + absi(dz) > 8:
                world.place_building(&"stockpile", th.origin + Vector2i(dx, dz), Vector2i(6, 6), true);
                dx = 99;
                dz = 99;
    hut.settings["cap_food"] = 100000;       # keep foraging all the time
    for p in world.pawns:
        p.profession = JobManager.Profession.LABORER;
    world.jobs.change_profession(JobManager.Profession.FORAGER, foragers);
    world.jobs.change_profession(JobManager.Profession.GATHERER, gatherers - 1);       # one gatherer already
    world.jobs.sync_targets();
    world.jobs.reconcile();
    _known = world.seeds.known.size();
    Engine.time_scale = 12.0;
    GameClock.set_speed(3);

func _process(_delta:float) -> void:
    if world.seeds.known.size() > _known:
        _known = world.seeds.known.size();
        _log.append("day %.1f (%d trips)" % [(GameClock.total_hours - GameClock.START_HOUR) / 24.0, world.seeds.trips]);
    if GameClock.day_index() != _last_day:
        _last_day = GameClock.day_index();
        if _last_day % 4 == 0 and _days <= 12:
            var kinds:PackedStringArray = [];
            for p in world.pawns:
                kinds.append("%s:%s" % [p.profession_name().substr(0, 3), p.task.kind if p.task != null else "-"]);
            print("day %d trips %d berries %d | %s" % [_last_day, world.seeds.trips, Stock.amount(&"berries"), " ".join(kinds)]);
    if GameClock.day_index() >= _days:
        print("SEEDS found %d of %d in %d days, %d trips: %s" % [_known - 1, Defs.CROPS.size() - 1, _days, world.seeds.trips, "; ".join(_log)]);
        get_tree().quit();
