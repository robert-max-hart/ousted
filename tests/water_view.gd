# ----------------------------------------------------------------
# Water overlay
#     The reach map: zero on open water, about the straight-line distance
#     elsewhere, zero at a finished well, and the view toggles on Terrain.
#     godot --headless --path . --fixed-fps 60 res://tests/water_view.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    var reach:PackedFloat32Array = world.water_reach();
    var wet:Vector2i = Vector2i(-1, -1);
    for z in range(5, Terrain.SIZE - 5):
        for x in range(5, Terrain.SIZE - 5):
            if wet.x < 0 and world.terrain.cell_height(Vector2i(x, z)) < Terrain.WATER_LEVEL:
                wet = Vector2i(x, z);
    _expect("open water is at distance 0", wet.x >= 0 and reach[world.idx(wet)] == 0.0);
    var side:Vector2i = wet + Vector2i(5, 0);
    var truth:float = 999.0;
    for z in range(side.y - 14, side.y + 15):
        for x in range(side.x - 14, side.x + 15):
            var c:Vector2i = Vector2i(x, z);
            if world.terrain.in_bounds(c) and world.terrain.cell_height(c) < Terrain.WATER_LEVEL:
                truth = minf(truth, Vector2(c - side).length());
    var got:float = reach[world.idx(side)];
    _expect("the distance is close to the true one (%.1f against %.1f)" % [got, truth], absf(got - truth) <= truth * 0.1 + 0.01);
    var hall:Vector2i = Vector2i(world.town_hall.center_cell());
    _expect("the Town Hall is a water source (%s)" % reach[world.idx(hall)], reach[world.idx(hall)] == 0.0);
    var well:Building = world.place_building(&"well", TestSite.spot(world, Vector2i(2, 2), Vector2i(14, 14)), Vector2i(2, 2), true);
    var wc:Vector2i = Vector2i(well.center_cell());
    _expect("a new well changes the map (%s)" % world.water_reach()[world.idx(wc)], world.water_reach()[world.idx(wc)] == 0.0);
    world.remove_building(well, false);
    _expect("and so does losing it", world.water_reach()[world.idx(wc)] > 0.0 or world.terrain.is_water(wc));
    world.terrain.set_water_view(true);
    _expect("the overlay colours dry ground by it", world.terrain.water_view and Terrain.water_color(3.0) != Terrain.water_color(30.0));
    print("WATER VIEW %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
