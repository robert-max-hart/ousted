# ----------------------------------------------------------------
# Fill bars
#     A store shows a bar of how full it is while it is selected or the
#     top bar's Stores toggle is on, and only then; the bar's colour goes
#     green, yellow, red; buildings with no store never get one.
#     godot --headless --path . --fixed-fps 60 res://tests/fill_bars.tscn
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
    await get_tree().process_frame;
    var o:Vector2i = TestSite.spot(world, Vector2i(4, 4), Vector2i(-12, 8));
    var yard:Building = world.place_building(&"stockpile", o, Vector2i(4, 4), true);
    var o2:Vector2i = TestSite.spot(world, Vector2i(3, 3), Vector2i(12, 8));
    var well:Building = world.place_building(&"well", o2, Defs.BUILDINGS[&"well"]["size"], true);
    var bars:FillBars = world.fill_bars;
    _expect("the world has the manager", bars != null and not bars.show_all);
    bars.update_for(yard, false);
    _expect("no bar to start with", yard.fill_bar == null or not yard.fill_bar.visible);
    yard.store(&"wood", yard.capacity() / 4);
    bars.update_for(yard, true);
    _expect("a bar appears over a store", yard.fill_bar != null and yard.fill_bar.visible and yard.fill_bar.is_inside_tree());
    bars._process(1.0);
    _expect("an unselected store with the toggle off has none", not yard.fill_bar.visible);
    world.tools.select(yard);
    bars._process(1.0);
    _expect("the selected store shows its bar", yard.fill_bar.visible);
    world.tools.select(null);
    bars._process(1.0);
    _expect("and hides it when deselected", not yard.fill_bar.visible);
    bars.show_all = true;
    bars._process(1.0);
    _expect("the toggle shows every store's bar, the Town Hall's too", yard.fill_bar.visible and world.town_hall.fill_bar != null and world.town_hall.fill_bar.visible);
    _expect("a well has no store and no bar", well.fill_bar == null);
    bars.show_all = false;
    bars._process(1.0);
    _expect("switching it off hides them", not yard.fill_bar.visible and not world.town_hall.fill_bar.visible);
    _expect("green under 70%", FillBar.color_for(0.5).g > FillBar.color_for(0.5).r);
    _expect("yellow from 70%", FillBar.color_for(0.75).r > 0.9 and FillBar.color_for(0.75).g > 0.7);
    _expect("red from 90%", FillBar.color_for(0.95).r > 0.8 and FillBar.color_for(0.95).g < 0.4);
    yard.store(&"wood", yard.capacity());
    bars.update_for(yard, true);
    var f:float = float(yard.used()) / yard.capacity();
    _expect("a full store is full (%.2f)" % f, f >= 0.99 and yard.fill_bar._mat.get_shader_parameter("fill") >= 0.99);
    print("FILL_BARS %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
