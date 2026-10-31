# ----------------------------------------------------------------
# Water shader test
#     The water uses the shader material with its ripple texture, its
#     clock follows the game's speed (still when paused) and its waves
#     rise in rain; the generated texture is the right size and has
#     slopes around 0.5. (The look is checked by water_shot, windowed.)
#     godot --headless --path . --fixed-fps 60 res://tests/water_shader.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    await get_tree().process_frame;
    var vis:WorldVisuals = world.visuals;
    var mat:ShaderMaterial = vis._water_mat;
    _expect("the water has the shader material", mat != null and mat.shader != null and mat.shader.code.contains("shader_type spatial"));
    var tex:Texture2D = mat.get_shader_parameter("ripples") as Texture2D;
    _expect("with a ripple texture of %d" % WaterTexture.SIZE, tex != null and tex.get_width() == WaterTexture.SIZE);
    var img:Image = tex.get_image();
    var sum:float = 0.0;
    for y in range(0, WaterTexture.SIZE, 7):
        for x in range(0, WaterTexture.SIZE, 7):
            sum += img.get_pixel(x, y).r;
    var mean:float = sum / float(ceili(WaterTexture.SIZE / 7.0) * ceili(WaterTexture.SIZE / 7.0));
    _expect("the ripple slopes are centred on flat (%.2f)" % mean, mean > 0.4 and mean < 0.6);
    GameClock.set_speed(0);
    var c0:float = vis._fx_clock;
    vis._update_water(1.0);
    _expect("paused water does not move", vis._fx_clock == c0);
    GameClock.set_speed(2);
    vis._update_water(1.0);
    _expect("at 2x the clock runs 2 seconds a second (%.2f)" % (vis._fx_clock - c0), is_equal_approx(vis._fx_clock - c0, GameClock.speed()));
    Weather.intensity = 0.0;
    vis._update_water(0.0);
    var calm:float = mat.get_shader_parameter("swell");
    Weather.intensity = 1.0;
    vis._update_water(0.0);
    var rough:float = mat.get_shader_parameter("swell");
    Weather.intensity = 0.0;
    _expect("waves are bigger in rain (%.3f against %.3f)" % [rough, calm], rough > calm);
    print("WATER SHADER %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    print("%s: %s" % ["PASS" if ok else "FAIL", what]);
    if not ok:
        _fails += 1;
