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
    var wanted:Array[StringName] = [&"house", &"field", &"well", &"house", &"field"];
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
    var n:int = 0;
    for rn in world.nodes:
        if not rn.is_auto() and Vector2(rn.cell - th.origin).length() < 22 and n < 25:
            world.set_designated(rn, true);
            n += 1;
    print("designated %d nodes" % n);
    _exercise_tools();

# Pokes the same code paths the player tools use.
func _exercise_tools() -> void:
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

func _report() -> void:
    print("\n=== %s %s | %s %.1fC | pop %d" % [GameClock.date_string(), GameClock.time_string(), Weather.description(), Weather.temperature, world.pawns.size()]);
    var stock:PackedStringArray = [];
    for item in Defs.ITEMS:
        stock.append("%s=%d" % [item, Stock.amount(item)]);
    print("stock: ", ", ".join(stock));
    for p in world.pawns:
        print("  %-8s %-9s H%.2f T%.2f E%.2f W%.2f HP%.2f | %s" % [p.first_name, p.profession_name(), p.hunger, p.thirst, p.energy, p.warmth, p.health, p.status]);
    for b in world.buildings:
        var extra:String = "";
        if b is Field and b.is_complete():
            extra = (b as Field).info_text().split("\n")[1];
        print("  [%s] %s %d%% builders=%d %s" % [b.display_name(), "done" if b.is_complete() else "building", roundi(b.progress() * 100), b.builders, extra]);
