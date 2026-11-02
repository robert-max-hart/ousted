# ----------------------------------------------------------------
# Root cellar
#     Food-only store that keeps food far longer than the open and
#     better than a granary in summer, with a ground temperature that
#     is never warmer than the air (so it is never worse than outside).
#     godot --headless --path . --fixed-fps 60 res://tests/root_cellar.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;

func _spoiled(b:Building, temp:float) -> int:
    b.stored = {&"potato": 100};
    b._spoil_acc = {};
    Weather.temperature = temp;
    var lost:int = 0;
    for i in range(24 * 8):
        lost += b.spoil_tick(1.0);
        b.stored[&"potato"] = 100;
    return lost;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    Weather.drought_enabled = false;
    GameRules.reset();
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    _expect("in the Storage menu", (Defs.BUILD_CATEGORIES[1][1] as Array).has(&"root_cellar") and Defs.BUILD_MENU.has(&"root_cellar"));
    var a:Vector2i = TestSite.spot(world, Vector2i(3, 3), Vector2i(-8, 8));
    var c:Building = world.place_building(&"root_cellar", a, Vector2i(3, 3), true);
    var g_at:Vector2i = TestSite.spot(world, Vector2i(3, 3), Vector2i(8, 8));
    var g:Building = world.place_building(&"granary", g_at, Vector2i(3, 3), true);
    _expect("both built", c != null and g != null and c.is_complete() and g.is_complete());
    _expect("food only, holds less than a granary", c.def.get("food_only", false) and c.capacity() < g.capacity() and c.accepts(&"potato") and not c.accepts(&"wood"));
    _expect("it is the preferred home for food", c.storage_rank(&"potato") < g.storage_rank(&"potato"));
    var cs:int = _spoiled(c, 28.0);
    var gs:int = _spoiled(g, 28.0);
    _expect("in summer the cellar loses far less (%d against %d)" % [cs, gs], cs * 2 < gs);
    var cw:int = _spoiled(c, -5.0);
    var gw:int = _spoiled(g, -5.0);
    _expect("in deep winter it is never worse than the frozen granary (%d against %d)" % [cw, gw], cw <= gw + 1);
    _expect("it is never warmer than the air (%.1f C)" % c.storage_temp(), c.storage_temp() <= Weather.temperature + 0.001);
    Weather.temperature = 20.0;
    _expect("in summer it stays cool (%.1f C)" % c.storage_temp(), c.storage_temp() > 9.0 and c.storage_temp() < 15.0);
    _expect("a granary follows the air", is_equal_approx(g.storage_temp(), Weather.temperature));
    _expect("the help says so", c.help_text().contains("much longer"));
    print("ROOT_CELLAR %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
