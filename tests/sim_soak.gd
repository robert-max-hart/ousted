# ----------------------------------------------------------------
# Sim soak test
#     Runs the game headless at high speed, issues a few player
#     orders and prints a daily colony summary.
#     godot --headless --path . --fixed-fps 60 res://tests/sim_soak.tscn
# ----------------------------------------------------------------
extends Node;

const DAYS:int = 6;

var world:World;
var _last_day:int = -1;

func _ready() -> void:
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    Engine.time_scale = 4.0;
    GameClock.set_speed(3);
    _issue_orders();

func _issue_orders() -> void:
    var th:Building = world.town_hall;
    var placed:int = 0;
    var wanted:Array[StringName] = [&"house", &"field", &"well", &"house", &"field", &"mine", &"blacksmith", &"woodcutter"];
    for r in range(4, 24):
        for dz in range(-r, r + 1, 3):
            for dx in range(-r, r + 1, 3):
                if placed >= wanted.size():
                    break;
                var id:StringName = wanted[placed];
                var size:Vector2i = Defs.BUILDINGS[id]["size"];
                var o:Vector2i = th.origin + Vector2i(dx, dz);
                if world.can_place(id, o, size) == "":
                    world.place_building(id, o, size);
                    print("placed %s at %s" % [id, o]);
                    placed += 1;
    for pw in world.pawns:
        if pw.profession == JobManager.Profession.LABORER:
            pw.profession = JobManager.Profession.MINER;
            break;
    for pw in world.pawns:
        if pw.profession == JobManager.Profession.LABORER:
            pw.profession = JobManager.Profession.BLACKSMITH;
            break;
    for pw in world.pawns:
        if pw.profession == JobManager.Profession.BUILDER:
            pw.profession = JobManager.Profession.WOODCUTTER;
            break;
    th.store(&"stone", 40);    # keeps the mine from starving for stone when the random world is unlucky
    th.store(&"coal", 6);       # no coal source yet, so seed some to exercise steel tools
    var n:int = 0;
    for rn in world.nodes:
        if not rn.is_auto() and Vector2(rn.cell - th.origin).length() < 22 and n < 25:
            world.set_designated(rn, true);
            n += 1;
    print("designated %d nodes" % n);
    _exercise_tools();

# Pokes the same code paths the player tools use.
func _exercise_tools() -> void:
    world.jobs.sync_targets();      # the professions above were set directly
    var th:Building = world.town_hall;
    var locked:Callable = world.is_corner_locked;
    var p:Vector3 = th.position + Vector3(14, 0, 14);
    world.terrain.apply_brush(p, 2.5, 1.0, NAN, locked);
    world.terrain.apply_brush(p, 2.5, -0.5, NAN, locked);
    world.terrain.apply_brush(p, 2.5, 0.5, p.y, locked);
    for x in range(-3, 8):
        world.set_road(th.origin + Vector2i(x, -2), true);
    world.set_road(th.origin + Vector2i(0, -2), false);
    var temp:Building = null;
    for dz in range(-20, 20, 4):
        if temp == null and world.can_place(&"stockpile", th.origin + Vector2i(-12, dz), Vector2i(4, 4)) == "":
            temp = world.place_building(&"stockpile", th.origin + Vector2i(-12, dz), Vector2i(4, 4));
    get_tree().create_timer(3.0).timeout.connect(func() -> void:
        if World.alive(temp):
            print("demolishing stockpile, delivered=", temp.delivered);
            world.remove_building(temp, true));
    world.jobs.change_profession(JobManager.Profession.FARMER, 1);
    world.jobs.change_profession(JobManager.Profession.GATHERER, -1);
    world.tools.set_mode(PlayerTools.Mode.BUILD, &"house");
    world.tools.set_mode(PlayerTools.Mode.SELECT);

func _process(_delta:float) -> void:
    var d:int = GameClock.day_index();
    if d == _last_day:
        return;
    _last_day = d;
    _report();
    if d >= DAYS:
        get_tree().quit();

var _upgrade_step:int = 0;

# Exercises the upgrade system on the mine: start, cancel with refund, start again, and check the
# exclusion and prerequisite rules on a copy of its definition.
func _exercise_upgrades() -> void:
    for b in world.buildings:
        if b.def_id != &"mine" or not b.is_complete():
            continue;
        if _upgrade_step != 0:
            continue;
        _upgrade_step = 1;
        var d:Dictionary = b.def.duplicate(true);
        d["upgrades"][&"ventilation"] = {"name": "Ventilation", "cost": {}, "work": 1.0, "excludes": [&"deep_shafts"]};
        d["upgrades"][&"lamps"] = {"name": "Lamps", "cost": {}, "work": 1.0, "requires": [&"ventilation"]};
        var real_def:Dictionary = b.def;
        b.def = d;
        print("UPGRADE rules before: ventilation='", b.upgrade_block_reason(&"ventilation"), "' lamps='", b.upgrade_block_reason(&"lamps"), "'");
        b.upgrades_done[&"deep_shafts"] = true;
        print("UPGRADE rules with deep shafts built: ventilation='", b.upgrade_block_reason(&"ventilation"), "'");
        b.upgrades_done.erase(&"deep_shafts");
        b.def = real_def;
        print("UPGRADE start: ", b.start_upgrade(&"deep_shafts"), " block now: ", b.upgrade_block_reason(&"deep_shafts"), " coal unlocked: ", b.item_unlocked(&"coal"));
        # cancel part-way, once some materials have arrived
        get_tree().create_timer(4.0).timeout.connect(func() -> void:
            if not World.alive(b) or b.upgrading == &"":
                print("UPGRADE finished before the cancel test");
                return;
            b.delivered[&"wood"] = 5;     # pretend some materials arrived, to check the refund
            var before:String = "%d/%d/%d" % [Stock.amount(&"wood"), Stock.amount(&"stone"), Stock.amount(&"iron")];
            print("UPGRADE cancelling, delivered ", b.delivered, " base ", b.all_delivered(), " stock ", before);
            b.cancel_upgrade();
            print("UPGRADE after cancel: stock ", Stock.amount(&"wood"), "/", Stock.amount(&"stone"), "/", Stock.amount(&"iron"), " delivered ", b.delivered, " upgrading '", b.upgrading, "'");
            b.start_upgrade(&"deep_shafts"));

var _killed:bool = false;

# Kills a citizen who is carrying goods, to check the goods are dropped and that their profession is refilled
# from the laborer pool.
func _exercise_death() -> void:
    if _killed or GameClock.day_index() < 3:
        return;
    _killed = true;
    var victim:Pawn = null;
    for p in world.pawns:
        if p.profession == JobManager.Profession.FARMER:
            victim = p;
    if victim == null:
        return;
    world.jobs.change_profession(JobManager.Profession.WOODCUTTER, -1);     # frees a laborer to take the farmer's place
    victim.set_carry(&"wheat", 4);
    var piles_before:int = world.piles.size();
    var farmers_before:int = world.jobs.count(JobManager.Profession.FARMER);
    world.kill_pawn(victim, "old age", true);
    print("DEATH: farmers ", farmers_before, " -> ", world.jobs.count(JobManager.Profession.FARMER), " (target ", world.jobs.target(JobManager.Profession.FARMER), "), piles ", piles_before, " -> ", world.piles.size(), ", log ", world.death_log);

func _report() -> void:
    _exercise_death();
    _exercise_upgrades();
    print("\n=== %s %s | %s %.1fC | pop %d" % [GameClock.date_string(), GameClock.time_string(), Weather.description(), Weather.temperature, world.pawns.size()]);
    var stock:PackedStringArray = [];
    for item in Defs.ITEMS:
        stock.append("%s=%d" % [item, Stock.amount(item)]);
    print("stock: ", ", ".join(stock));
    for p in world.pawns:
        print("  %-8s %-9s H%.2f T%.2f E%.2f W%.2f HP%.2f | %s | tool %s" % [p.first_name, p.profession_name(), p.hunger, p.thirst, p.energy, p.warmth, p.health, p.status, p.tool]);
    for b in world.buildings:
        var extra:String = "";
        if b is Field and b.is_complete():
            extra = (b as Field).info_text().split("\n")[1];
        elif b.def.has("upgrades"):
            extra = "upgrading '%s' %d%% delivered %s done %s coal %s" % [b.upgrading, roundi(b.progress() * 100), b.delivered, b.upgrades_done.keys(), b.item_unlocked(&"coal")];
        elif b.def.has("fuel_capacity") and b.is_complete():
            extra = "fuel %d/%d" % [b.fuel, b.def["fuel_capacity"]];
        print("  [%s] %s %d%% builders=%d %s" % [b.display_name(), "done" if b.is_complete() else "building", roundi(b.progress() * 100), b.builders, extra]);
