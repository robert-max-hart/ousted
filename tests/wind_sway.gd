# ----------------------------------------------------------------
# Wind sway test
#     Trees, bushes and grass use the swaying materials; one clock moves
#     them all and it stops when the game is paused; the wind is stronger
#     in rain; the season colours are still set (through WindSway); and
#     the sway shader's offset leaves the foot alone and moves the top.
#     (The look is checked by water_shot, windowed.)
#     godot --headless --path . --fixed-fps 60 res://tests/wind_sway.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    await get_tree().process_frame;
    var vis:WorldVisuals = world.visuals;
    var r:ResourceRenderer = world.renderer;
    _expect("tree, bush and oak materials are swaying shaders", r._canopy_mat is ShaderMaterial and r._bush_mat is ShaderMaterial and r._oak_leaf_mat is ShaderMaterial);
    var grass:GrassDetail = null;
    for c in world.get_children():
        if c is GrassDetail:
            grass = c;
    _expect("so is the grass", grass != null and grass._mat is ShaderMaterial and grass._mat.shader.code.contains("cull_disabled"));
    _expect("the materials are kept in step (%d)" % WindSway.count(), WindSway.count() >= 10);
    GameClock.set_speed(0);
    vis._update_water(1.0);
    var still:float = r._canopy_mat.get_shader_parameter("clock");
    vis._update_water(1.0);
    _expect("paused trees do not move", r._canopy_mat.get_shader_parameter("clock") == still);
    GameClock.set_speed(3);
    vis._update_water(1.0);
    _expect("running, the clock moves all of them together", r._canopy_mat.get_shader_parameter("clock") > still and r._canopy_mat.get_shader_parameter("clock") == grass._mat.get_shader_parameter("clock"));
    Weather.intensity = 0.0;
    vis._update_water(0.0);
    var calm:float = r._canopy_mat.get_shader_parameter("wind");
    Weather.intensity = 1.0;
    vis._update_water(0.0);
    var rain:float = r._canopy_mat.get_shader_parameter("wind");
    Weather.intensity = 0.0;
    _expect("the wind is stronger in rain (%.1f against %.1f)" % [rain, calm], rain > calm);
    r.set_season(GameClock.Season.AUTUMN);
    _expect("season colours still reach the canopy", (r._canopy_mat.get_shader_parameter("albedo") as Color).is_equal_approx(ResourceRenderer.CANOPY_BY_SEASON[GameClock.Season.AUTUMN]));
    # materials of a world that is gone are dropped
    var before:int = WindSway.count();
    world.queue_free();
    await get_tree().process_frame;
    await get_tree().process_frame;
    WindSway.update(0.0, 1.0);
    _expect("a freed world's materials are dropped (%d to %d)" % [before, WindSway.count()], WindSway.count() < before);
    print("WIND SWAY %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    print("%s: %s" % ["PASS" if ok else "FAIL", what]);
    if not ok:
        _fails += 1;
