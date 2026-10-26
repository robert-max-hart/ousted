# ----------------------------------------------------------------
# Roads, field sites and effect speed test
#     A road through a tree marks it and finishes when it is cleared,
#     a bush is uprooted, a field being built shows as a site and
#     turns tilled when done, a field tool's default is one square,
#     and rain and smoke follow the game speed.
#     godot --headless --path . --fixed-fps 60 res://tests/roads_fields.tscn
# ----------------------------------------------------------------
extends Node;

var world:World;
var _frame:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    var o:Vector2i = world.town_hall.origin + Vector2i(-14, -14);
    for dz in range(-20, 20):       # a dry, free strip of five cells (the world is random)
        var ok:bool = true;
        for i in 5:
            ok = ok and world.can_plan_road(world.town_hall.origin + Vector2i(-14 + i, dz));
        if ok:
            o = world.town_hall.origin + Vector2i(-14, dz);
            break;
    var cells:Array[Vector2i] = [];
    for i in 5:
        var c:Vector2i = o + Vector2i(i, 0);
        if world.node_at[world.idx(c)] != null:
            world.remove_node(world.node_at[world.idx(c)]);
        cells.append(c);
    var tree:ResourceNode = world.add_node(&"tree", cells[1]);
    var bush:ResourceNode = world.add_node(&"bush", cells[3]);
    for c in cells:
        world.plan_road(c);
    _expect("the tree is marked for clearing", tree.designated and world.pending_roads.has(cells[1]));
    _expect("no road under the tree yet", world.terrain.get_overlay(cells[1]) == Terrain.Overlay.NONE);
    _expect("the bush is marked too, not pulled up at once", not bush.removed and bush.clearing and world.pending_roads.has(cells[3]));
    _expect("open cells got road", world.terrain.get_overlay(cells[0]) == Terrain.Overlay.ROAD);
    var saved:Dictionary = world.serialize();
    _expect("pending roads are saved", (saved["pending_roads"] as Array).has(cells[1]));
    world.remove_node(tree);
    world.remove_node(bush);
    _expect("clearing finishes the road", world.terrain.get_overlay(cells[1]) == Terrain.Overlay.ROAD and world.terrain.get_overlay(cells[3]) == Terrain.Overlay.ROAD and world.pending_roads.is_empty());

    var f:Building = world.place_building(&"field", world.town_hall.origin + Vector2i(14, 8), Vector2i(3, 3));
    _expect("a field being built is a site", world.terrain.get_overlay(f.origin) == Terrain.Overlay.SITE);
    f.complete();
    _expect("a finished field is tilled", world.terrain.get_overlay(f.origin) == Terrain.Overlay.TILLED);
    var g:Building = world.place_building(&"field", world.town_hall.origin + Vector2i(14, 14), Vector2i(2, 2));
    world.remove_building(g, true);
    _expect("removing a site clears the ground", world.terrain.get_overlay(g.origin) == Terrain.Overlay.NONE);

    world.tools.set_mode(PlayerTools.Mode.BUILD, &"field");
    _expect("the field tool starts at 2x2", world.tools.build_size == Vector2i(2, 2));
    world.tools.set_mode(PlayerTools.Mode.BUILD, &"graveyard");
    _expect("so does the graveyard tool", world.tools.build_size == Vector2i(2, 2));
    world.tools.set_mode(PlayerTools.Mode.SELECT);

    var house:Building = world.place_building(&"house", world.town_hall.origin + Vector2i(-8, 6), Vector2i(3, 3), true);
    house.settings["heating"] = true;
    house.residents.append(world.pawns[0]);
    house.add_fuel(&"firewood", 10);
    Weather.temperature = 2.0;
    GameClock.set_speed(0);

func _process(_delta:float) -> void:
    _frame += 1;
    if _frame == 5:
        _expect("rain is still when paused", world.visuals._rain.speed_scale == 0.0);
        GameClock.set_speed(3);
    elif _frame == 10:
        _expect("rain runs at game speed", is_equal_approx(world.visuals._rain.speed_scale, GameClock.speed()));
        var smoking:int = 0;
        for b in world.buildings:
            if b._smoke != null and b.is_burning():
                b.update_smoke();
                smoking += 1 if is_equal_approx(b._smoke.speed_scale, GameClock.speed()) else 0;
        _expect("smoke follows game speed", smoking > 0);
        GameClock.set_speed(0);
    elif _frame == 12:
        for b in world.buildings:
            if b._smoke != null:
                _expect("smoke is still when paused", b._smoke.speed_scale == 0.0);
                break;
        get_tree().quit();

func _expect(what:String, ok:bool) -> void:
    print(("PASS " if ok else "FAIL ") + what);
