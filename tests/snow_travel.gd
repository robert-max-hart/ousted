# ----------------------------------------------------------------
# Snow travel
#     Snow on the ground slows citizens on foot: open ground most, roads
#     and bridges a little, none in clear weather. The depth is the
#     weather's (saved with it), the terrain shader follows it, and it
#     builds while it snows and melts when it is warm.
#     godot --headless --path . --fixed-fps 60 res://tests/snow_travel.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    Weather.drought_enabled = false;
    GameRules.reset();
    GameRules.illness = 0;
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    await get_tree().process_frame;
    var p:Pawn = world.pawns[0];
    var o:Vector2i = TestSite.near(world, Vector2i(8, 8), Vector2i(16, 4));
    world.terrain.flatten_rect(Rect2i(o, Vector2i(16, 4)));
    var open:Vector2i = o + Vector2i(1, 0);
    var road:Vector2i = o + Vector2i(2, 2);
    world.terrain.set_overlay(road, Terrain.Overlay.ROAD);
    Weather.snow_depth = 0.0;
    _expect("no snow: open ground is the normal speed", is_equal_approx(p.ground_speed(open), 1.0));
    _expect("and a road is quicker", is_equal_approx(p.ground_speed(road), Pawn.ROAD_SPEED_MULT));
    Weather.snow_depth = 1.0;
    _expect("full snow slows open ground (%.2f)" % p.ground_speed(open), is_equal_approx(p.ground_speed(open), Pawn.SNOW_SPEED_MULT));
    _expect("a road much less (%.2f)" % p.ground_speed(road), is_equal_approx(p.ground_speed(road), Pawn.ROAD_SPEED_MULT * Pawn.SNOW_ROAD_MULT) and p.ground_speed(road) > p.ground_speed(open) * 1.5);
    Weather.snow_depth = 0.5;
    _expect("half the snow is half the slowing (%.2f)" % p.ground_speed(open), is_equal_approx(p.ground_speed(open), lerpf(1.0, Pawn.SNOW_SPEED_MULT, 0.5)));
    # a real walk: the distance covered in a second
    var dist:Dictionary = {};
    for depth in [0.0, 1.0]:
        Weather.snow_depth = depth;
        p.position = Vector3(o.x + 0.5, 0.0, o.y + 0.5);
        var path:Array[Vector2i] = [];
        for i in 14:
            path.append(o + Vector2i(i, 0));
        p._path = path;
        p._path_i = 1;
        p._follow_path(1.0);
        dist[depth] = p.position.x - (o.x + 0.5);
    print("distance in a second: %s" % str(dist));
    _expect("a citizen walks about 0.6 of the way in full snow (%.2f against %.2f)" % [dist[1.0], dist[0.0]], absf(dist[1.0] / dist[0.0] - Pawn.SNOW_SPEED_MULT) < 0.05);
    # building and melting
    Weather.snow_depth = 0.0;
    Weather.is_raining = true;
    Weather.intensity = 1.0;
    Weather._dry_temperature = -5.0;
    Weather.temperature = -6.0;
    Weather.update_snow(3.0);
    _expect("it builds while it snows (%.2f)" % Weather.snow_depth, Weather.snow_depth > 0.4 and Weather.snow_depth < 0.7);
    Weather.update_snow(0.0);
    var held:float = Weather.snow_depth;
    Weather.is_raining = false;
    Weather.intensity = 0.0;
    Weather.update_snow(5.0);
    _expect("cold and clear it stays (%.2f)" % Weather.snow_depth, is_equal_approx(Weather.snow_depth, held));
    Weather.temperature = 10.0;
    Weather.update_snow(5.0);
    _expect("warm it melts (%.2f)" % Weather.snow_depth, Weather.snow_depth < held);
    Weather.snow_depth = 0.99;
    Weather.is_raining = true;
    Weather.intensity = 1.0;
    Weather.temperature = -6.0;
    Weather.update_snow(10.0);
    _expect("it never passes full cover", Weather.snow_depth <= 1.0);
    # the visuals and saving
    world.visuals.snow_cover = 0.35;
    _expect("the visuals' snow cover is the weather's depth", is_equal_approx(Weather.snow_depth, 0.35));
    Weather.is_raining = false;
    Weather.intensity = 0.0;
    var saved:Dictionary = Weather.save_state();
    Weather.reset();
    _expect("a new game has none", Weather.snow_depth == 0.0 and not Weather.snow_loaded);
    Weather.restore_state(saved);
    _expect("the depth is saved", is_equal_approx(Weather.snow_depth, 0.35) and Weather.snow_loaded);
    world.visuals.start_snow_cover();
    _expect("a loaded world keeps it, and uses it up", is_equal_approx(Weather.snow_depth, 0.35) and not Weather.snow_loaded);
    var old:Dictionary = saved.duplicate();
    old.erase("snow_depth");
    Weather.restore_state(old);
    _expect("a save from before has no depth and starts from the season", not Weather.snow_loaded);
    print("SNOW TRAVEL %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
