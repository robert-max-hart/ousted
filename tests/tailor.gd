# ----------------------------------------------------------------
# Clothing
#     Sheep give wool; a pasture's keep-at-most level slaughters the
#     surplus for meat and leather; Artisans at the Tailor's Workshop
#     make wool, leather and fine (both) clothes; citizens put them on,
#     lose less warmth in the cold and wear them out over years.
#     godot --headless --path . --fixed-fps 60 res://tests/tailor.tscn
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
    _pen = world.place_building(&"pasture", o, Vector2i(5, 5), true) as Pasture;
    _expect("a new pasture keeps chickens until told otherwise", _pen.kind == &"chicken");
    _expect("an empty one can change animal", _pen.set_kind(&"sheep") and _pen.kind == &"sheep");
    _shop = world.place_building(&"tailor", o + Vector2i(10, 0), Vector2i(3, 3), true);
    _expect("sheep: a pasture of 8 (%d)" % _pen.capacity_animals(), _pen.kind == &"sheep" and _pen.capacity_animals() == 8);
    _expect("Artisan is a profession with two positions here", JobManager.PROFESSION_NAMES[JobManager.Profession.ARTISAN] == "Artisan" and world.jobs.total_slots(JobManager.Profession.ARTISAN) == 2);
    _expect("clothing is not food and has trade value", Defs.is_clothing(&"clothes_fine") and not Defs.is_food(&"clothes_wool") and Defs.trade_value(&"clothes_fine") > Defs.trade_value(&"clothes_wool"));
    var basic:Dictionary = Defs.ITEMS[&"clothes_wool"]["clothing"];
    var fine:Dictionary = Defs.ITEMS[&"clothes_fine"]["clothing"];
    _expect("fine clothes keep out twice the cold", is_equal_approx(fine["warm"], basic["warm"] * 2.0));
    _expect("basic lasts 2.5 years, fine 4.5 (%s, %s days)" % [basic["days"], fine["days"]], basic["days"] == 2.5 * 32.0 and fine["days"] == 4.5 * 32.0);
    var rf:Dictionary = _shop.def["recipes"][&"clothes_fine"];
    var rw:Dictionary = _shop.def["recipes"][&"clothes_wool"];
    _expect("fine clothes need wool and leather and take twice as long", rf["inputs"].has(&"wool") and rf["inputs"].has(&"leather") and rf["hours"] == rw["hours"] * 2.0);
    # sheep and slaughter
    _pen.add_animals(6);
    for i in 20:
        _pen.on_day();
    _expect("sheep grow wool (%d ready)" % _pen.ready_product, _pen.ready_product >= Pasture.COLLECT_AT);
    _expect("nothing is slaughtered by default", _pen.animals >= 6 and _pen.ready_extra.is_empty());
    _pen.settings["keep"] = 4;
    var before:int = _pen.animals;
    for i in 3:
        _pen.on_day();
    _expect("over the keep level the surplus is slaughtered (%d to %d)" % [before, _pen.animals], _pen.animals == 4 and _pen.animals < before);
    _expect("for meat and leather (%s)" % [_pen.ready_extra], _pen.ready_extra.get(&"meat", 0) >= 3 and _pen.ready_extra.get(&"leather", 0) >= 1);
    var d:Dictionary = _pen.to_dict();
    _pen.ready_extra = {};
    _pen.restore_dict(d);
    _expect("the slaughter yield is saved", _pen.ready_extra.get(&"meat", 0) >= 3);
    _expect("farmers are sent for it", _pen.take_ready(&"meat", 99) >= 3 and _pen.take_ready(&"leather", 99) >= 1);
    # clothes on a citizen
    var p:Pawn = world.pawns[1];
    var cold:float = Weather.temperature;
    _expect("no clothes at first", p.clothing == &"" and p.cold_resist() == 0.0);
    p.dress(&"clothes_wool");
    _expect("clothes give protection", is_equal_approx(p.cold_resist(), 0.3));
    p.dress(&"clothes_fine");
    _expect("fine give twice that", is_equal_approx(p.cold_resist(), 0.6));
    p._wear_clothing(144.0 * 24.0 - 1.0);
    _expect("they last nearly 4.5 years", p.clothing == &"clothes_fine");
    p._wear_clothing(2.0);
    _expect("and then wear out", p.clothing == &"" and p.cold_resist() == 0.0);
    # cold drain is cut
    var q:Pawn = world.pawns[2];
    var r:Pawn = world.pawns[3];
    for x in [q, r]:
        x.indoors = false;
        x.warmth = 1.0;
    r.dress(&"clothes_fine");
    Weather.temperature = -10.0;
    q._update_needs(2.0);
    r._update_needs(2.0);
    var lost_bare:float = 1.0 - q.warmth;
    var lost_clad:float = 1.0 - r.warmth;
    _expect("clothed citizens lose less warmth (%.3f against %.3f)" % [lost_clad, lost_bare], lost_bare > 0.1 and absf(lost_clad - lost_bare * 0.4) < 0.01);
    Weather._update_temperature();
    var save:Dictionary = r.to_dict();
    r.clothing = &"";
    r.restore(world, save);
    _expect("clothes are saved", r.clothing == &"clothes_fine" and r.clothing_hours > 0.0);
    # the Artisan makes clothes from stored wool and leather; citizens put them on
    for x in world.pawns:
        x.clothing = &"";
    world.town_hall.store(&"wool", 9);
    world.town_hall.store(&"leather", 4);
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
    var worn:int = 0;
    for p in world.pawns:
        if p.clothing != &"":
            worn += 1;
    if worn >= 3 or hours > 80.0:
        _expect("clothes were made and put on (%d wearing, %.1f h)" % [worn, hours], worn >= 3);
        print("TAILOR %s" % ("PASS" if _fails == 0 else "FAIL"));
        get_tree().quit(1 if _fails > 0 else 0);
        _phase = 2;

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
