# ----------------------------------------------------------------
# Soil view
#     The terrain overlay colours ground by fertility, the selected
#     field numbers its plots, and the crop list warns on poor soil
#     and points out crops that restore it.
#     godot --headless --path . --fixed-fps 60 res://tests/soil_view.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    world.seeds.unlock_all();
    var o:Vector2i = TestSite.near(world, Vector2i(8, -10));
    for off in [Vector2i(8, -10), Vector2i(-14, -10), Vector2i(8, 10), Vector2i(-14, 10), Vector2i(0, -16), Vector2i(0, 16)]:       # dry land, not the shore
        var cand:Vector2i = world.town_hall.origin + off;
        if world.terrain.in_bounds(cand + Vector2i(8, 8)) and world.terrain.cell_height(cand + Vector2i(2, 2)) > Terrain.WATER_LEVEL + 1.5 and world.terrain.cell_height(cand) > Terrain.WATER_LEVEL + 1.5 and world.terrain.cell_height(cand + Vector2i(8, 8)) > Terrain.WATER_LEVEL + 1.5:
            o = cand;
            break;
    for rn in world.nodes.duplicate():
        if Rect2i(o - Vector2i(3, 3), Vector2i(16, 12)).has_point(rn.cell):
            world.remove_node(rn);
    world.terrain.flatten_rect(Rect2i(o - Vector2i(2, 2), Vector2i(18, 14)));
    var f:Field = world.place_building(&"field", o, Vector2i(4, 4), true) as Field;
    for i in f.plot_count():
        world.soil_fertility[world.terrain.index(f.plot_cell(i))] = 0.2;
    var off:Color = world.terrain._cell_color(o);
    world.terrain.set_soil_view(true);
    var poor:Color = world.terrain._cell_color(o);
    world.soil_fertility[world.terrain.index(o)] = 0.9;
    var rich:Color = world.terrain._cell_color(o);
    _expect("the overlay changes the ground colour", not poor.is_equal_approx(off));
    _expect("rich soil looks greener than poor (%s vs %s)" % [rich, poor], rich.g > rich.r and poor.r > poor.g);
    f.show_soil_numbers(true);
    var shown:int = f._soil_labels.filter(func(l:Label3D) -> bool: return l.visible).size();
    _expect("every plot has a number (%d)" % shown, shown == f.plot_count());
    _expect("the first reads 90 and the second 20", f._soil_labels[0].text == "90" and f._soil_labels[1].text == "20");
    f.show_soil_numbers(false);
    _expect("numbers hide again", f._soil_labels.all(func(l:Label3D) -> bool: return not l.visible));
    world.tools.select(f);
    world.hud._on_info_button();
    var texts:Array[String] = [];
    for b in world.hud._crop_list.get_children():
        texts.append((b as Button).text);
    var wheat:String = texts.filter(func(t:String) -> bool: return t.begins_with("! Wheat") or t.begins_with("Wheat"))[0];
    var beans:String = texts.filter(func(t:String) -> bool: return t.begins_with("Beans"))[0];
    _expect("wheat is flagged on poor soil ('%s')" % wheat, wheat.begins_with("! "));
    _expect("beans are pointed out as restoring ('%s')" % beans, beans.ends_with("(restores soil)"));
    print("SOIL VIEW %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
