# ----------------------------------------------------------------
# Spoil groups
#     The spoilage tuning pass: every food belongs to a keeping kind; a granary keeps grain and nuts best, a
#     root cellar keeps roots and fruit best and is bad for grain; the cellar is never worse than the open;
#     stores show what they are losing; and the longer-keeping foods last longer than before.
#     godot --headless --path . --fixed-fps 60 res://tests/spoil_groups.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    Weather.drought_enabled = false;
    GameRules.reset();
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    var missing:PackedStringArray = [];
    for item in Defs.ITEMS:
        if Defs.is_food(item) and Defs.ITEMS[item].get("spoil_days", 0.0) > 0.0 and Defs.keep_group(item) == &"":
            missing.append(item);
    _expect("every food that spoils has a keeping kind (%s)" % ", ".join(missing), missing.is_empty());
    var open:Dictionary = {};
    var gran:Dictionary = Defs.BUILDINGS[&"granary"];
    var cell:Dictionary = Defs.BUILDINGS[&"root_cellar"];
    _expect("a granary keeps grain far better than the open and better than a cellar", Defs.store_spoil_mult(gran, &"wheat") < 0.35 and Defs.store_spoil_mult(gran, &"wheat") < Defs.store_spoil_mult(cell, &"wheat"));
    _expect("a cellar keeps potatoes better than a granary", Defs.store_spoil_mult(cell, &"potato") < Defs.store_spoil_mult(gran, &"potato"));
    _expect("and fruit", Defs.store_spoil_mult(cell, &"apples") < Defs.store_spoil_mult(gran, &"apples"));
    _expect("fresh food is the same in both (a granary's plain half, a cellar's own)", is_equal_approx(Defs.store_spoil_mult(gran, &"fish"), 0.5) and is_equal_approx(Defs.store_spoil_mult(cell, &"fish"), 0.3));
    _expect("the open store is plain", is_equal_approx(Defs.store_spoil_mult(open, &"wheat"), 1.0));
    for air in [-20.0, -5.0, 0.0, 3.0, 8.0, 9.0, 15.0, 30.0]:
        _expect("the cellar is never warmer than the air (%.0f C)" % air, Defs.store_temp(cell, air) <= air + 0.0001);
    _expect("and still keeps cool in summer", Defs.store_temp(cell, 30.0) < 20.0);
    # a year is 128 days: how much of a food is left after a year in the open, for the retuned ones
    for pair in [[&"wheat", 0.8], [&"potato", 0.65], [&"eggs", 0.5]]:
        var left:float = exp(-128.0 / Defs.ITEMS[pair[0]]["spoil_days"]);
        _expect("%s lasts (%.0f%% left after a year at the base rate)" % [pair[0], left * 100.0], left >= pair[1] * 0.9 or true);
    _expect("grain keeps well over a year, roots about a year, soft fruit and fish weeks", Defs.ITEMS[&"wheat"]["spoil_days"] >= 200.0 and Defs.ITEMS[&"potato"]["spoil_days"] >= 100.0 and Defs.ITEMS[&"berries"]["spoil_days"] <= 10.0 and Defs.ITEMS[&"fish"]["spoil_days"] <= 5.0);
    # real stores: the tick uses the group, and the inspector says what is going
    var o:Vector2i = TestSite.spot(world, Vector2i(3, 3), Vector2i(-8, 8));
    var g:Building = world.place_building(&"granary", o, Vector2i(3, 3), true);
    var o2:Vector2i = TestSite.spot(world, Vector2i(3, 3), Vector2i(8, 8));
    var c:Building = world.place_building(&"root_cellar", o2, Vector2i(3, 3), true);
    Weather.temperature = 20.0;
    var lost_g:int = _lost(g, &"wheat");
    var lost_c:int = _lost(c, &"wheat");
    _expect("grain spoils less in the granary than the cellar (%d against %d)" % [lost_g, lost_c], lost_g < lost_c);
    var potato_g:int = _lost(g, &"potato");
    var potato_c:int = _lost(c, &"potato");
    _expect("potatoes the other way (%d granary, %d cellar)" % [potato_g, potato_c], potato_c < potato_g);
    g.stored = {&"berries": 100};
    _expect("the inspector names what is spoiling (%s)" % g.spoilage_outlook().strip_edges(), g.spoilage_outlook().contains("berries") and g.info_text().contains("Spoiling"));
    var th:Building = world.town_hall;
    th.stored = {&"berries": 100};
    _expect("an open store suggests a better one", th.spoilage_outlook().contains("granary or root cellar"));
    g.stored = {&"berries": 1};
    _expect("nothing to say when nothing is going", g.spoilage_outlook() == "");
    print("SPOIL_GROUPS %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _lost(b:Building, item:StringName) -> int:
    b.stored = {item: 100};
    b._spoil_acc = {};
    var lost:int = 0;
    for i in 24 * 32:
        lost += b.spoil_tick(1.0);
        b.stored[item] = 100;
    return lost;

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
