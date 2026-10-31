# ----------------------------------------------------------------
# Climates test
#     Each climate gives the temperatures and rain it promises over a
#     year, the land only goes wintry where there is a winter, woods are
#     thinner in the desert, and a saved game keeps its climate.
#     godot --headless --path . --fixed-fps 60 res://tests/climates.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Weather.drought_enabled = false;
    var stats:Dictionary = {};
    for id in Climate.DEFS:
        Climate.current = id;
        var lo:float = INF;
        var hi:float = -INF;
        var rain_hours:int = 0;
        var snow_hours:int = 0;
        var hours:int = 32 * 4 * 24;
        GameClock.total_hours = 0.0;
        Weather.reset();
        for h in hours:
            GameClock.total_hours = float(h);
            Weather._on_hour(h % 24);
            lo = minf(lo, Weather.mean_temperature());
            hi = maxf(hi, Weather.mean_temperature());
            if Weather.is_raining:
                rain_hours += 1;
                if Weather.snow_fraction() > 0.5:
                    snow_hours += 1;
        stats[id] = {"lo": lo, "hi": hi, "rain": rain_hours, "snow": snow_hours};
        print("%s: mean temperature %.1f to %.1f C, %d rain hours (%d snow) in a year" % [Climate.name_of(id), lo, hi, rain_hours, snow_hours]);
    _expect("Arctic winters are far colder than temperate ones", stats[Climate.Id.ARCTIC]["lo"] < stats[Climate.Id.TEMPERATE]["lo"] - 8.0);
    _expect("Arctic summers stay cool", stats[Climate.Id.ARCTIC]["hi"] < 18.0);
    _expect("Desert summers are hot", stats[Climate.Id.DESERT]["hi"] > 30.0);
    _expect("the tropics never get cold", stats[Climate.Id.TROPICAL]["lo"] > 18.0);
    _expect("the tropics get more rain than temperate land, the desert far less", stats[Climate.Id.TROPICAL]["rain"] > stats[Climate.Id.TEMPERATE]["rain"] and stats[Climate.Id.DESERT]["rain"] * 3 < stats[Climate.Id.TEMPERATE]["rain"]);
    _expect("no snow in the tropics or desert", stats[Climate.Id.TROPICAL]["snow"] == 0 and stats[Climate.Id.DESERT]["snow"] == 0);
    _expect("snow falls in temperate and arctic winters", stats[Climate.Id.TEMPERATE]["snow"] > 0 and stats[Climate.Id.ARCTIC]["snow"] > stats[Climate.Id.TEMPERATE]["snow"]);

    Climate.current = Climate.Id.DESERT;
    _expect("the desert has no winter look", Climate.look(GameClock.Season.WINTER) != GameClock.Season.WINTER);
    Climate.current = Climate.Id.TEMPERATE;
    _expect("temperate land does", Climate.look(GameClock.Season.WINTER) == GameClock.Season.WINTER);

    var trees:Dictionary = {};
    var data:Dictionary = {};
    for id in [Climate.Id.DESERT, Climate.Id.TEMPERATE, Climate.Id.TROPICAL]:
        Climate.current = id;
        GameClock.reset();
        Weather.reset();
        var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
        world.world_seed = 5150;
        add_child(world);
        await get_tree().process_frame;
        trees[id] = world.nodes.filter(func(n:ResourceNode) -> bool: return n.is_tree()).size();
        print("%s: %d trees" % [Climate.name_of(id), trees[id]]);
        if id == Climate.Id.DESERT:
            data = world.serialize();
        world.queue_free();
        await get_tree().process_frame;
    _expect("woods thin out in the desert and thicken in the tropics", trees[Climate.Id.DESERT] < trees[Climate.Id.TEMPERATE] and trees[Climate.Id.TEMPERATE] < trees[Climate.Id.TROPICAL]);
    Climate.current = Climate.Id.TEMPERATE;
    World.pending_load = data;
    var loaded:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(loaded);
    await get_tree().process_frame;
    _expect("a loaded game keeps its climate", Climate.current == Climate.Id.DESERT);
    Climate.current = Climate.Id.TEMPERATE;
    print("CLIMATES %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    print("%s: %s" % ["PASS" if ok else "FAIL", what]);
    if not ok:
        _fails += 1;
