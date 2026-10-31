# ----------------------------------------------------------------
# AmbientAudio
#     The background sound of the land: wind, rain, running water, birds
#     by day and crickets at night (loops in assets/audio/ambient, made
#     by tools/make_sounds.py). A child of World; each loop fades toward
#     a level worked out from the weather, the time of day, the season
#     and what the camera is looking at (water within sight). Plays on
#     the Ambient bus, so it follows the Ambient volume in Settings.
# ----------------------------------------------------------------
class_name AmbientAudio extends Node;

const DIR      :String = "res://assets/audio/ambient/";
const FADE_PER_SEC:float = 0.5;          # how fast a level moves toward its target
const LOOK_EVERY:float = 0.5;            # seconds between looks at the camera's surroundings
const WATER_SEEN_RADIUS:int = 14;        # cells round the point the camera looks at
const LOUDNESS:Dictionary = {&"wind": 0.55, &"rain": 0.75, &"water": 0.8, &"birds": 0.7, &"crickets": 0.55};

var world:World;
var levels :Dictionary = {};       # id -> current level 0..1
var targets:Dictionary = {};       # id -> where it is heading
var _players:Dictionary = {};      # id -> AudioStreamPlayer
var _look  :float = 0.0;
var _water_share:float = 0.0;

func _init(w:World) -> void:
    world = w;

func _ready() -> void:
    Sfx.ensure_buses();
    Sfx.apply_volumes();
    for id in LOUDNESS:
        var src:AudioStreamWAV = load("%s%s.wav" % [DIR, id]) as AudioStreamWAV;
        if src == null:
            continue;
        var s:AudioStreamWAV = src.duplicate() as AudioStreamWAV;
        s.loop_mode = AudioStreamWAV.LOOP_FORWARD;
        s.loop_begin = 0;
        s.loop_end = s.data.size() / 2;          # 16-bit mono: two bytes a frame
        var p:AudioStreamPlayer = AudioStreamPlayer.new();
        p.stream = s;
        p.bus = Sfx.BUS_AMBIENT;
        p.volume_db = -80.0;
        add_child(p);
        _players[id] = p;
        levels[id] = 0.0;
        targets[id] = 0.0;
    _update_targets();
    for id in levels:           # start where they are going: no fade-in from silence when a game opens
        levels[id] = targets[id];
        _apply(id);

func _process(delta:float) -> void:
    _look -= delta;
    if _look <= 0.0:
        _look = LOOK_EVERY;
        _update_targets();
    for id in _players:
        levels[id] = move_toward(levels[id], targets[id], delta * FADE_PER_SEC);
        _apply(id);

func _apply(id:StringName) -> void:
    var p:AudioStreamPlayer = _players[id];
    var level:float = levels[id] * LOUDNESS[id];
    if level < 0.004:
        if p.playing:
            p.stop();
        return;
    p.volume_db = linear_to_db(level);
    if not p.playing:
        p.play(randf() * p.stream.get_length());

# What each loop should be right now.
func _update_targets() -> void:
    var rain:float = 0.0 if Weather.is_snowing() else Weather.intensity;
    var snow:float = Weather.intensity if Weather.is_snowing() else 0.0;
    var hour:float = GameClock.hour();
    var day:bool = hour >= 6.0 and hour < 19.5;
    var night:bool = hour >= 21.0 or hour < 4.5;
    var calm:float = 1.0 - clampf(Weather.intensity * 1.4, 0.0, 1.0);
    var warm:float = clampf((Weather.temperature - 4.0) / 8.0, 0.0, 1.0);
    targets[&"wind"] = clampf(0.25 + 0.45 * rain + 0.35 * snow + 0.15 * float(Weather.temperature < 0.0), 0.0, 1.0);
    targets[&"rain"] = rain;
    targets[&"water"] = clampf(_look_at_water() * 3.0, 0.0, 1.0) * (1.0 - 0.5 * rain);
    targets[&"birds"] = (calm * warm) if (day and not Climate.is_dormant()) else 0.0;
    targets[&"crickets"] = (calm * clampf((Weather.temperature - 9.0) / 6.0, 0.0, 1.0)) if (night and not Climate.is_dormant()) else 0.0;

# The share of water in the ground round the point the camera looks at, scaled down as the view rises.
func _look_at_water() -> float:
    var cam:Camera3D = get_viewport().get_camera_3d();
    if cam == null or world.terrain == null:
        return 0.0;
    var forward:Vector3 = -cam.global_transform.basis.z;
    var ground:Vector3 = cam.global_position;
    if forward.y < -0.05:
        ground = cam.global_position + forward * (cam.global_position.y / -forward.y);
    var centre:Vector2i = Vector2i(floori(ground.x), floori(ground.z));
    var wet:int = 0;
    var seen:int = 0;
    for dz in range(-WATER_SEEN_RADIUS, WATER_SEEN_RADIUS + 1, 3):
        for dx in range(-WATER_SEEN_RADIUS, WATER_SEEN_RADIUS + 1, 3):
            var c:Vector2i = centre + Vector2i(dx, dz);
            if c.x < 0 or c.y < 0 or c.x >= Terrain.SIZE or c.y >= Terrain.SIZE:
                continue;
            seen += 1;
            if world.terrain.is_water(c):
                wet += 1;
    var share:float = float(wet) / maxf(1.0, float(seen));
    return share * clampf(1.4 - cam.global_position.y / 70.0, 0.25, 1.0);
