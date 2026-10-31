# ----------------------------------------------------------------
# Arctic probe (not part of the suite: it fails on most seeds, see CLAUDE.md)
#     Can an Arctic colony live on foraging and fishing? A normal start
#     with a Forager's Hut, a fishing hut, a woodcutter, a well and two
#     houses, all finished at the start, and no fields. Nobody is
#     topped up: it runs through the first summer and winter (day 45 by
#     default; pass a number after -- for more, then a climate id for a control run, then a number of fields, then a map seed, then "v" for citizen lines, then the crops) and prints the colony
#     every four days. Fails if fewer than 4 citizens are left.
#     godot --headless --path . --fixed-fps 60 res://tests/arctic_probe.tscn
# ----------------------------------------------------------------
extends Node;

const MIN_SURVIVORS:int = 4;

var world:World;
var days:int = 45;
var _last_day:int = -1;
var _min_pop:int = 99;
var _lowest_food:int = 999999;
var _done:bool = false;
var verbose:bool = false;          # a fifth argument turns on a line per citizen in each report
var crop_list:String = "";         # a sixth argument: the fields' crops, comma separated (default barley, wheat, radish)
var fields:int = 0;       # how many fields the colony also starts (the bot builds them; sown with hardy crops)

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Climate.current = Climate.Id.ARCTIC;
    Defs.difficulty = &"normal";
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0:
        days = args[0].to_int();
    if args.size() > 1:
        Climate.current = args[1].to_int();       # a control run: 0 temperate (the default here is 1, arctic)
    if args.size() > 2:
        fields = args[2].to_int();
    verbose = args.size() > 4 and args[4] == "v";
    crop_list = args[5] if args.size() > 5 else "";
    var map_seed:int = args[3].to_int() if args.size() > 3 else 0;       # the map changes every run; pass one to compare runs
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    world.world_seed = map_seed;
    add_child(world);
    await get_tree().process_frame;
    Engine.time_scale = 4.0;
    _build();
    GameClock.set_speed(3);

func _build() -> void:
    for id in [&"house", &"house", &"well", &"woodcutter", &"forager"]:
        var size:Vector2i = Defs.BUILDINGS[id]["size"];
        var o:Vector2i = TestSite.spot(world, size, Vector2i(6, 6));
        world.place_building(id, o, size, true);
    var fishing:bool = _place_fishing_hut();
    var wild:int = 0;
    var anchor:Vector2i = TestSite.anchor(world);
    for rn in world.nodes:
        if rn.is_forageable() and Vector2(rn.cell - anchor).length() <= 25.0:
            wild += rn.max_amount;
    var hut_rate:float = 0.0;
    for b in world.buildings:
        if b is FishingHut:
            hut_rate = (b as FishingHut).catch_rate();
    print("Arctic start: %d wild food within 25 cells of the start, fishing hut catch %.2f fish an hour" % [wild, hut_rate]);
    print("Arctic start: fishing hut %s" % ("placed" if fishing else "NOT placed (no shore)"));
    var crops:Array[StringName] = [&"barley", &"wheat", &"radish"];
    if crop_list != "":
        crops.clear();
        for c in crop_list.split(","):
            crops.append(StringName(c));
    var fsize:Vector2i = Defs.BUILDINGS[&"field"]["size"];
    var spots:Array[Vector2i] = _watered_spots(fsize, fields);
    for i in spots.size():
        var f:Field = world.place_building(&"field", spots[i], fsize) as Field;
        f.set_crop(crops[i % crops.size()]);
        print("Arctic start: field %d at %s, %d%% within reach of water" % [i + 1, spots[i], roundi(_watered_share(spots[i], fsize) * 100.0)]);
    # Nine of the twelve are adults: 2 builders (from the start), then a farm crew, foragers, fishermen and a woodcutter,
    # which is every adult. The children haul (more jobs than adults and nobody is left to carry goods).
    world.jobs.targets[JobManager.Profession.FARMER] = 2 if fields > 0 else 0;
    world.jobs.targets[JobManager.Profession.FORAGER] = 2;
    world.jobs.targets[JobManager.Profession.WOODCUTTER] = 1;
    if fishing:
        world.jobs.targets[JobManager.Profession.FISHERMAN] = 2;
    world.jobs.reconcile();

# Share of the field's cells within reach of water (see Field.NEAR_WATER_RANGE): plots out of reach grow at about a
# third of the speed, so a player puts fields right beside the water (the soak test does the same).
func _watered_share(o:Vector2i, size:Vector2i) -> float:
    var wet:int = 0;
    for z in range(o.y, o.y + size.y):
        for x in range(o.x, o.x + size.x):
            if world.near_water(Vector2i(x, z), Field.NEAR_WATER_RANGE):
                wet += 1;
    return float(wet) / (size.x * size.y);

# `count` places for fields on open ground near the start, the best watered first (ties go to the nearest).
func _watered_spots(size:Vector2i, count:int) -> Array[Vector2i]:
    var found:Array = [];
    var home:Vector2i = TestSite.anchor(world);
    for dz in range(-28, 29, 2):
        for dx in range(-28, 29, 2):
            var o:Vector2i = home + Vector2i(dx, dz);
            if world.can_place(&"field", o, size) == "" and world._rect_free_of_nodes(Rect2i(o, size)):
                found.append([_watered_share(o, size), Vector2(dx, dz).length(), o]);
    found.sort_custom(func(a:Array, b:Array) -> bool: return a[0] > b[0] + 0.05 or (absf(a[0] - b[0]) <= 0.05 and a[1] < b[1]));
    var out:Array[Vector2i] = [];
    for f in found:
        var ok:bool = true;
        for o in out:
            if Rect2i(o, size).grow(1).intersects(Rect2i(f[2], size)):
                ok = false;
        if ok:
            out.append(f[2]);
        if out.size() >= count:
            break;
    return out;

# The nearest shore where a hut fits (its pier over the water).
func _place_fishing_hut() -> bool:
    var best:Vector2i = Vector2i(-1, -1);
    var best_facing:int = 0;
    var best_d:float = INF;
    for facing in 4:
        var size:Vector2i = Vector2i(3, 4) if facing % 2 == 0 else Vector2i(4, 3);
        for z in range(6, Terrain.SIZE - 10):
            for x in range(6, Terrain.SIZE - 10):
                var o:Vector2i = Vector2i(x, z);
                var d:float = Vector2(o - world.town_hall.origin).length();
                if d < best_d and d < 40.0 and world.can_place(&"fishing_hut", o, size, false, facing) == "":
                    best = o;
                    best_facing = facing;
                    best_d = d;
    if best.x < 0:
        return false;
    var s:Vector2i = Vector2i(3, 4) if best_facing % 2 == 0 else Vector2i(4, 3);
    world.place_building(&"fishing_hut", best, s, true, false, best_facing);
    return true;

func _process(_delta:float) -> void:
    if world == null or _done:
        return;
    _min_pop = mini(_min_pop, world.pawns.size());
    _lowest_food = mini(_lowest_food, Stock.food_total());
    var day:int = GameClock.day_index();
    if day != _last_day and day % 4 == 0:
        _last_day = day;
        _report();
    if day >= days:
        _done = true;
        var ok:bool = world.pawns.size() >= MIN_SURVIVORS;
        print("\nARCTIC PROBE %s: %d citizens at day %d (lowest %d, need %d), lowest food stock %d" % ["PASS" if ok else "FAIL", world.pawns.size(), days, _min_pop, MIN_SURVIVORS, _lowest_food]);
        Engine.time_scale = 1.0;
        get_tree().quit(0 if ok else 1);

func _report() -> void:
    var jobs:Dictionary = {};
    for p in world.pawns:
        jobs[p.profession_name()] = jobs.get(p.profession_name(), 0) + 1;
    var hungry:int = world.pawns.filter(func(p:Pawn) -> bool: return p.hunger < 0.3).size();
    var cold:int = world.pawns.filter(func(p:Pawn) -> bool: return p.warmth < 0.3).size();
    print("day %2d %-6s %5.1fC | pop %2d (hungry %d, cold %d) | food %4d (fish %d, berries %d, mushrooms %d, hazelnuts %d, wheat %d) | wood %d, firewood %d | %s" % [
        GameClock.day_index(), GameClock.season_name(), Weather.temperature, world.pawns.size(), hungry, cold, Stock.food_total(),
        Stock.amount(&"fish"), Stock.amount(&"berries"), Stock.amount(&"mushrooms"), Stock.amount(&"hazelnuts"), Stock.amount(&"wheat"),
        Stock.amount(&"wood"), Stock.amount(&"firewood"), jobs]);
    if verbose:
        for p in world.pawns:
            print("      %-8s %-10s H%.2f T%.2f %s" % [p.first_name, p.profession_name(), p.hunger, p.thirst, p.status]);
    for b in world.buildings:
        if b is Field:
            var f:Field = b as Field;
            print("      field %s: %s" % [f.crop_id, ("built, " + f.info_text().split("\n")[1]) if f.is_complete() else "%d%% built" % roundi(f.progress() * 100.0)]);
