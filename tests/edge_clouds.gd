# ----------------------------------------------------------------
# Edge clouds test
#     The map is ringed by a bank of cloud billows and a cloud sea: the sea is under the lowest ground and wide
#     enough to reach past the horizon; along every edge, at every station, a billow covers the edge point and rises
#     above the ground there (so the cut is hidden from the side); there is one on each side of the corners; the
#     clouds take the colour of the sky (dark at night, warm at dusk) and move with the game clock.
#     godot --headless --path . --fixed-fps 60 res://tests/edge_clouds.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Weather.drought_enabled = false;
    Defs.difficulty = &"easy";
    for seed in [5, 11, 23]:
        World.new_game_seed = seed;
        var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
        add_child(world);
        GameClock.set_speed(0);
        await get_tree().process_frame;
        await get_tree().process_frame;
        _check(world, seed);
        world.queue_free();
        await get_tree().process_frame;
    print("EDGE CLOUDS %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _check(world:World, seed:int) -> void:
    var c:MapEdgeClouds = world.visuals.edge_clouds;
    var t:Terrain = world.terrain;
    var size:float = Terrain.SIZE;
    _expect("seed %d: there is a cloud bank (%d billows)" % [seed, c.puff_count()], c != null and c.puff_count() > 300);
    var low:float = INF;
    for x in range(0, Terrain.SIZE + 1, 4):
        for z in range(0, Terrain.SIZE + 1, 4):
            low = minf(low, t.height_at(x, z));
    _expect("seed %d: the cloud sea (%.1f) is under the lowest ground (%.1f)" % [seed, c.floor_height(), low], c.floor_height() < low - 1.0);
    var uncovered:int = 0;
    var lower:int = 0;
    var checked:int = 0;
    for side in 4:
        for i in range(0, Terrain.SIZE + 1, 4):
            var p:Vector2 = [Vector2(i, 0), Vector2(size, i), Vector2(i, size), Vector2(0, i)][side];
            var ground:float = t.height_at(p.x, p.y);
            var best:float = -INF;
            for puff in c.puffs:
                var d:Vector2 = Vector2(puff[0].x - p.x, puff[0].z - p.y);
                if d.length() < puff[1] * 0.8:
                    best = maxf(best, puff[0].y + puff[2]);
            checked += 1;
            if best == -INF:
                uncovered += 1;
            elif best < ground:
                lower += 1;
    _expect("seed %d: a billow covers every edge point (%d of %d uncovered)" % [seed, uncovered, checked], uncovered == 0);
    _expect("seed %d: and rises above the ground there (%d too low)" % [seed, lower], lower == 0);
    for corner in [Vector2(0, 0), Vector2(size, 0), Vector2(size, size), Vector2(0, size)]:
        var near:int = 0;
        for puff in c.puffs:
            if Vector2(puff[0].x - corner.x, puff[0].z - corner.y).length() < 10.0:
                near += 1;
        _expect("seed %d: the corner at %s is covered (%d billows)" % [seed, corner, near], near >= 2);
    # the colour follows the sky
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON * 1 + 3) * GameClock.HOURS_PER_DAY + 12.0;
    world.visuals._update_lighting();
    var noon:Color = c._bank_mat.get_shader_parameter("tint");
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON * 1 + 3) * GameClock.HOURS_PER_DAY + 1.0;
    world.visuals._update_lighting();
    var night:Color = c._bank_mat.get_shader_parameter("tint");
    _expect("seed %d: the clouds are brighter at noon than at night and bluer at night (%.2f, %.2f)" % [seed, noon.get_luminance(), night.get_luminance()], noon.get_luminance() > night.get_luminance() * 1.3 and night.b > night.r);
    GameClock.set_speed(1);
    world.visuals._update_water(0.5);
    var running:float = float(c._bank_mat.get_shader_parameter("clock"));
    GameClock.set_speed(0);
    world.visuals._update_water(0.5);
    _expect("seed %d: the clouds move with the game and hold when it is paused" % seed, running > 0.0 and is_equal_approx(float(c._bank_mat.get_shader_parameter("clock")), running));

func _expect(what:String, ok:bool) -> void:
    if ok:
        print("PASS: ", what);
    else:
        _fails += 1;
        print("FAIL: ", what);
