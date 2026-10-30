# ----------------------------------------------------------------
# Pottery
#     An Artisan at the Potter's Workshop turns stone (with water, which
#     the workshop must have in reach) into pottery to trade.
#     godot --headless --path . --fixed-fps 60 res://tests/pottery.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;
var world:World;
var _shop:Building;
var _phase:int = 0;
var _start:float = 0.0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    Weather.drought_enabled = false;
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    var o:Vector2i = TestSite.spot(world, Vector2i(3, 3), Vector2i(5, -7));
    for rn in world.nodes.duplicate():
        if Rect2i(o - Vector2i(3, 3), Vector2i(16, 12)).has_point(rn.cell):
            world.remove_node(rn);
    world.terrain.flatten_rect(Rect2i(o - Vector2i(2, 2), Vector2i(18, 14)));
    _shop = world.place_building(&"pottery", o, Vector2i(3, 3), true);
    _expect("pottery is a tradeable good, not a food", Defs.trade_value(&"pottery") >= 10 and not Defs.is_food(&"pottery") and not Defs.is_treat(&"pottery"));
    _expect("it needs only stone (and water in reach)", _shop.def["inputs"].keys() == [&"stone"] and _shop.def["needs_water"] > 0.0);
    _expect("stone is worth less than the pottery it makes", 4 * Defs.trade_value(&"stone") < 2 * Defs.trade_value(&"pottery"));
    _expect("it is in the build menu and the Industry group", Defs.BUILD_MENU.has(&"pottery") and (Defs.BUILD_CATEGORIES[3][1] as Array).has(&"pottery"));
    _expect("it is an artisan building", _shop.def["profession"] == "ARTISAN");
    world.town_hall.store(&"stone", 8);
    var artisan:Pawn = world.pawns[0];
    artisan.profession = JobManager.Profession.ARTISAN;
    world.jobs.change_profession(JobManager.Profession.ARTISAN, 1);
    GameClock.set_speed(3);
    Engine.time_scale = 4.0;
    _start = GameClock.total_hours;
    _phase = 1;

func _process(_delta:float) -> void:
    if _phase != 1:
        return;
    for p in world.pawns:
        p.hunger = 1.0; p.thirst = 1.0; p.energy = 1.0; p.warmth = 1.0;
    var hours:float = GameClock.total_hours - _start;
    if Stock.amount(&"pottery") >= 4 or hours > 80.0:
        _expect("pottery was made (%d, %.1f h)" % [Stock.amount(&"pottery"), hours], Stock.amount(&"pottery") >= 4);
        print("POTTERY %s" % ("PASS" if _fails == 0 else "FAIL"));
        get_tree().quit(1 if _fails > 0 else 0);
        _phase = 2;

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
