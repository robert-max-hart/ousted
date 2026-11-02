# ----------------------------------------------------------------
# Spoilage probe (not part of the suite)
#     How much of a food is left after a season in each kind of store, for a season starting in spring,
#     summer, autumn and winter, per climate. Uses the real temperature curve (day and night, no weather
#     spells), Defs.spoil_temp_factor and the stores' own definitions (spoil_mult, spoil_groups, ground_temp).
#     Pass a climate id after -- (0 temperate, 1 arctic, 2 desert, 3 tropical; default all).
#     godot --headless --path . res://tests/spoil_probe.tscn -- 0
# ----------------------------------------------------------------
extends Node;

var STORES:Array = [["open", {}], ["granary", Defs.BUILDINGS[&"granary"]], ["cellar", Defs.BUILDINGS[&"root_cellar"]]];       # name, the store's definition

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    var args:PackedStringArray = OS.get_cmdline_user_args();
    var ids:Array = [0, 1, 2, 3];
    if args.size() > 0:
        ids = [args[0].to_int()];
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    await get_tree().process_frame;
    Weather.drought_enabled = false;
    Weather.drought_days = 0;
    Weather.snap_days = 0;
    Weather.intensity = 0.0;
    Weather._day_offset = 0.0;
    var foods:Array = [];
    for item in Defs.ITEMS:
        if Defs.is_food(item) and Defs.ITEMS[item].get("spoil_days", 0.0) > 0.0:
            foods.append(item);
    foods.sort_custom(func(a:StringName, b:StringName) -> bool: return Defs.ITEMS[a]["spoil_days"] < Defs.ITEMS[b]["spoil_days"]);
    for id in ids:
        Climate.current = id;
        print("== climate %d (%s): share of a food left after 32 days, starting in spring / summer / autumn / winter" % [id, Climate.data().get("name", "?")]);
        print("%-14s days | %s" % ["", " | ".join(STORES.map(func(s:Array) -> String: return "%-15s" % s[0]))]);
        for item in foods:
            var row:PackedStringArray = [];
            for st in STORES:
                var cells:PackedStringArray = [];
                for season in 4:
                    cells.append("%3d" % roundi(100.0 * _left(item, season, st) ));
                row.append("%-15s" % " ".join(cells));
            print("%-14s %4d | %s" % [item, int(Defs.ITEMS[item]["spoil_days"]), " | ".join(row)]);
    get_tree().quit();

func _left(item:StringName, season:int, st:Array) -> float:
    var rate:float = Defs.spoil_per_hour(item);
    var left:float = 1.0;
    var start:float = float(season * GameClock.DAYS_PER_SEASON) * GameClock.HOURS_PER_DAY;
    for h in GameClock.DAYS_PER_SEASON * int(GameClock.HOURS_PER_DAY):
        GameClock.total_hours = start + h;
        Weather._update_temperature();
        var t:float = Defs.store_temp(st[1], Weather.temperature);
        left *= 1.0 - minf(1.0, rate * Defs.spoil_temp_factor(t) * Defs.store_spoil_mult(st[1], item));
    return left;
