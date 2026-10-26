# ----------------------------------------------------------------
# Tuning probe
#     Not a pass/fail test: keeps the colony fed and housed and prints
#     population by life stage, births, deaths, mood and experience per
#     season, to judge the pairing, birth and experience numbers.
#     godot --headless --path . --fixed-fps 60 res://tests/tuning_probe.tscn -- <years>
# ----------------------------------------------------------------
extends Node;

var world:World;
var years:int = 4;
var _last_day:int = -1;
var _born:int = 0;
var _seen:int = 0;
var _logged:int = 0;

func _ready() -> void:
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0 and args[0].is_valid_int():
        years = args[0].to_int();
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    Engine.time_scale = 4.0;
    GameClock.set_speed(3);
    var th:Building = world.town_hall;
    for i in 0 if OS.get_cmdline_user_args().has("bare") else (1 if OS.get_cmdline_user_args().has("tight") else 3):
        world.place_building(&"house", th.origin + Vector2i(-8 - 4 * i, 0), Vector2i(3, 3), true);
    if OS.get_cmdline_user_args().has("yard"):
        world.place_building(&"graveyard", th.origin + Vector2i(6, 6), Vector2i(6, 4), true);
    world.place_building(&"school", th.origin + Vector2i(8, -8), Vector2i(4, 4), true);
    world.jobs.change_profession(JobManager.Profession.TEACHER, 1);
    world.families.assign_homes();
    if OS.get_cmdline_user_args().has("spread"):         # two to a house, so couples have room for a baby
        var houses:Array[Building] = world.buildings.filter(func(b:Building) -> bool: return b.def_id == &"house");
        for i in world.pawns.size():
            world.families.move_home(world.pawns[i], houses[i % houses.size()]);
    _seen = world.pawns.size();

func _process(_delta:float) -> void:
    var d:int = GameClock.day_index();
    if d == _last_day:
        return;
    _last_day = d;
    world.town_hall.store(&"wheat", maxi(0, 120 - Stock.amount(&"wheat")));
    world.town_hall.store(&"firewood", maxi(0, 60 - Stock.amount(&"firewood")));
    if d % GameClock.DAYS_PER_SEASON == 0:
        _report(d);
    if d >= years * GameClock.DAYS_PER_YEAR:
        get_tree().quit();

func _report(d:int) -> void:
    if OS.get_cmdline_user_args().has("houses") and Weather.temperature < 8.0:
        for b in world.buildings:
            if b.def_id == &"house":
                print("  house: residents %d, fuel %d, heating %s, warm %s" % [b.residents.size(), b.fuel, b.settings.get("heating"), b.is_heated()]);
        var a:Pawn = world.pawns.filter(func(x:Pawn) -> bool: return x.is_adult())[0];
        print("  firewood in stock %d, storage near: %s, fuel task: %s, adult status: %s, kinds: %s" % [Stock.amount(&"firewood"), world.nearest_storage_with(&"firewood", a.position), world.jobs._fuel_task(a), a.status, world.pawns.filter(func(x:Pawn) -> bool: return x.is_adult()).map(func(x:Pawn) -> String: return x.status)]);
        for p in world.pawns:
            if p.is_baby() or not p.is_adult():
                print("  young %s age %.1f warmth %.2f health %.2f home %s status %s" % [p.first_name, p.age, p.warmth, p.health, p.home != null, p.status]);
    if world.death_log.size() > _logged:
        for e in world.death_log.slice(_logged):
            print("  death: %s, age %d, %s, %s, %s" % [e["name"], e["age"], e["cause"], e["profession"], e["when"]]);
        _logged = world.death_log.size();
    var babies:int = 0;
    var kids:int = 0;
    var adults:int = 0;
    var mood:float = 0.0;
    var xp:float = 0.0;
    var gen:float = 0.0;
    var oldest:float = 0.0;
    var coupled:int = 0;
    var housed:int = 0;
    var pregnant:int = 0;
    for p in world.pawns:
        coupled += 1 if p.partner != null else 0;
        housed += 1 if p.home != null else 0;
        pregnant += 1 if p.due_hour >= 0.0 else 0;
        if p.is_baby():
            babies += 1;
        elif p.is_adult():
            adults += 1;
            mood += p.mood;
            xp += p.job_xp.values().max() if not p.job_xp.is_empty() else 0.0;
            gen += p.general_xp;
        else:
            kids += 1;
        oldest = maxf(oldest, p.age);
    var n:int = maxi(1, adults);
    print("%s | pop %d (babies %d, children %d, adults %d) deaths %d | adult mood %.2f, best job xp %.2f, schooling %.2f | oldest %.0f | coupled %d, housed %d, pregnant %d | graves %d, bodies %d, shacks %d, homeless %d" % [
        GameClock.date_string() if GameClock.has_method("date_string") else "day %d" % d,
        world.pawns.size(), babies, kids, adults, world.death_log.size(), mood / n, xp / n, gen / n, oldest, coupled, housed, pregnant, _graves(), world.bodies.size(), _shacks(), world.families.homeless_count()]);

func _graves() -> int:
    var n:int = 0;
    for b in world.buildings:
        if b is Graveyard:
            n += (b as Graveyard).used_slots();
    return n;

func _shacks() -> int:
    return world.buildings.filter(func(b:Building) -> bool: return b.def.get("shack", false)).size();
