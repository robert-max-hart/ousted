# ----------------------------------------------------------------
# Settings
#     The player's graphics and window choices, kept in
#     user://settings.cfg (separate from saved games). Static: read it
#     anywhere, change it through set_value, which saves and applies.
# ----------------------------------------------------------------
class_name Settings extends RefCounted;

const PATH:String = "user://settings.cfg";

# Grass density choices: name and share of GrassDetail.DENSITY.
const GRASS_NAMES :Array[String] = ["Off", "Low", "Normal", "Dense"];
const GRASS_SHARES:Array[float]  = [0.0, 0.4, 1.0, 1.4];

# Water detail: a flat tint; swells and one ripple layer; everything (two ripple layers and foam).
const WATER_NAMES:Array[String] = ["Simple", "Medium", "Full"];

# How far away trees, bushes, rocks and crops are drawn (metres from the camera; 0 is no limit), and which set of models: the full
# one or the reduced one with fewer sides, stalks and leaves (assets/models/<set>_low, see tools/make_models.py; ModelDetail swaps the world).
const DISTANCE_NAMES:Array[String] = ["Near", "Normal", "Far"];
const DISTANCES:Array[float] = [60.0, 110.0, 0.0];
const DETAIL_NAMES:Array[String] = ["Full", "Reduced"];

static var grass      :int  = 2;
static var tree_distance:int = 2;
static var model_detail:int = 0;
static var water      :int  = 2;
static var sway       :bool = true;       # trees, bushes and hazel
static var grass_sway :bool = true;
static var ground     :bool = true;       # ground grain and rock strata
static var snow_edge  :bool = true;       # ragged, patchy snow edges
static var wispy_clouds:bool = true;     # dithered, broken-up edges on the cloud bank round the map
static var shadows    :bool = true;
static var mute_unfocused:bool = true;     # silence while the window is behind another
static var volume_master :int = 80;      # 0 to 100
static var volume_sfx    :int = 80;
static var volume_ambient:int = 60;
static var volume_music  :int = 60;       # the background music (MusicPlayer)
static var fullscreen :bool = false;
static var vsync      :bool = true;
# The window's size when it is not fullscreen: one of WINDOW_SIZES; (0, 0) leaves the window as the engine opens it.
static var window_w   :int = 0;
static var window_h   :int = 0;
const WINDOW_SIZES:Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)];
static var _loaded    :bool = false;

# --------------------------------
static func ensure_loaded() -> void:
    if _loaded:
        return;
    _loaded = true;
    var cfg:ConfigFile = ConfigFile.new();
    if cfg.load(PATH) != OK:
        return;
    grass = clampi(int(cfg.get_value("graphics", "grass", grass)), 0, GRASS_NAMES.size() - 1);
    shadows = bool(cfg.get_value("graphics", "shadows", shadows));
    volume_master = clampi(int(cfg.get_value("audio", "master", volume_master)), 0, 100);
    volume_sfx = clampi(int(cfg.get_value("audio", "sfx", volume_sfx)), 0, 100);
    volume_ambient = clampi(int(cfg.get_value("audio", "ambient", volume_ambient)), 0, 100);
    volume_music = clampi(int(cfg.get_value("audio", "music", volume_music)), 0, 100);
    water = clampi(int(cfg.get_value("graphics", "water", water)), 0, WATER_NAMES.size() - 1);
    tree_distance = clampi(int(cfg.get_value("graphics", "tree_distance", tree_distance)), 0, DISTANCE_NAMES.size() - 1);
    model_detail = clampi(int(cfg.get_value("graphics", "model_detail", model_detail)), 0, DETAIL_NAMES.size() - 1);
    sway = bool(cfg.get_value("graphics", "sway", sway));
    grass_sway = bool(cfg.get_value("graphics", "grass_sway", grass_sway));
    ground = bool(cfg.get_value("graphics", "ground", ground));
    snow_edge = bool(cfg.get_value("graphics", "snow_edge", snow_edge));
    wispy_clouds = bool(cfg.get_value("graphics", "wispy_clouds", wispy_clouds));
    mute_unfocused = bool(cfg.get_value("audio", "mute_unfocused", mute_unfocused));
    fullscreen = bool(cfg.get_value("window", "fullscreen", fullscreen));
    vsync = bool(cfg.get_value("window", "vsync", vsync));
    window_w = clampi(int(cfg.get_value("window", "width", window_w)), 0, 16384);
    window_h = clampi(int(cfg.get_value("window", "height", window_h)), 0, 16384);

static func save() -> void:
    var cfg:ConfigFile = ConfigFile.new();
    cfg.set_value("graphics", "grass", grass);
    cfg.set_value("graphics", "shadows", shadows);
    cfg.set_value("audio", "master", volume_master);
    cfg.set_value("audio", "sfx", volume_sfx);
    cfg.set_value("audio", "ambient", volume_ambient);
    cfg.set_value("audio", "music", volume_music);
    cfg.set_value("graphics", "water", water);
    cfg.set_value("graphics", "tree_distance", tree_distance);
    cfg.set_value("graphics", "model_detail", model_detail);
    cfg.set_value("graphics", "sway", sway);
    cfg.set_value("graphics", "grass_sway", grass_sway);
    cfg.set_value("graphics", "ground", ground);
    cfg.set_value("graphics", "snow_edge", snow_edge);
    cfg.set_value("graphics", "wispy_clouds", wispy_clouds);
    cfg.set_value("audio", "mute_unfocused", mute_unfocused);
    cfg.set_value("window", "fullscreen", fullscreen);
    cfg.set_value("window", "vsync", vsync);
    cfg.set_value("window", "width", window_w);
    cfg.set_value("window", "height", window_h);
    cfg.save(PATH);

static func grass_share() -> float:
    ensure_loaded();
    return GRASS_SHARES[grass];

static func shadows_on() -> bool:
    ensure_loaded();
    return shadows;

# The draw distance for trees, bushes, rocks and crops in metres (0: no limit).
static func draw_distance() -> float:
    ensure_loaded();
    return DISTANCES[tree_distance];

static func models_reduced() -> bool:
    ensure_loaded();
    return model_detail == 1;

# The folder of a model set at the chosen detail ("res://assets/models/trees/" or its "_low" sibling).
static func model_dir(base:String) -> String:
    return base.trim_suffix("/") + "_low/" if models_reduced() else base;

static func sway_on() -> bool:
    ensure_loaded();
    return sway;

static func grass_sway_on() -> bool:
    ensure_loaded();
    return grass_sway;

static func ground_on() -> bool:
    ensure_loaded();
    return ground;

static func wispy_clouds_on() -> bool:
    ensure_loaded();
    return wispy_clouds;

static func snow_shading_on() -> bool:
    ensure_loaded();
    return snow_edge;

# Changes one setting ("tree_distance", "model_detail", "volume_master", "volume_sfx", "volume_ambient", "volume_music", "grass", "shadows", "water", "sway", "grass_sway", "ground", "snow_edge", "wispy_clouds", "mute_unfocused", "fullscreen", "vsync" or "window_size" (a Vector2i)), saves and applies it.
static func set_value(key:String, value:Variant) -> void:
    ensure_loaded();
    match key:
        "grass": grass = clampi(int(value), 0, GRASS_NAMES.size() - 1);
        "shadows": shadows = bool(value);
        "volume_master": volume_master = clampi(int(value), 0, 100);
        "volume_sfx": volume_sfx = clampi(int(value), 0, 100);
        "volume_ambient": volume_ambient = clampi(int(value), 0, 100);
        "volume_music": volume_music = clampi(int(value), 0, 100);
        "water": water = clampi(int(value), 0, WATER_NAMES.size() - 1);
        "tree_distance": tree_distance = clampi(int(value), 0, DISTANCE_NAMES.size() - 1);
        "model_detail": model_detail = clampi(int(value), 0, DETAIL_NAMES.size() - 1);
        "sway": sway = bool(value);
        "grass_sway": grass_sway = bool(value);
        "ground": ground = bool(value);
        "snow_edge": snow_edge = bool(value);
        "wispy_clouds": wispy_clouds = bool(value);
        "mute_unfocused": mute_unfocused = bool(value);
        "fullscreen": fullscreen = bool(value);
        "vsync": vsync = bool(value);
        "window_size":
            var v:Vector2i = value;
            window_w = clampi(v.x, 0, 16384);
            window_h = clampi(v.y, 0, 16384);
        _: return;
    save();
    apply();
    if key == "window_size" or key == "fullscreen":
        apply_window(true);          # (only these resize the window: any other change leaves a hand-dragged window as it is)

# Pushes the settings to the window and, if a world is running, to its grass, lights and shaders.
static func apply() -> void:
    ensure_loaded();
    apply_window(false);
    Sfx.apply_volumes();
    var w:World = World.instance;
    CropMeshes.reload_if_needed();
    ModelDetail.apply(w);
    if w != null and is_instance_valid(w):
        if w.renderer != null:
            w.renderer.apply_settings();
        for b in w.buildings:
            if b is Field:
                (b as Field).apply_settings();
        if w.visuals != null:
            w.visuals.apply_settings();
        for c in w.get_children():
            if c is GrassDetail:
                (c as GrassDetail).reload();
            elif c is GroundPlants:
                (c as GroundPlants).reload();

# Fullscreen, vsync and, with `resize` (at start-up and when the size or fullscreen is changed), the window's size.
static func apply_window(resize:bool = true) -> void:
    ensure_loaded();
    DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED);
    DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED);
    if resize and not fullscreen and window_w > 0 and window_h > 0:
        var screen:Vector2i = DisplayServer.screen_get_size();
        if screen.x <= 0 or screen.y <= 0:
            return;          # (no screen to measure against: a headless run)
        var size:Vector2i = Vector2i(mini(window_w, screen.x), mini(window_h, screen.y));
        DisplayServer.window_set_size(size);
        var at:Vector2i = DisplayServer.screen_get_position() + (screen - size) / 2;
        DisplayServer.window_set_position(Vector2i(at.x, maxi(at.y, DisplayServer.screen_get_position().y)));

# The sizes the window can be set to: the presets that fit this screen, and the saved one if it is not a preset.
static func window_size_choices() -> Array[Vector2i]:
    ensure_loaded();
    var screen:Vector2i = DisplayServer.screen_get_size();
    var out:Array[Vector2i] = [];
    for v in WINDOW_SIZES:
        if screen.x <= 0 or (v.x <= screen.x and v.y <= screen.y):          # (a headless run has no screen to measure: offer them all)
            out.append(v);
    if window_w > 0 and not out.has(Vector2i(window_w, window_h)):
        out.append(Vector2i(window_w, window_h));
        out.sort_custom(func(a:Vector2i, b:Vector2i) -> bool: return a.x < b.x);
    return out;
