# ----------------------------------------------------------------
# Bridges and fords (rivers)
#     The map has a river with fords; a bridge can be placed across deep
#     water (and only across water), carries walkers over it, and shallow
#     water can be waded but deep water cannot.
#     godot --headless --path . --fixed-fps 60 res://tests/bridge.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;

func _ready() -> void:
    await _run();

func _run() -> void:
    SaveGame.autosave_enabled = false;
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    var t:Terrain = world.terrain;
    _expect("the map has a river with fords", t.river_path.size() > 20 and t.river_fords.size() == Terrain.FORDS);
    _expect("the start is by the river, not on it (%.1f cells)" % t.river_distance(world.town_hall.origin), t.river_distance(world.town_hall.origin) > 6.0 and t.river_distance(world.town_hall.origin) < 30.0);
    # a ford's middle can be waded: shallow, walkable, but slower
    var wadeable:int = 0;
    for f in t.river_fords:
        var fc:Vector2i = Vector2i(f);
        if t.is_water(fc) and t.is_shallow(fc) and world.nav.is_walkable(fc):
            wadeable += 1;
    _expect("at least one ford's middle is shallow water that can be waded (%d of %d)" % [wadeable, t.river_fords.size()], wadeable >= 1);
    # deep water: find a row crossing it with land at both ends
    var run:Array = _deep_run(t);
    _expect("found deep water to bridge %s" % [run], not run.is_empty());
    if run.is_empty():
        _finish();
        return;
    var flip:bool = run[3];
    var z:int = run[0];
    var x0:int = run[1];
    var x1:int = run[2];
    var mid:Vector2i = _cell(flip, (x0 + x1) / 2, z);
    _expect("deep water is not walkable", not world.nav.is_walkable(mid));
    var rect:Rect2i = Rect2i(_cell(flip, x0 - 1, z), Vector2i(x1 - x0 + 3, 2) if not flip else Vector2i(2, x1 - x0 + 3));
    _expect("an ordinary building cannot go on water", world.can_place(&"house", mid, Vector2i(3, 3)) == "Can't build on water");
    var why:String = world.can_place(&"bridge", rect.position, rect.size);
    _expect("a bridge across the water is allowed (%s)" % why, why == "");
    var b:Building = world.place_building(&"bridge", rect.position, rect.size, true);
    _expect("the deck is walkable", world.nav.is_walkable(mid) and world.is_bridge(mid));
    _expect("citizens stand on the deck, above the water (%.2f)" % world.stand_y(mid.x + 0.5, mid.y + 0.5), absf(world.stand_y(mid.x + 0.5, mid.y + 0.5) - Building.DECK_HEIGHT) < 0.01);
    var path:Array[Vector2i] = world.nav.find_path(_cell(flip, x0, z), _cell(flip, x1, z));
    _expect("there is a path from bank to bank (%d steps)" % path.size(), path.size() >= x1 - x0 + 1);
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0:          # windowed: a picture of the bridge, from above and from the side
        world.hud.visible = false;
        world.camera_rig.focus_on(Vector3(mid.x, 0.0, mid.y));
        world.camera_rig._distance = 30.0;
        world.camera_rig._target_distance = 30.0;
        for i in 12:
            await get_tree().process_frame;
        get_viewport().get_texture().get_image().save_png(args[0].path_join("bridge.png"));
    world.remove_building(b, false);
    _expect("without the bridge the water blocks again", not world.nav.is_walkable(mid));
    _finish();

func _cell(flip:bool, x:int, z:int) -> Vector2i:
    return Vector2i(z, x) if flip else Vector2i(x, z);

# A line z and the run of water x0..x1 along it (3 to 14 cells) with dry land at both ends, in this row and the next
# one, and none of it shallow; flip swaps the axes, for a river that runs along the first one. Returns [z, x0, x1, flip].
func _deep_run(t:Terrain) -> Array:
    for flip in [false, true]:
        for z in range(10, Terrain.SIZE - 12):
            var x:int = 10;
            while x < Terrain.SIZE - 12:
                if not t.is_water(_cell(flip, x, z)) and t.is_water(_cell(flip, x + 1, z)):
                    var e:int = x + 1;
                    while e < Terrain.SIZE - 10 and t.is_water(_cell(flip, e, z)):
                        e += 1;
                    var dry:bool = not t.is_water(_cell(flip, x, z + 1)) and not t.is_water(_cell(flip, e, z + 1)) and not t.is_water(_cell(flip, e, z));
                    var run:int = e - x - 1;
                    var flat:bool = t.cell_slope(_cell(flip, x, z)) < 1.5 and t.cell_slope(_cell(flip, e, z)) < 1.5;
                    if run >= 3 and run <= 14 and dry and flat and not t.is_shallow(_cell(flip, (x + 1 + e - 1) / 2, z)):
                        return [z, x + 1, e - 1, flip];
                    x = e;
                else:
                    x += 1;
    return [];

func _finish() -> void:
    print("BRIDGE %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
