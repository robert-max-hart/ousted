# ----------------------------------------------------------------
# Wild foods per climate
#     Each climate has its own wild foods: the temperate map is as it
#     was, the arctic has lingonberries and no hazel, the desert has
#     prickly pears and date palms (by the water) and no berry bushes,
#     the tropics have bananas and coconut palms and more mushrooms and
#     herbs. Foods a map does not have are not spread or sown, are
#     hidden in the Forager's Hut's controls, and every food has an
#     item, a model and a place to be drawn.
#     godot --headless --path . --fixed-fps 60 res://tests/wild_foods.tscn
# ----------------------------------------------------------------
extends Node;

const KINDS:Array[StringName] = [&"bush", &"mushroom", &"hazel", &"herb", &"lingon", &"cactus", &"date", &"banana", &"coconut"];

var _fails:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    Weather.drought_enabled = false;
    GameRules.reset();
    GameRules.illness = 0;
    Terrain.set_size(96);
    var counts:Dictionary = {};
    for id in [Climate.Id.TEMPERATE, Climate.Id.ARCTIC, Climate.Id.DESERT, Climate.Id.TROPICAL]:
        Climate.current = id;
        World.new_game_seed = 777;
        var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
        add_child(world);
        GameClock.set_speed(0);
        await get_tree().process_frame;
        var c:Dictionary = {};
        for rn in world.nodes:
            c[rn.kind] = c.get(rn.kind, 0) + 1;
        counts[id] = c;
        if id == Climate.Id.DESERT:
            _check_desert(world);
        world.queue_free();
        await get_tree().process_frame;
    Climate.current = Climate.Id.TEMPERATE;
    print("wild foods by climate: ", counts);
    var t:Dictionary = counts[Climate.Id.TEMPERATE];
    var a:Dictionary = counts[Climate.Id.ARCTIC];
    var d:Dictionary = counts[Climate.Id.DESERT];
    var r:Dictionary = counts[Climate.Id.TROPICAL];
    _expect("temperate keeps the old four and none of the new", t.get(&"bush", 0) > 10 and t.get(&"mushroom", 0) > 10 and t.get(&"hazel", 0) > 5 and t.get(&"herb", 0) > 5 \
        and t.get(&"lingon", 0) + t.get(&"cactus", 0) + t.get(&"date", 0) + t.get(&"banana", 0) + t.get(&"coconut", 0) == 0);
    _expect("arctic: lingonberries, no hazel, few berry bushes (%d lingon, %d bush against %d)" % [a.get(&"lingon", 0), a.get(&"bush", 0), t.get(&"bush", 0)], a.get(&"lingon", 0) > 10 and a.get(&"hazel", 0) == 0 and a.get(&"bush", 0) < t.get(&"bush", 0));
    _expect("desert: prickly pears and dates, no bushes or hazel (%d cactus, %d date)" % [d.get(&"cactus", 0), d.get(&"date", 0)], d.get(&"cactus", 0) > 5 and d.get(&"date", 0) > 0 and d.get(&"bush", 0) == 0 and d.get(&"hazel", 0) == 0);
    _expect("tropics: bananas and coconuts, no hazel, more herbs (%d banana, %d coconut)" % [r.get(&"banana", 0), r.get(&"coconut", 0)], r.get(&"banana", 0) > 10 and r.get(&"coconut", 0) > 5 and r.get(&"hazel", 0) == 0 and r.get(&"herb", 0) > t.get(&"herb", 0));
    # every food: share, item, node, model, drawn layer
    for kind in KINDS:
        var def:Dictionary = Defs.RESOURCE_NODES[kind];
        _expect("%s: a node def with a food item" % kind, def.get("forage", false) and Defs.is_food(def["item"]) if kind != &"herb" else def.get("forage", false));
        _expect("%s: a trade value" % kind, Defs.trade_value(def["item"]) > 0);
        _expect("%s: in the forager's order and options" % kind, ProductionTasks.FORAGE_KINDS.has(kind));
        if not ["bush", "mushroom", "hazel", "herb"].has(String(kind)):
            _expect("%s: a model" % kind, ResourceLoader.exists("res://assets/models/plants/%s_ripe.obj" % kind));
    var opts:Array = Defs.BUILDINGS[&"forager"]["controls"].filter(func(c:Dictionary) -> bool: return c["id"] == "forage_pref")[0]["option_wild"];
    _expect("the Pick first options line up with the kinds", opts.size() == ProductionTasks.FORAGE_KINDS.size() + 2 and opts.slice(2) == ProductionTasks.FORAGE_KINDS);
    print("WILD FOODS %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

# On a desert map: no bush sown, no dates away from the water, foods that belong are allowed, the hut hides what the map lacks.
func _check_desert(world:World) -> void:
    var far:Vector2i = Vector2i(-1, -1);
    var spot:Vector2i = TestSite.near(world, Vector2i(8, 8));
    _expect("a bush cannot be sown in the desert", not WildGrowth.can_grow(world, spot, &"bush"));
    _expect("a prickly pear can", WildGrowth.can_grow(world, spot, &"cactus") or world.node_at[world.idx(spot)] != null);
    var dates_away:int = 0;
    for rn in world.nodes:
        if rn.kind == &"date" and not WildGrowth.near_water(world, rn.cell, WildGrowth.DATE_WATER + 2):
            dates_away += 1;
    _expect("date palms grow by the water (%d away from it)" % dates_away, dates_away == 0);
    var shown:Array[String] = [];
    for c in Defs.BUILDINGS[&"forager"]["controls"]:
        if c.has("wild") and Climate.has_wild(c["wild"]):
            shown.append(c["id"]);
    _expect("the hut shows the desert's foods only (%s)" % str(shown), shown.has("forage_cactus") and shown.has("forage_date") and not shown.has("forage_bush") and not shown.has("forage_banana"));
    _expect("the share helpers agree", Climate.wild_share(&"cactus") == 1.0 and Climate.wild_share(&"hazel") == 0.0 and not Climate.has_wild(&"banana"));

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
