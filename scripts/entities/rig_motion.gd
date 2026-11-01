# ----------------------------------------------------------------
# RigMotion
#     The shapes of motion behind the citizens' animation (PawnRig):
#     easing curves, a work swing with a wind-up, a fast strike, an
#     impact and a rebound (instead of a plain sine), and the walk's
#     phase relations between hips, knees, shoulders and elbows. All
#     static and pure, so they can be tested without a body.
# ----------------------------------------------------------------
class_name RigMotion extends RefCounted;

# --------------------------------
# Easing

static func ease_in_out(x:float) -> float:
    x = clampf(x, 0.0, 1.0);
    return x * x * (3.0 - 2.0 * x);

static func ease_in(x:float, power:float = 2.0) -> float:
    return pow(clampf(x, 0.0, 1.0), power);

static func ease_out(x:float, power:float = 2.0) -> float:
    return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), power);

# A smooth pulse: 0, up to 1 over `rise`, held until `fall_at`, back to 0 over `fall`.
static func pulse(t:float, rise:float, fall_at:float, fall:float) -> float:
    return ease_in_out(t / maxf(0.0001, rise)) * (1.0 - ease_in_out((t - fall_at) / maxf(0.0001, fall)));

# --------------------------------
# Work swings

# Where in its swing a tool is, as 0 at the moment of the strike up to 1 at the top, for a phase of 0 to 1 round the cycle. The strike is
# at 0.75 of the cycle (Pawn._strike listens to the same clock: the tool comes down when sin(phase) is at its lowest). `style` picks the
# timing: heavy (an axe or pick: a long lift, a pause at the top and a fast fall), quick (a hammer: short lift, snappy), push (a hoe: a
# pull up and a push down), or anything else a gentle reach. Values may dip a little under 0 (digging in) and over 1 (the top of the lift).
static func work_u(phase:float, style:StringName) -> float:
    var s:float = fposmod(phase - 0.75, 1.0);          # 0 at the strike, running on through the rebound, the lift, the pause and the fall
    match style:
        &"heavy":
            return _swing(s, 0.08, 0.60, 0.70, 0.12);
        &"quick":
            return _swing(s, 0.10, 0.52, 0.58, 0.05);
        &"push":
            return _swing(s, 0.12, 0.66, 0.74, 0.14);
    return (sin(phase * TAU) + 1.0) * 0.5;               # (the gentle reach: the old plain sine, 0 at phase 0.75)

# The piecewise swing: a rebound to 0.1 over [0, rebound), a slow eased lift to the top by `top_at`, a settle at the top (a small
# overshoot and back) until `fall_from`, then a falling strike that speeds up and lands at 1.0 with a little dig-in under 0.
static func _swing(s:float, rebound:float, top_at:float, fall_from:float, dig:float) -> float:
    if s < rebound:
        return lerpf(-0.04 * dig / 0.12, 0.1, ease_out(s / rebound));
    if s < top_at:
        return lerpf(0.1, 1.0, ease_in_out((s - rebound) / (top_at - rebound)));
    if s < fall_from:
        var k:float = (s - top_at) / (fall_from - top_at);
        return 1.0 + 0.045 * sin(k * PI);                  # a settle at the top: the wind-up hangs for a beat
    var f:float = (s - fall_from) / (1.0 - fall_from);
    return lerpf(1.0, -0.04 * dig / 0.12, ease_in(f, 2.4));

# --------------------------------
# Walking (phi is the stride in radians: the left thigh is at its rearmost at PI/2)

# Thigh angles (positive swings the leg back) for the left and right leg.
static func thigh(phi:float, amp:float) -> Vector2:
    return Vector2(sin(phi), -sin(phi)) * 0.64 * amp;

# Knee bend (positive, the shin goes back): a little all the time, a lot while the leg swings forward through the middle of the step.
static func knee(phi:float, amp:float) -> Vector2:
    var l:float = pow(maxf(0.0, -cos(phi)), 1.6);
    var r:float = pow(maxf(0.0, cos(phi)), 1.6);
    return Vector2(0.1 + 0.95 * l, 0.1 + 0.95 * r) * amp + Vector2(0.06, 0.06) * (1.0 - amp);

# Shoulder swing (negative is forward), lagging the hips a little: the arm follows the leg.
static func shoulder(phi:float, amp:float) -> Vector2:
    var s:float = sin(phi - 0.35);
    return Vector2(-s, s) * 0.5 * amp;

# Elbow bend (negative bends the forearm forward): the arm folds as it comes forward.
static func elbow(phi:float, amp:float) -> Vector2:
    var s:float = sin(phi - 0.35);
    return Vector2(-(0.2 + 0.45 * maxf(0.0, s)), -(0.2 + 0.45 * maxf(0.0, -s))) * lerpf(0.6, 1.0, amp);

# How far the hips drop and rise: highest as the legs pass under the body, lowest as the feet land (two bobs a stride).
static func bob(phi:float, amp:float) -> float:
    return 0.048 * amp * (0.5 + 0.5 * cos(2.0 * phi));

# The shoulders turn against the hips.
static func twist(phi:float, amp:float) -> float:
    return 0.14 * amp * sin(phi - 0.2);

# The body leans over the leg that carries it.
static func roll(phi:float, amp:float) -> float:
    return 0.04 * amp * sin(phi);
