# ----------------------------------------------------------------
# SleepZs
#     The Zs that float up from a citizen asleep in the open: three
#     letters of different sizes, each rising, drifting and fading in
#     turn. A child of the Pawn (made the first time they sleep out);
#     update(t) is called every frame while it is shown.
# ----------------------------------------------------------------
class_name SleepZs extends Node3D;

const COUNT   :int = 3;
const PERIOD  :float = 3.0;           # seconds for one Z to rise and fade
const RISE    :float = 0.75;          # metres
const SIZES   :Array[float] = [0.9, 1.15, 1.4];

var _labels:Array[Label3D] = [];

func _init() -> void:
    for i in COUNT:
        var l:Label3D = Label3D.new();
        l.text = "Z";
        l.billboard = BaseMaterial3D.BILLBOARD_ENABLED;
        l.font_size = 40;
        l.pixel_size = 0.007;
        l.outline_size = 10;
        l.outline_modulate = Color(0.1, 0.12, 0.25, 0.9);
        l.modulate = Color(0.92, 0.95, 1.0, 0.0);
        l.shaded = false;
        l.no_depth_test = true;
        add_child(l);
        _labels.append(l);

func update(t:float) -> void:
    for i in COUNT:
        var u:float = fposmod(t / PERIOD + float(i) / COUNT, 1.0);
        var l:Label3D = _labels[i];
        l.position = Vector3(0.12 * sin(u * 5.0 + i) + 0.08 * u, u * RISE, 0.0);
        l.scale = Vector3.ONE * SIZES[i] * (0.6 + 0.6 * u);
        var a:float = smoothstep(0.0, 0.2, u) * (1.0 - smoothstep(0.65, 1.0, u));
        l.modulate.a = a;
        l.outline_modulate.a = 0.9 * a;
