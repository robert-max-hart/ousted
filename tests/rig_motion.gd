# ----------------------------------------------------------------
# Rig motion
#     The curves behind the citizens' animation: easing, the work swing
#     (a wind-up, a fast fall and a rebound that meets the sound of the
#     strike), the walk's phase relations (knees bend while a leg swings
#     forward, the arm swings against the leg, two bobs a stride), and
#     smoothness: no jumps from one frame to the next.
#     godot --headless --path . --fixed-fps 60 res://tests/rig_motion.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;

func _ready() -> void:
    _expect("easing starts at 0 and ends at 1", RigMotion.ease_in_out(0.0) == 0.0 and RigMotion.ease_in_out(1.0) == 1.0 and RigMotion.ease_in(1.0) == 1.0 and RigMotion.ease_out(0.0) == 0.0);
    # work swings
    for style in [&"heavy", &"quick", &"push", &"gentle"]:
        var biggest_step:float = 0.0;
        var lo:float = 9.0;
        var hi:float = -9.0;
        var prev:float = RigMotion.work_u(0.0, style);
        for i in range(1, 1001):
            var u:float = RigMotion.work_u(i / 1000.0, style);
            biggest_step = maxf(biggest_step, absf(u - prev));
            prev = u;
            lo = minf(lo, u);
            hi = maxf(hi, u);
        _expect("%s: a smooth swing, no jumps (biggest step %.3f in a thousandth of a cycle)" % [style, biggest_step], biggest_step < 0.04);
        _expect("%s: from about 0 at the strike to about 1 at the top (%.2f to %.2f)" % [style, lo, hi], lo > -0.12 and lo < 0.01 and hi > 0.99 and hi < 1.08);
        _expect("%s: the strike is at three quarters of the cycle (%.3f)" % [style, RigMotion.work_u(0.75, style)], RigMotion.work_u(0.75, style) < 0.05);
    # heavy swings take long to lift and fall fast: the fall is quicker than the rise
    var rise_time:float = 0.0;
    var fall_time:float = 0.0;
    for i in 1000:
        var a:float = RigMotion.work_u(0.75 + i / 1000.0, &"heavy");
        var b:float = RigMotion.work_u(0.75 + (i + 1) / 1000.0, &"heavy");
        if b > a and a > 0.05 and b < 0.95:
            rise_time += 0.001;
        elif b < a and a > 0.05 and a < 0.95:
            fall_time += 0.001;
    _expect("a heavy swing lifts slowly and falls fast (lift %.2f of the cycle, fall %.2f)" % [rise_time, fall_time], rise_time > fall_time * 1.5);
    # walking
    var knee_ok:bool = true;
    for i in 200:
        var phi:float = i * 0.0314;
        var th:Vector2 = RigMotion.thigh(phi, 1.0);
        var kn:Vector2 = RigMotion.knee(phi, 1.0);
        knee_ok = knee_ok and kn.x >= 0.0 and kn.y >= 0.0;
        if absf(th.x) < 0.02:           # the legs pass under the body: the one swinging forward has its knee bent, the other straight
            var swinging_left:bool = cos(phi) < 0.0;
            knee_ok = knee_ok and (kn.x > kn.y if swinging_left else kn.y > kn.x);
    _expect("knees only bend one way, and the swinging leg's is the bent one", knee_ok);
    var s:Vector2 = RigMotion.shoulder(1.0, 1.0);
    var t:Vector2 = RigMotion.thigh(1.0, 1.0);
    _expect("each arm swings against its own side's leg (%s, %s)" % [s, t], (s.x < 0.0) == (t.x > 0.0) or absf(s.x) < 0.05);
    _expect("the two legs swing in opposition", RigMotion.thigh(0.7, 1.0).x == -RigMotion.thigh(0.7, 1.0).y);
    var bobs:int = 0;
    var prev_b:float = RigMotion.bob(0.0, 1.0);
    var rising:bool = false;
    for i in range(1, 400):
        var b2:float = RigMotion.bob(i * TAU / 200.0, 1.0);          # two cycles of the stride
        var now_rising:bool = b2 > prev_b;
        if rising and not now_rising:
            bobs += 1;
        rising = now_rising;
        prev_b = b2;
    _expect("the hips bob twice a stride (%d peaks in two strides)" % bobs, bobs == 4 or bobs == 3);
    var slow:float = RigMotion.thigh(1.0, 0.5).x;
    var brisk:float = RigMotion.thigh(1.0, 1.0).x;
    _expect("a slower walk takes smaller steps", absf(slow) < absf(brisk));
    print("RIG MOTION %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
