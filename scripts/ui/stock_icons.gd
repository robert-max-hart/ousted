# ----------------------------------------------------------------
# StockIcons
#     The icons for the top bar's stock figures and the idle mark over
#     citizens: asset files, assets/icons/stock/<id>.svg (a <id>.png
#     beside one takes precedence). Ids: wood, firewood, coal, stone,
#     iron, food, pop, idle, homeless. texture(id) caches the loaded file.
# ----------------------------------------------------------------
class_name StockIcons extends RefCounted;

const SIZE:int = 22;           # the size the SVGs are made at
const DIR :String = "res://assets/icons/stock/";

static var _cache:Dictionary = {};

static func texture(id:StringName) -> Texture2D:
    if not _cache.has(id):
        _cache[id] = AssetIcons.load_icon(DIR, id);
    return _cache[id];
