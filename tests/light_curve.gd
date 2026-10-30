# ----------------------------------------------------------------
# Light curve
#     Steps through the day and checks the light never jumps: neither
#     light's energy changes by more than a small step, and a light
#     that is on never turns to a new direction in one step (the sun and
#     moon each cross the sky once and fade at the ends).
#     godot --headless --path . --fixed-fps 60 res://tests/light_curve.tscn
# ----------------------------------------------------------------
extends Node;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Weather.drought_enabled = false;
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    Weather.intensity = 0.0;
    var v:WorldVisuals = world.visuals;
    var fails:int = 0;
    var prev_sun:float = -1.0;
    var prev_moon:float = -1.0;
    var prev_sun_dir:Vector3 = Vector3.ZERO;
    var prev_moon_dir:Vector3 = Vector3.ZERO;
    var biggest:float = 0.0;
    var day0:float = floorf(GameClock.total_hours / 24.0) * 24.0;
    for i in 481:
        GameClock.total_hours = day0 + i * 0.05;
        v._update_lighting();
        var s:float = v._sun.light_energy;
        var m:float = v._moon.light_energy;
        var sd:Vector3 = -v._sun.global_transform.basis.z;
        var md:Vector3 = -v._moon.global_transform.basis.z;
        if prev_sun >= 0.0:
            biggest = maxf(biggest, maxf(absf(s - prev_sun), absf(m - prev_moon)));
            if absf(s - prev_sun) > 0.03 or absf(m - prev_moon) > 0.03:
                print("FAIL energy jumps at hour %.2f: sun %.2f -> %.2f, moon %.2f -> %.2f" % [i * 0.05, prev_sun, s, prev_moon, m]);
                fails += 1;
            if s > 0.02 and prev_sun > 0.02 and sd.angle_to(prev_sun_dir) > 0.08:
                print("FAIL the sun turns suddenly at hour %.2f" % (i * 0.05));
                fails += 1;
            if m > 0.02 and prev_moon > 0.02 and md.angle_to(prev_moon_dir) > 0.08:
                print("FAIL the moon turns suddenly at hour %.2f" % (i * 0.05));
                fails += 1;
        prev_sun = s;
        prev_moon = m;
        prev_sun_dir = sd;
        prev_moon_dir = md;
    print("biggest energy step in 0.05 h: %.3f" % biggest);
    print("LIGHT CURVE %s" % ("PASS" if fails == 0 else "FAIL"));
    get_tree().quit(1 if fails > 0 else 0);
