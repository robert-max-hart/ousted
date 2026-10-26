# ----------------------------------------------------------------
# Forage probe
#     Not pass/fail: puts a Forager's Hut where the most wild food is in
#     reach, staffs it, and prints per season how much each food was
#     picked and how much stands in range, to tune respawn rates.
#     godot --headless --path . --fixed-fps 60 res://tests/forage_probe.tscn -- <years> <foragers>
# ----------------------------------------------------------------
extends Node;

var world:World;
var hut:Building;
var years:int = 1;
var foragers:int = 2;
var _last_day:int = -1;
var _picked:Dictionary = {};
var _seen:Dictionary = {};

func _ready() -> void:
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0:
        years = args[0].to_int();
    if args.size() > 1:
        foragers = args[1].to_int();
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    Engine.time_scale = 4.0;
    GameClock.set_speed(3);
    var best:Vector2i = Vector2i.ZERO;
    var best_n:int = -1;
    var size:Vector2i = Defs.BUILDINGS[&"forager"]["size"];
    for dz in range(-30, 31, 2):
        for dx in range(-30, 31, 2):
            var o:Vector2i = world.town_hall.origin + Vector2i(dx, dz);
            if world.can_place(&"forager", o, size) != "" or not world._rect_free_of_nodes(Rect2i(o, size)):
                continue;
            var n:int = _in_range(o + size / 2).size();
            if n > best_n:
                best_n = n;
                best = o;
    hut = world.place_building(&"forager", best, size, true);
    var set_up:int = 0;
    for p in world.pawns:
        if set_up < foragers and p.is_adult():
            p.profession = JobManager.Profession.FORAGER;
            set_up += 1;
    world.jobs.sync_targets();
    hut.settings["cap_food"] = 0;
    for p in world.pawns:
        if p.profession == JobManager.Profession.FORAGER:
            continue;
        p.profession = JobManager.Profession.LABORER;
    world.jobs.sync_targets();
    print("hut at %s with %d wild foods in range, %d foragers" % [best, best_n, foragers]);

func _in_range(center:Vector2i) -> Array:
    return world.nodes.filter(func(rn:ResourceNode) -> bool: return rn.is_forageable() and Vector2(rn.cell).distance_to(Vector2(center)) <= 16.0);

func _process(_delta:float) -> void:
    var d:int = GameClock.day_index();
    if d == _last_day:
        return;
    _last_day = d;
    world.town_hall.take(&"wheat", maxi(0, world.town_hall.amount(&"wheat") - 50));      # keep room in storage
    if d % GameClock.DAYS_PER_SEASON == 0 and d > 0:
        _report();
    if d >= years * GameClock.DAYS_PER_YEAR:
        get_tree().quit();

func _report() -> void:
    var now:Dictionary = {};
    for item in [&"berries", &"mushrooms", &"hazelnuts"]:
        now[item] = Stock.amount(item);
    var wild:Dictionary = {};
    for rn in _in_range(hut.origin + hut.size / 2):
        wild[rn.item] = wild.get(rn.item, 0) + rn.amount;
    var doing:Array = world.pawns.filter(func(p:Pawn) -> bool: return p.profession == JobManager.Profession.FORAGER).map(func(p:Pawn) -> String: return "%s (hunger %.2f, health %.2f)" % [p.status, p.hunger, p.health]);
    print("  foragers: ", doing, " hall %d / %d, room for hazelnuts: %s" % [world.town_hall.used(), world.town_hall.capacity(), Stock.has_room_for(&"hazelnuts")]);
    print("%s | in storage: berries %d, mushrooms %d, hazelnuts %d | still on the ground in range: berries %d, mushrooms %d, hazelnuts %d | food %d" % [
        GameClock.date_string(), now[&"berries"], now[&"mushrooms"], now[&"hazelnuts"], wild.get(&"berries", 0), wild.get(&"mushrooms", 0), wild.get(&"hazelnuts", 0), Stock.food_total()]);
