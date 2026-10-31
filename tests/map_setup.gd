# ----------------------------------------------------------------
# Map setup test
#     Map sizes and river styles: the terrain arrays follow the size, every
#     style makes the river it promises (None makes none, Wide the most
#     water), and a small map with another river style builds a world,
#     saves, and loads back with the same size and style.
#     godot --headless --path . --fixed-fps 60 res://tests/map_setup.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    var seeds:Array[int] = [3, 17, 256, 4242, 98765];
    for size in Terrain.MAP_SIZES:
        Terrain.set_size(size);
        var t:Terrain = Terrain.new();
        t.generate(7);
        _expect("size %d: arrays follow it" % size, t.heights.size() == (size + 1) * (size + 1) and t.overlay.size() == size * size and Terrain.CHUNKS * Terrain.CHUNK == size);
        t.free();
    Terrain.set_size(Terrain.DEFAULT_SIZE);
    var water:Dictionary = {};
    for style in Terrain.RIVER_STYLES:
        Terrain.river_style = style;
        var total:int = 0;
        var rivers:int = 0;
        for s in seeds:
            var t:Terrain = Terrain.new();
            t.generate(s);
            if not t.river_path.is_empty():
                rivers += 1;
            for z in Terrain.SIZE:
                for x in Terrain.SIZE:
                    if t.is_water(Vector2i(x, z)):
                        total += 1;
            t.free();
        water[style] = total / seeds.size();
        print("%s: %d of %d maps have a river, %d water cells on average" % [Terrain.RIVER_STYLES[style]["name"], rivers, seeds.size(), water[style]]);
        if Terrain.RIVER_STYLES[style]["land"] != &"river":
            _expect("%s makes no river" % Terrain.RIVER_STYLES[style]["name"], rivers == 0);
        else:
            _expect("%s makes a river on at least 4 of 5 maps" % Terrain.RIVER_STYLES[style]["name"], rivers >= 4);
    _expect("Wide has more water than Winding", water[Terrain.RiverStyle.WIDE] > water[Terrain.RiverStyle.WINDING]);
    _expect("None has the least water", water[Terrain.RiverStyle.NONE] < water[Terrain.RiverStyle.GENTLE]);
    _check_wetlands_and_coast(seeds);

    Terrain.set_size(96);
    Terrain.river_style = Terrain.RiverStyle.WILD;
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    await get_tree().create_timer(1.0).timeout;
    _expect("a Small world has 96 cells and citizens", Terrain.SIZE == 96 and world.pawns.size() > 0 and world.occupant.size() == 96 * 96);
    GameClock.set_speed(3);
    await get_tree().create_timer(3.0).timeout;
    GameClock.set_speed(1);
    var data:Dictionary = world.serialize();
    Terrain.set_size(160);
    Terrain.river_style = Terrain.RiverStyle.NONE;
    World.pending_load = data;
    var loaded:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(loaded);
    await get_tree().create_timer(0.5).timeout;
    _expect("loading restores the size and style", Terrain.SIZE == 96 and Terrain.river_style == Terrain.RiverStyle.WILD);
    _expect("the loaded world matches the saved one", loaded.pawns.size() == world.pawns.size() and loaded.terrain.heights == world.terrain.heights);
    loaded.queue_free();
    world.queue_free();
    Terrain.set_size(128);
    Terrain.river_style = Terrain.RiverStyle.NONE;
    var dry:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(dry);
    await get_tree().create_timer(1.0).timeout;
    GameClock.set_speed(3);
    await get_tree().create_timer(3.0).timeout;
    _expect("a Medium world with no river starts a colony", dry.town_hall != null and dry.pawns.size() > 0 and dry.terrain.river_path.is_empty());
    dry.queue_free();
    for style in [Terrain.RiverStyle.WETLANDS, Terrain.RiverStyle.COAST]:
        Terrain.set_size(128);
        Terrain.river_style = style;
        var w:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
        add_child(w);
        await get_tree().create_timer(1.0).timeout;
        GameClock.set_speed(3);
        await get_tree().create_timer(3.0).timeout;
        var th_ok:bool = w.town_hall != null and w.terrain.cell_height(w.town_hall.origin) > 0.5;
        _expect("a %s world starts a colony on dry land" % Terrain.RIVER_STYLES[style]["name"], th_ok and w.pawns.size() > 0);
        w.queue_free();
        await get_tree().process_frame;
    Terrain.set_size(Terrain.DEFAULT_SIZE);
    Terrain.river_style = Terrain.RiverStyle.WINDING;
    print("MAP SETUP %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

# Wetlands: most of the map is water and most of that wadeable, with a dry rise in the middle region.
# Coast: one edge is sea and the opposite one is land.
@warning_ignore("integer_division")
func _check_wetlands_and_coast(seeds:Array[int]) -> void:
    for s in seeds:
        Terrain.river_style = Terrain.RiverStyle.WETLANDS;
        var t:Terrain = Terrain.new();
        t.generate(s);
        var wet:int = 0;
        var shallow:int = 0;
        var dry_middle:int = 0;
        for z in Terrain.SIZE:
            for x in Terrain.SIZE:
                var c:Vector2i = Vector2i(x, z);
                if t.is_water(c):
                    wet += 1;
                    if t.is_shallow(c):
                        shallow += 1;
                elif absi(x - Terrain.SIZE / 2) < Terrain.SIZE * 0.25 and absi(z - Terrain.SIZE / 2) < Terrain.SIZE * 0.25 and t.cell_height(c) > 0.5:
                    dry_middle += 1;
        var cells:float = float(Terrain.SIZE * Terrain.SIZE);
        print("Wetlands seed %d: %.0f%% water, %.0f%% of it wadeable, %d dry cells near the middle" % [s, wet / cells * 100.0, shallow * 100.0 / maxi(wet, 1), dry_middle]);
        _expect("wetlands seed %d: mostly water" % s, wet / cells > 0.55 and wet / cells < 0.9);
        _expect("wetlands seed %d: most of the water can be waded" % s, shallow > wet / 2);
        _expect("wetlands seed %d: there is dry land to start on" % s, dry_middle > 250);
        t.free();
        Terrain.river_style = Terrain.RiverStyle.COAST;
        t = Terrain.new();
        t.generate(s);
        var sea:Array[float] = [0.0, 0.0, 0.0, 0.0];       # share of each edge row that is water
        for i in Terrain.SIZE:
            sea[0] += 1.0 if t.is_water(Vector2i(i, 0)) else 0.0;
            sea[1] += 1.0 if t.is_water(Vector2i(i, Terrain.SIZE - 1)) else 0.0;
            sea[2] += 1.0 if t.is_water(Vector2i(0, i)) else 0.0;
            sea[3] += 1.0 if t.is_water(Vector2i(Terrain.SIZE - 1, i)) else 0.0;
        var open_edges:int = 0;
        var ocean:int = -1;
        for k in 4:
            sea[k] /= Terrain.SIZE;
            if sea[k] > 0.95:
                open_edges += 1;
                ocean = k;
        var opposite:float = sea[[1, 0, 3, 2][ocean]] if ocean >= 0 else 1.0;
        print("Coast seed %d: sea on edge %d, opposite edge %.0f%% water" % [s, ocean, opposite * 100.0]);
        _expect("coast seed %d: exactly one edge is open sea" % s, open_edges == 1);
        _expect("coast seed %d: the opposite edge is mostly land" % s, opposite < 0.5);
        t.free();

func _expect(what:String, ok:bool) -> void:
    print("%s: %s" % ["PASS" if ok else "FAIL", what]);
    if not ok:
        _fails += 1;
