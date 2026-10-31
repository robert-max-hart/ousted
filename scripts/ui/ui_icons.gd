# ----------------------------------------------------------------
# UIIcons
#     Every small icon in the interface, as asset files: the button
#     glyphs (tools, build categories, panel toggles, professions) in
#     assets/icons/ui and the top bar's stock icons (also the idle mark
#     over citizens) in assets/icons/stock. Each is <id>.svg, imported at
#     the size in the file; a <id>.png beside it takes precedence, so an
#     artist can replace any icon without touching code. Ids are unique
#     across those two folders. The build menu's icons, one per building
#     def id (and `road`), are in assets/icons/buildings, drawn by hand:
#     building(id). tools/make_icons.py regenerates the SVGs.
#     texture(id) caches the loaded file.
# ----------------------------------------------------------------
class_name UIIcons extends RefCounted;

const SIZE:int = 18;           # the size the button glyphs are made at (and the room buttons leave for them)
const BUILDING_DIR:String = "res://assets/icons/buildings/";
const DIRS:Array[String] = ["res://assets/icons/ui/", "res://assets/icons/stock/"];

static var _cache:Dictionary = {};

# The icon for `id`: a PNG if there is one, else the SVG; null (no icon, and a warning) when neither exists.
static func texture(id:StringName) -> Texture2D:
    if not _cache.has(id):
        _cache[id] = _load(id);
    return _cache[id];

# The build-menu icon for a building def id, or for `road`.
static func building(id:StringName) -> Texture2D:
    var key:String = "building:" + id;
    if not _cache.has(key):
        _cache[key] = _load(id, [BUILDING_DIR]);
    return _cache[key];

static func _load(id:StringName, dirs:Array = DIRS) -> Texture2D:
    for ext in ["png", "svg"]:
        for dir in dirs:
            var path:String = "%s%s.%s" % [dir, id, ext];
            if ResourceLoader.exists(path):
                return load(path) as Texture2D;
    push_warning("No icon file for '%s'" % id);
    return null;

# The glyph that goes with a button's label (a trailing " >" is ignored), or &"" for none.
const BY_LABEL:Dictionary = {
    "Select": &"arrow", "Harvest": &"axe", "Forage": &"basket", "Plant trees": &"sapling", "Channel": &"trench",
    "Demolish": &"hammer", "Cancel": &"cross",
    "Housing": &"house", "Storage": &"crate", "Food": &"wheat", "Industry": &"anvil", "Civic": &"flag",
    "Jobs": &"person", "Citizens": &"people", "Log": &"scroll", "Policies": &"tablet",
    "Soil": &"soil", "Water": &"drop", "Slope": &"slope",
    "Laborer": &"person", "Builder": &"hammer", "Farmer": &"wheat", "Woodcutter": &"axe", "Miner": &"pick",
    "Blacksmith": &"anvil", "Teacher": &"book", "Forager": &"basket", "Artisan": &"spool", "Fisherman": &"fish",
};

static func for_label(label:String) -> StringName:
    return BY_LABEL.get(label.trim_suffix(" >"), &"");

# Puts the glyph for `label` on a button, if there is one.
static func decorate(b:Button, label:String) -> void:
    var id:StringName = for_label(label);
    if id != &"":
        b.icon = texture(id);
        b.add_theme_constant_override("h_separation", 5);

static func has(id:StringName) -> bool:
    return texture(id) != null;

# The stock icons: the top bar's figures and the idle mark.
const STOCK_IDS:Array[StringName] = [&"wood", &"firewood", &"coal", &"stone", &"iron", &"food", &"pop", &"idle", &"homeless"];

# Every button glyph that ships (the icon sheet test draws these).
const IDS:Array[StringName] = [
    &"arrow", &"axe", &"basket", &"sapling", &"trench", &"hammer", &"cross",
    &"house", &"crate", &"wheat", &"anvil", &"flag",
    &"people", &"person", &"scroll", &"tablet", &"drop", &"slope", &"soil",
    &"pick", &"book", &"fish", &"spool",
];
