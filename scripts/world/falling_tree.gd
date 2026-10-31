# ----------------------------------------------------------------
# FallingTree
#     A tree that has just been felled, on its way down: the same mesh
#     the tree was drawn with, pivoting about its foot to tip over away
#     from the woodcutter, speeding up as it goes, settling with a
#     small rebound and lying a moment before it sinks and is gone.
#     Purely visual (the tree is already removed from the world); it
#     runs on the game's effect clock, so it holds when paused.
# ----------------------------------------------------------------
class_name FallingTree extends Node3D;

const FALL_SECONDS:float = 1.25;          # tipping over, from upright to flat
const LIE_SECONDS :float = 0.9;           # lying there
const SINK_SECONDS:float = 0.9;           # sinking and shrinking away
const REBOUND     :float = 0.09;          # how far it springs back up on hitting the ground, in radians

var _t       :float = 0.0;
var _axis    :Vector3 = Vector3.RIGHT;
var _spin    :Basis = Basis.IDENTITY;      # the tree's own turn and size, kept under the tip-over
var _foot    :Vector3;
var _size    :float = 1.0;

# `meshes` are the parts to draw (the tree, and its crown if that is a layer of its own), `away` is the horizontal direction it falls.
func setup(meshes:Array, foot:Vector3, yaw:float, size:float, away:Vector3) -> void:
    _foot = foot;
    _size = size;
    _spin = Basis(Vector3.UP, yaw);
    var d:Vector3 = Vector3(away.x, 0.0, away.z);
    d = d.normalized() if d.length() > 0.01 else Vector3.RIGHT;
    _axis = Vector3.UP.cross(d);
    for m in meshes:
        var mi:MeshInstance3D = MeshInstance3D.new();
        mi.mesh = m;
        add_child(mi);
    position = foot;
    _apply(0.0, 1.0);

func _process(delta:float) -> void:
    _t += delta * minf(World.fx_speed(), 3.0);
    var angle:float = PI * 0.5;
    var scale_k:float = 1.0;
    var sink:float = 0.0;
    if _t < FALL_SECONDS:
        var k:float = _t / FALL_SECONDS;
        angle = PI * 0.5 * k * k;                         # gravity: slow at first, quicker as it goes
    elif _t < FALL_SECONDS + 0.45:
        var r:float = _t - FALL_SECONDS;
        angle = PI * 0.5 - REBOUND * absf(sin(r * 14.0)) * exp(-r * 7.0);
    elif _t > FALL_SECONDS + LIE_SECONDS:
        var s:float = (_t - FALL_SECONDS - LIE_SECONDS) / SINK_SECONDS;
        if s >= 1.0:
            queue_free();
            return;
        scale_k = 1.0 - s;
        sink = s * 0.5;
    _apply(angle, scale_k, sink);

func _apply(angle:float, scale_k:float, sink:float = 0.0) -> void:
    transform = Transform3D(Basis(_axis.normalized(), angle) * _spin.scaled(Vector3.ONE * _size * scale_k), _foot - Vector3(0, sink, 0));

# How far over it has fallen now, in radians (0 upright, a quarter turn flat), for tests.
func angle_now() -> float:
    var up:Vector3 = (transform.basis * Vector3.UP).normalized();
    return acos(clampf(up.y, -1.0, 1.0));
