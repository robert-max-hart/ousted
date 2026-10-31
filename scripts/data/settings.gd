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

static var grass      :int  = 2;
static var shadows    :bool = true;
static var fullscreen :bool = false;
static var vsync      :bool = true;
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
    fullscreen = bool(cfg.get_value("window", "fullscreen", fullscreen));
    vsync = bool(cfg.get_value("window", "vsync", vsync));

static func save() -> void:
    var cfg:ConfigFile = ConfigFile.new();
    cfg.set_value("graphics", "grass", grass);
    cfg.set_value("graphics", "shadows", shadows);
    cfg.set_value("window", "fullscreen", fullscreen);
    cfg.set_value("window", "vsync", vsync);
    cfg.save(PATH);

static func grass_share() -> float:
    ensure_loaded();
    return GRASS_SHARES[grass];

static func shadows_on() -> bool:
    ensure_loaded();
    return shadows;

# Changes one setting ("grass", "shadows", "fullscreen" or "vsync"), saves and applies it.
static func set_value(key:String, value:Variant) -> void:
    ensure_loaded();
    match key:
        "grass": grass = clampi(int(value), 0, GRASS_NAMES.size() - 1);
        "shadows": shadows = bool(value);
        "fullscreen": fullscreen = bool(value);
        "vsync": vsync = bool(value);
        _: return;
    save();
    apply();

# Pushes the settings to the window and, if a world is running, to its grass and lights.
static func apply() -> void:
    ensure_loaded();
    apply_window();
    var w:World = World.instance;
    if w != null and is_instance_valid(w):
        if w.visuals != null:
            w.visuals.apply_settings();
        for c in w.get_children():
            if c is GrassDetail:
                (c as GrassDetail).reload();

static func apply_window() -> void:
    ensure_loaded();
    DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED);
    DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED);
