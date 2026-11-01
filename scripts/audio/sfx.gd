# ----------------------------------------------------------------
# Sfx
#     Sound effects (assets/audio/sfx, made by tools/make_sounds.py),
#     played through pools of players kept under the scene tree's root
#     so they survive scene changes. ui(id) plays a flat sound,
#     at(id, position) plays one in the world (it fades with distance
#     from the camera, is skipped when far away, and thins out at fast
#     game speeds so work sounds do not turn into a roar). An id with
#     variants (chop_1.wav, chop_2.wav ...) picks one at random.
#     Also owns the audio buses (Sfx, Ambient, Music under Master) and
#     their volumes from Settings, and hooks a click onto every button.
# ----------------------------------------------------------------
class_name Sfx extends RefCounted;

const DIR       :String = "res://assets/audio/sfx/";
const BUS_SFX   :StringName = &"Sfx";
const BUS_AMBIENT:StringName = &"Ambient";
const BUS_MUSIC :StringName = &"Music";
const POOL_UI   :int = 4;
const POOL_WORLD:int = 12;
const HEARD_WITHIN:float = 70.0;       # metres from the camera; farther work is silent
const GAP_UI_MS :int = 40;             # the least time between two plays of the same id
const GAP_WORLD_MS:int = 90;

static var _variants:Dictionary = {};
static var _holder  :Node;
static var _flat    :Array[AudioStreamPlayer] = [];
static var _world   :Array[AudioStreamPlayer3D] = [];
static var _last_ms :Dictionary = {};
static var _hooked  :bool = false;
static var _focused :bool = true;

# --------------------------------
# Buses and volumes

# Makes the Sfx, Ambient and Music buses if they are missing.
static func ensure_buses() -> void:
    for bus in [BUS_SFX, BUS_AMBIENT, BUS_MUSIC]:
        if AudioServer.get_bus_index(bus) == -1:
            AudioServer.add_bus();
            var i:int = AudioServer.bus_count - 1;
            AudioServer.set_bus_name(i, bus);
            AudioServer.set_bus_send(i, &"Master");

# Sets the bus volumes from Settings (0 to 100 each; 0 mutes).
static func apply_volumes() -> void:
    ensure_buses();
    _set_bus(&"Master", 0 if (not _focused and Settings.mute_unfocused) else Settings.volume_master);       # (a window that lost focus is silent, if the player wants)
    _set_bus(BUS_SFX, Settings.volume_sfx);
    _set_bus(BUS_AMBIENT, Settings.volume_ambient);
    _set_bus(BUS_MUSIC, Settings.volume_music);

static func _set_bus(bus:StringName, percent:int) -> void:
    var i:int = AudioServer.get_bus_index(bus);
    if i == -1:
        return;
    AudioServer.set_bus_mute(i, percent <= 0);
    AudioServer.set_bus_volume_db(i, linear_to_db(maxf(percent / 100.0, 0.0001)));

# --------------------------------
# Playing

static func has(id:StringName) -> bool:
    return not _streams(id).is_empty();

# A flat sound (interface and events). Returns whether it started.
static func ui(id:StringName) -> bool:
    if not _ready_to_play() or Settings.volume_sfx <= 0 or _too_soon(id, GAP_UI_MS):
        return false;
    var s:AudioStream = _pick(id);
    if s == null:
        return false;
    for p in _flat:
        if not p.playing:
            p.stream = s;
            p.volume_db = 0.0;
            p.pitch_scale = 1.0;
            p.play();
            return true;
    return false;

# A sound at a place in the world. `volume_db` makes it softer, `reach` is how far from the camera (plus the camera's height, so a zoomed-out view
# hears more of the map) it can be heard, and `gap_ms` the least time between two plays of the same id. Returns whether it started.
static func at(id:StringName, position:Vector3, pitch_jitter:float = 0.06, volume_db:float = 0.0, reach:float = HEARD_WITHIN, gap_ms:int = GAP_WORLD_MS) -> bool:
    if not _ready_to_play() or Settings.volume_sfx <= 0 or _too_soon(id, gap_ms):
        return false;
    var cam:Camera3D = _holder.get_viewport().get_camera_3d();
    if cam == null or cam.global_position.distance_to(position) > reach + cam.global_position.y:
        return false;
    var speed:float = GameClock.speed();
    if speed > 2.5 and randf() > 2.5 / speed:          # at 5x and 10x only a share of the strikes sound
        return false;
    var s:AudioStream = _pick(id);
    if s == null:
        return false;
    for p in _world:
        if not p.playing:
            p.stream = s;
            p.global_position = position;
            p.volume_db = volume_db;
            p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter);
            p.play();
            return true;
    return false;

# Every button anywhere in the tree clicks when pressed (and so does one made later).
static func hook_buttons(tree:SceneTree) -> void:
    _ready_to_play();          # (also starts the holder that hears the window lose focus)
    if _hooked:
        return;
    _hooked = true;
    tree.node_added.connect(func(n:Node) -> void:
        if n is BaseButton and not n.has_meta(&"sfx_hooked"):
            n.set_meta(&"sfx_hooked", true);
            (n as BaseButton).pressed.connect(func() -> void: Sfx.ui(&"click")));

# The window gained or lost focus (SfxHolder tells us): with Settings.mute_unfocused the game goes quiet while another window is in front.
static func on_focus(focused:bool) -> void:
    _focused = focused;
    apply_volumes();

# --------------------------------
# Internals

static func _ready_to_play() -> bool:
    if _holder == null or not is_instance_valid(_holder):
        var tree:SceneTree = Engine.get_main_loop() as SceneTree;
        if tree == null:
            return false;
        ensure_buses();
        apply_volumes();
        _holder = SfxHolder.new();
        _holder.name = "Sfx";
        _flat.clear();
        _world.clear();
        for i in POOL_UI:
            var p:AudioStreamPlayer = AudioStreamPlayer.new();
            p.bus = BUS_SFX;
            _holder.add_child(p);
            _flat.append(p);
        for i in POOL_WORLD:
            var q:AudioStreamPlayer3D = AudioStreamPlayer3D.new();
            q.bus = BUS_SFX;
            q.unit_size = 14.0;
            q.max_distance = HEARD_WITHIN + 20.0;
            q.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE;
            _holder.add_child(q);
            _world.append(q);
        tree.root.add_child.call_deferred(_holder);
    return _holder.is_inside_tree();

static func _too_soon(id:StringName, gap_ms:int) -> bool:
    var now:int = Time.get_ticks_msec();
    if now - int(_last_ms.get(id, -100000)) < gap_ms:
        return true;
    _last_ms[id] = now;
    return false;

static func _pick(id:StringName) -> AudioStream:
    var list:Array = _streams(id);
    if list.is_empty():
        return null;
    return list[randi() % list.size()];

# The streams for an id: <id>.wav, or <id>_1.wav, <id>_2.wav ... (loaded once).
static func _streams(id:StringName) -> Array:
    if not _variants.has(id):
        var list:Array = [];
        var single:String = "%s%s.wav" % [DIR, id];
        if ResourceLoader.exists(single):
            list.append(load(single));
        else:
            var n:int = 1;
            while ResourceLoader.exists("%s%s_%d.wav" % [DIR, id, n]):
                list.append(load("%s%s_%d.wav" % [DIR, id, n]));
                n += 1;
        if list.is_empty():
            push_warning("No sound file for '%s'" % id);
        _variants[id] = list;
    return _variants[id];
