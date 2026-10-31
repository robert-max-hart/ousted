# ----------------------------------------------------------------
# Terrain shader and snow test
#     The ground uses the shader material with its noise texture; roads and
#     fields hold less snow than open ground and channels none; the winter
#     ground is dormant, not painted white (snow comes from the shader);
#     snow cover builds in snowfall, melts when warm, stays through cold
#     clear weather and stops with the game paused; a game starts with
#     the cover its season suggests; and an overlay switches the detail off.
#     (The look is checked by terrain_shot, windowed.)
#     godot --headless --path . --fixed-fps 60 res://tests/terrain_shader.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Weather.drought_enabled = false;
    GameClock.reset();
    GameClock.total_hours = float(2 * GameClock.HOURS_PER_DAY + 12);        # a spring day
    Weather.reset();
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    await get_tree().process_frame;
    var t:Terrain = world.terrain;
    var vis:WorldVisuals = world.visuals;
    var mat:ShaderMaterial = t._material;
    _expect("the terrain has the shader material and a noise texture", mat != null and mat.shader.code.contains("shader_type spatial") and (mat.get_shader_parameter("noise_tex") as Texture2D).get_width() == TerrainTexture.SIZE);
    _expect("snow lies best on open ground, less on roads and fields, not in a channel", t._snow_hold(Terrain.Overlay.NONE) == 1.0 and t._snow_hold(Terrain.Overlay.ROAD) < t._snow_hold(Terrain.Overlay.TILLED) and t._snow_hold(Terrain.Overlay.TILLED) < 1.0 and t._snow_hold(Terrain.Overlay.CHANNEL) == 0.0);
    _expect("the winter ground is dormant, not painted white", Terrain.GRASS_BY_SEASON[GameClock.Season.WINTER].get_luminance() < 0.5);
    _expect("a spring start has no snow (%.2f)" % vis.snow_cover, vis.snow_cover == 0.0);
    GameClock.total_hours = float(27 * GameClock.HOURS_PER_DAY + 12);        # a winter day
    Weather.reset();
    vis.start_snow_cover();
    _expect("a winter start has some (%.2f)" % vis.snow_cover, vis.snow_cover > 0.0);
    _expect("and the shader is given it", is_equal_approx(float(mat.get_shader_parameter("snow")), vis.snow_cover));

    # snowfall builds it
    vis.snow_cover = 0.0;
    GameClock.set_speed(3);
    Weather._dry_temperature = -6.0;
    Weather.temperature = -6.0;
    Weather.is_raining = true;
    Weather.intensity = 1.0;
    _expect("it is snowing", Weather.is_snowing());
    vis._update_snow(1.0);
    var built:float = vis.snow_cover;
    _expect("snowfall builds cover (%.2f)" % built, built > 0.05);
    # cold and clear: it stays
    Weather.is_raining = false;
    Weather.intensity = 0.0;
    vis._update_snow(1.0);
    _expect("cold, clear weather keeps it", is_equal_approx(vis.snow_cover, built));
    # warm: it melts, faster in rain
    vis.snow_cover = 0.8;
    Weather.temperature = 6.0;
    vis._update_snow(1.0);
    var melted:float = vis.snow_cover;
    _expect("warm weather melts it (%.2f from 0.80)" % melted, melted < 0.8);
    vis.snow_cover = 0.8;
    Weather._dry_temperature = 6.0;       # (so the rain is rain, not snow)
    Weather.intensity = 0.5;
    vis._update_snow(1.0);
    _expect("rain melts it faster (%.2f)" % vis.snow_cover, vis.snow_cover < melted);
    Weather.intensity = 0.0;
    # paused: nothing changes
    GameClock.set_speed(0);
    vis.snow_cover = 0.8;
    vis._update_snow(1.0);
    _expect("a paused game keeps it as it is", vis.snow_cover == 0.8);
    _expect("it never leaves 0 to 1", vis.snow_cover >= 0.0 and vis.snow_cover <= 1.0);

    # overlays show the colour plain
    _expect("detail is on by default", float(mat.get_shader_parameter("overlay_view")) == 0.0);
    t.set_soil_view(true);
    _expect("an overlay turns the detail off", float(mat.get_shader_parameter("overlay_view")) == 1.0);
    t.set_soil_view(false);
    t.set_slope_view(true);
    t.set_slope_view(false);
    _expect("and off again", float(mat.get_shader_parameter("overlay_view")) == 0.0);
    print("TERRAIN SHADER %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    print("%s: %s" % ["PASS" if ok else "FAIL", what]);
    if not ok:
        _fails += 1;
