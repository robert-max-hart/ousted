# ----------------------------------------------------------------
# Spirits
#     An Artisan at the Distillery turns barley, apples or pears and a
#     little firewood into spirits, but only while the colony's food
#     stock is above the level set; citizens drink spirits as a treat
#     with a bigger boost than honey.
#     godot --headless --path . --fixed-fps 60 res://tests/still.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;
var world:World;
var _still:Building;
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
    world.policies.set_on(&"treats", false);       # or citizens drink what the test is counting
    var o:Vector2i = TestSite.spot(world, Vector2i(3, 3), Vector2i(5, -7));
    for rn in world.nodes.duplicate():
        if Rect2i(o - Vector2i(3, 3), Vector2i(16, 12)).has_point(rn.cell):
            world.remove_node(rn);
    world.terrain.flatten_rect(Rect2i(o - Vector2i(2, 2), Vector2i(18, 14)));
    _still = world.place_building(&"still", o, Vector2i(3, 3), true);
    var spirits:Dictionary = Defs.ITEMS[&"spirits"];
    var honey:Dictionary = Defs.ITEMS[&"honey"];
    _expect("spirits are a treat, not a food", Defs.is_treat(&"spirits") and not Defs.is_food(&"spirits"));
    _expect("a bigger boost than honey", spirits["treat"]["mood"] > honey["treat"]["mood"]);
    _expect("they are traded", Defs.trade_value(&"spirits") >= 20);
    world.town_hall.store(&"spirits", 2);
    world.town_hall.store(&"honey", 2);
    _expect("citizens choose spirits over honey", Stock.best_treat() == &"spirits");
    world.town_hall.take(&"spirits", 2);
    world.town_hall.take(&"honey", 2);
    # recipes: three ways to one product
    var r:Dictionary = _still.def["recipes"];
    _expect("six recipes make spirits (barley and five fruits)", r.size() == 6 and r[&"spirits_barley"]["output"] == &"spirits" and r[&"spirits_apples"]["output"] == &"spirits");
    _expect("the recipes are switched on", _still.recipe_enabled(&"spirits_barley") and _still.recipe_enabled(&"spirits_apples"));
    # water
    _expect("the Distillery needs water in reach", _still.needs_water() and _still.def["needs_water"] == 12.0);
    _expect("the Town Hall (a well) is near enough", _still.has_water());
    var real:Dictionary = _still.def;
    _still.def = real.duplicate();
    _still.def["needs_water"] = 0.5;       # no water within half a cell of it
    _still._water_checked = -99.0;
    _expect("with no water in reach it cannot work or fetch", not _still.has_water() and not _still.recipe_enabled(&"spirits_barley") and _still.inputs_wanted().is_empty());
    _expect("and says so", _still.info_text().contains("Water within") and _still.info_text().contains("NO"));
    var well:Building = world.place_building(&"well", o + Vector2i(0, 4), Vector2i(2, 2), true);
    _still.def["needs_water"] = 8.0;
    _still._water_checked = -99.0;
    _expect("a well within reach gives it water", well != null and _still.has_water() and _still.recipe_enabled(&"spirits_barley"));
    _still.def = real;
    _still._water_checked = -99.0;
    # the food reserve
    var food:int = Stock.food_total();
    _still.settings["keep_food"] = food + 50;
    _expect("under the food level it does not distil or fetch grain", not _still.recipe_enabled(&"spirits_barley") and _still.inputs_wanted().is_empty());
    _still.settings["keep_food"] = 0;
    _expect("with no level it always can", _still.recipe_enabled(&"spirits_barley"));
    _still.settings["make_spirits_barley"] = false;
    _expect("a recipe can be switched off", not _still.recipe_enabled(&"spirits_barley") and not _still.inputs_wanted().has(&"barley"));
    _still.settings["make_spirits_barley"] = true;
    _still.settings["cap_spirits"] = 0;
    _expect("a cap of zero switches it all off", not _still.recipe_enabled(&"spirits_barley") and not _still.recipe_enabled(&"spirits_pears"));
    _still.settings["cap_spirits"] = 20;
    # an artisan distils from stored goods
    world.town_hall.store(&"barley", 8);
    world.town_hall.store(&"firewood", 10);
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
    if Stock.amount(&"spirits") >= 4 or hours > 80.0:
        _expect("spirits were distilled (%d, %.1f h)" % [Stock.amount(&"spirits"), hours], Stock.amount(&"spirits") >= 4);
        world.policies.set_on(&"treats", true);
        var drinker:Pawn = world.pawns[1];
        drinker.treat_until = 0.0;
        drinker.treat_ready = 1.0;
        var t:Task = world.jobs.needs.treat_task(drinker);
        _expect("with the policy on a citizen goes for the spirits", t != null and t.label.contains("spirits"));
        print("STILL %s" % ("PASS" if _fails == 0 else "FAIL"));
        get_tree().quit(1 if _fails > 0 else 0);
        _phase = 2;

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
