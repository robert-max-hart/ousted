# ----------------------------------------------------------------
# TitleCamera
#     The title screen's camera: it drifts slowly back and forth
#     around the town, rising and falling a little as it goes. Only
#     the camera moves; the scene itself stays frozen.
# ----------------------------------------------------------------
class_name TitleCamera extends Camera3D;

const SWEEP_PERIOD  :float = 110.0;     # seconds for a full swing there and back
const BOB_PERIOD    :float = 61.0;

var target      :Vector3;
var base_yaw    :float;
var sweep       :float = 0.45;          # radians either side of base_yaw
var distance    :float = 38.0;
var elevation   :float = 26.0;          # degrees
var min_height  :Callable = Callable();       # ground height + clearance at a position, to keep the camera above hills
var _t          :float = 0.0;

func _process(delta:float) -> void:
    _t += delta;
    apply();

# Puts the camera where it should be at the current time.
func apply() -> void:
    var yaw:float = base_yaw + sin(_t * TAU / SWEEP_PERIOD) * sweep;
    var elev:float = deg_to_rad(elevation + sin(_t * TAU / BOB_PERIOD) * 3.0);
    var d:float = distance * (1.0 + sin(_t * TAU / (SWEEP_PERIOD * 1.3)) * 0.06);
    var pos:Vector3 = target + Vector3(sin(yaw) * cos(elev), sin(elev), cos(yaw) * cos(elev)) * d;
    if min_height.is_valid():
        pos.y = maxf(pos.y, min_height.call(pos));
    global_position = pos;
    look_at(target, Vector3.UP);
