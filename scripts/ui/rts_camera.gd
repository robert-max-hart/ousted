# ----------------------------------------------------------------
# RTSCamera
#     Orbiting strategy camera. The rig sits on the ground; the camera
#     hangs off it at a pitch and distance.
#       WASD/arrows pan, Q/E rotate, wheel zooms, middle-drag orbits,
#       right-drag pans (grabs the ground).
# ----------------------------------------------------------------
class_name RTSCamera extends Node3D;

const PAN_SPEED     :float = 28.0;
const ROTATE_SPEED  :float = 1.8;
const ZOOM_STEP     :float = 1.15;
const MIN_DISTANCE  :float = 8.0;
const MAX_DISTANCE  :float = 120.0;
const MIN_PITCH     :float = -85.0 * PI / 180.0;
const MAX_PITCH     :float = -20.0 * PI / 180.0;
const DRAG_SENS     :float = 0.006;
const CLICK_SLOP    :float = 4.0;       # px of right-button travel before it counts as a drag

var camera          :Camera3D;
var _yaw            :float = deg_to_rad(35.0);
var _pitch          :float = deg_to_rad(-52.0);
var _distance       :float = 45.0;
var _target_distance:float = 45.0;
var _orbiting       :bool = false;
var _panning        :bool = false;
var _pan_travel     :float = 0.0;
# True when the last right-button press turned into a pan, so a click handler can tell the two apart.
var right_dragged   :bool = false;

func _ready() -> void:
    camera = Camera3D.new();
    camera.far = 800.0;
    camera.fov = 55.0;
    add_child(camera);
    camera.make_current();
    _apply();

func save_state() -> Dictionary:
    return {"position": position, "yaw": _yaw, "pitch": _pitch, "distance": _distance};

func restore_state(d:Dictionary) -> void:
    position = d["position"];
    _yaw = d["yaw"];
    _pitch = d["pitch"];
    _distance = d["distance"];
    _target_distance = _distance;
    _apply();

func focus_on(p:Vector3) -> void:
    position = p;
    _apply();

func _process(delta:float) -> void:
    var move:Vector2 = Vector2.ZERO;
    if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
        move.y -= 1.0;
    if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
        move.y += 1.0;
    if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
        move.x -= 1.0;
    if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
        move.x += 1.0;
    if Input.is_key_pressed(KEY_Q):
        _yaw += ROTATE_SPEED * delta;
    if Input.is_key_pressed(KEY_E):
        _yaw -= ROTATE_SPEED * delta;
    if move != Vector2.ZERO:
        var speed:float = PAN_SPEED * (_distance / 45.0) * (2.5 if Input.is_key_pressed(KEY_SHIFT) else 1.0);
        var dir:Vector3 = Basis(Vector3.UP, _yaw) * Vector3(move.x, 0.0, move.y);
        position += dir.normalized() * speed * delta;
    position.x = clampf(position.x, 0.0, Terrain.SIZE);
    position.z = clampf(position.z, 0.0, Terrain.SIZE);
    var ground:float = World.instance.terrain.height_at(position.x, position.z);
    position.y = lerpf(position.y, maxf(ground, Terrain.WATER_LEVEL), minf(1.0, delta * 6.0));
    _distance = lerpf(_distance, _target_distance, minf(1.0, delta * 10.0));
    _apply();

func _unhandled_input(event:InputEvent) -> void:
    if event is InputEventMouseButton:
        var mb:InputEventMouseButton = event;
        if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
            _target_distance = maxf(MIN_DISTANCE, _target_distance / ZOOM_STEP);
        elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
            _target_distance = minf(MAX_DISTANCE, _target_distance * ZOOM_STEP);
        elif mb.button_index == MOUSE_BUTTON_MIDDLE:
            _orbiting = mb.pressed;
        elif mb.button_index == MOUSE_BUTTON_RIGHT:
            _panning = mb.pressed;
            if mb.pressed:
                _pan_travel = 0.0;
                right_dragged = false;
    elif event is InputEventMouseMotion:
        var mm:InputEventMouseMotion = event;
        if _orbiting:
            _yaw -= mm.relative.x * DRAG_SENS;
            _pitch = clampf(_pitch - mm.relative.y * DRAG_SENS, MIN_PITCH, MAX_PITCH);
        elif _panning:
            _pan_travel += mm.relative.length();
            if _pan_travel > CLICK_SLOP:
                right_dragged = true;
                _pan_by_pixels(mm.relative);

# Moves the rig so the ground under the cursor follows the mouse.
func _pan_by_pixels(rel:Vector2) -> void:
    var view_h:float = maxf(1.0, get_viewport().get_visible_rect().size.y);
    var per_px:float = 2.0 * _distance * tan(deg_to_rad(camera.fov) * 0.5) / view_h;
    var forward_k:float = per_px / maxf(0.2, sin(-_pitch));   # the ground is foreshortened by the pitch
    var local:Vector3 = Vector3(-rel.x * per_px, 0.0, -rel.y * forward_k);
    position += Basis(Vector3.UP, _yaw) * local;

func _apply() -> void:
    rotation = Vector3(0.0, _yaw, 0.0);
    var tilt:Basis = Basis(Vector3.RIGHT, _pitch);
    camera.transform = Transform3D(tilt, tilt * Vector3(0.0, 0.0, _distance));
