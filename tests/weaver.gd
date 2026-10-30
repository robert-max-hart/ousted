# ----------------------------------------------------------------
# Sheep, wool and the Weaver
#     Sheep give wool, farmers collect it; an Artisan at the Weaver's
#     Workshop turns wool fetched from storage into cloth; both are
#     tradeable luxuries.
#     godot --headless --path . --fixed-fps 60 res://tests/weaver.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;
var world:World;
var _pen:Pasture;
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
    world.seeds.unlock_all();
    Weather._day_offset = 0.0;
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON * 1 + 2) * GameClock.HOURS_PER_DAY + 12.0;
    Weather._update_temperature();
    var o:Vector2i = world.town_hall.origin + Vector2i(8, -10);
    for rn in world.nodes.duplicate():
        if Rect2i(o - Vector2i(3, 3), Vector2i(26, 14)).has_point(rn.cell):
            world.remove_node(rn);
    world.terrain.flatten_rect(Rect2i(o - Vector2i(2, 2), Vector2i(28, 16)));
    _pen = world.place_building(&"sheepfold", o, Vector2i(5, 5), true) as Pasture;
    _shop = world.place_building(&"weaver", o + Vector2i(10, 0), Vector2i(3, 3), true);
    _expect("a sheep pasture is a pasture for sheep", _pen != null and _pen.def["animal"] == &"sheep");
    _expect("it holds %d sheep (5x5 / 3)" % _pen.capacity_animals(), _pen.capacity_animals() == 8);
    _expect("wool and cloth have trade values", Defs.trade_value(&"wool") > 0 and Defs.trade_value(&"cloth") > Defs.trade_value(&"wool") * 3);
    _expect("neither spoils", not Defs.ITEMS[&"wool"].has("spoil_days") and not Defs.ITEMS[&"cloth"].has("spoil_days"));
    _expect("Artisan is a profession", JobManager.PROFESSION_NAMES[JobManager.Profession.ARTISAN] == "Artisan");
    _expect("the workshop gives two artisan positions", world.jobs.total_slots(JobManager.Profession.ARTISAN) == 2);
    _pen.add_animals(6);
    for i in 20:
        _pen.on_day();
    _expect("sheep grow wool (%d ready)" % _pen.ready_product, _pen.ready_product >= Pasture.COLLECT_AT);
    _expect("it is wool they give", _pen.collectable().get("item", &"") == &"wool");
    _expect("merchants can offer sheep", Defs.ANIMALS.has(&"sheep") and Defs.animal_key(&"sheep") != &"");
    # the Artisan works from stored wool
    world.town_hall.store(&"wool", 9);
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
    if Stock.amount(&"cloth") >= 3 or hours > 60.0:
        _expect("cloth was woven (%d, in %.1f h)" % [Stock.amount(&"cloth"), hours], Stock.amount(&"cloth") >= 3);
        print("WEAVER %s" % ("PASS" if _fails == 0 else "FAIL"));
        get_tree().quit(1 if _fails > 0 else 0);
        _phase = 2;

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
