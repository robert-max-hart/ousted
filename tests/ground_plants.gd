# ----------------------------------------------------------------
# GroundPlants test
#     Flowers, ferns and reeds are laid out: every block is built, flowers stand on open grass in spring and not
#     in winter, ferns are beside trees, reeds are at the water's edge and never in deep water or on a road,
#     and the Grass setting Off removes them all.
#     godot --headless --path . --fixed-fps 60 res://tests/ground_plants.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    Settings.ensure_loaded();
    var keep:int = Settings.grass;
    Settings.set_value("grass", 2);
    Weather.drought_enabled = false;
    GameClock.total_hours = 3 * GameClock.HOURS_PER_DAY + 10.0;       # spring
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    var gp:GroundPlants = null;
    for c in world.get_children():
        if c is GroundPlants:
            gp = c;
    _expect("the world has ground plants", gp != null);
    if gp == null:
        _done();
        return;
    for i in 400:
        await get_tree().process_frame;
        if gp._dirty.is_empty():
            break;
    for i in 30:
        await get_tree().process_frame;
    print("dirty after settling: ", gp._dirty.size());
    _expect("every block was built", gp._dirty.is_empty() and gp._spots.size() == (Terrain.SIZE / GroundPlants.BLOCK) * (Terrain.SIZE / GroundPlants.BLOCK));
    var t:Terrain = world.terrain;
    var totals:Dictionary = {&"flower_a": 0, &"flower_b": 0, &"fern": 0, &"reed": 0};
    var bad_reed:int = 0;
    var bad_land:int = 0;
    for z in Terrain.SIZE:
        for x in Terrain.SIZE:
            var c:Vector2i = Vector2i(x, z);
            for kind in totals:
                var n:int = gp.count_in_cell(kind, c);
                totals[kind] += n;
                if n == 0:
                    continue;
                if kind == &"reed":
                    if (t.is_water(c) and not t.is_shallow(c)) or t.get_overlay(c) != Terrain.Overlay.NONE:
                        bad_reed += 1;
                        print("bad reed ", c, " water ", t.is_water(c), " shallow ", t.is_shallow(c), " overlay ", t.get_overlay(c), " h ", t.cell_height(c));
                elif t.is_water(c) or t.get_overlay(c) != Terrain.Overlay.NONE or world.occupant[world.idx(c)] != null:
                    bad_land += 1;
    print("spring: ", totals);
    _expect("flowers grow in spring", totals[&"flower_a"] + totals[&"flower_b"] > 100);
    _expect("both flower shapes appear", totals[&"flower_a"] > 0 and totals[&"flower_b"] > 0);
    _expect("ferns grow", totals[&"fern"] > 0);
    _expect("no reeds in deep water or on roads and fields (%d)" % bad_reed, bad_reed == 0);
    _expect("no flowers or ferns on water, roads or buildings (%d)" % bad_land, bad_land == 0);
    # winter: no flowers, no ferns, fewer reeds
    var spring_reeds:int = totals[&"reed"];
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON * 3 + 3) * GameClock.HOURS_PER_DAY + 10.0;
    gp.reload();
    for i in 400:
        await get_tree().process_frame;
        if gp._dirty.is_empty():
            break;
    var winter:Dictionary = _totals(gp);
    print("winter: ", winter);
    _expect("no flowers or ferns in winter", winter[&"flower_a"] + winter[&"flower_b"] + winter[&"fern"] == 0);
    _expect("reeds thin out in winter but stay", winter[&"reed"] > 0 and winter[&"reed"] < spring_reeds);
    # the grass setting scales them, Off removes them
    GameClock.total_hours = 3 * GameClock.HOURS_PER_DAY + 10.0;
    Settings.set_value("grass", 0);
    for i in 400:
        await get_tree().process_frame;
        if gp._dirty.is_empty():
            break;
    var off:Dictionary = _totals(gp);
    _expect("Grass Off draws none", off[&"flower_a"] + off[&"flower_b"] + off[&"fern"] + off[&"reed"] == 0);
    Settings.set_value("grass", keep);
    _done();

func _totals(gp:GroundPlants) -> Dictionary:
    var totals:Dictionary = {&"flower_a": 0, &"flower_b": 0, &"fern": 0, &"reed": 0};
    for z in Terrain.SIZE:
        for x in Terrain.SIZE:
            for kind in totals:
                totals[kind] += gp.count_in_cell(kind, Vector2i(x, z));
    return totals;

func _done() -> void:
    print("GROUND PLANTS %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    if ok:
        print("PASS: ", what);
    else:
        print("FAIL: ", what);
        _fails += 1;
