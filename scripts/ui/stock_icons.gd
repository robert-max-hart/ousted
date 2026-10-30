# ----------------------------------------------------------------
# StockIcons
#     Small icons drawn in code (placeholders until the art pass) for
#     the top bar's stock figures and the idle mark over citizens.
#     Each is painted at 4x size from a few shapes and scaled down,
#     which gives soft edges. texture(id) caches them.
# ----------------------------------------------------------------
class_name StockIcons extends RefCounted;

const SIZE   :int = 22;
const BIG    :int = 88;       # the working size, scaled down to SIZE at the end
const OUTLINE:Color = Color(0.08, 0.07, 0.06, 0.9);

static var _cache:Dictionary = {};

static func texture(id:StringName) -> Texture2D:
    if not _cache.has(id):
        _cache[id] = _make(id);
    return _cache[id];

# --------------------------------
# Drawing helpers (coordinates are 0..1 across the icon)

static func _px(v:float) -> int:
    return roundi(v * BIG);

static func _rect(img:Image, x:float, y:float, w:float, h:float, c:Color) -> void:
    for yy in range(_px(y), _px(y + h)):
        for xx in range(_px(x), _px(x + w)):
            _put(img, xx, yy, c);

static func _ellipse(img:Image, cx:float, cy:float, rx:float, ry:float, c:Color) -> void:
    for yy in range(_px(cy - ry), _px(cy + ry) + 1):
        for xx in range(_px(cx - rx), _px(cx + rx) + 1):
            var dx:float = (float(xx) / BIG - cx) / rx;
            var dy:float = (float(yy) / BIG - cy) / ry;
            if dx * dx + dy * dy <= 1.0:
                _put(img, xx, yy, c);

static func _poly(img:Image, pts:PackedVector2Array, c:Color) -> void:
    var lo:Vector2 = pts[0];
    var hi:Vector2 = pts[0];
    for p in pts:
        lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y));
        hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y));
    for yy in range(_px(lo.y), _px(hi.y) + 1):
        for xx in range(_px(lo.x), _px(hi.x) + 1):
            if Geometry2D.is_point_in_polygon(Vector2(float(xx) / BIG, float(yy) / BIG), pts):
                _put(img, xx, yy, c);

static func _put(img:Image, x:int, y:int, c:Color) -> void:
    if x >= 0 and y >= 0 and x < BIG and y < BIG:
        img.set_pixel(x, y, c);

# Every filled pixel gets a dark ring around it (done last, so the icon reads on any background).
static func _outline(img:Image) -> void:
    var src:Image = img.duplicate();
    for y in BIG:
        for x in BIG:
            if src.get_pixel(x, y).a > 0.01:
                continue;
            var near:bool = false;
            for d in [Vector2i(-3, 0), Vector2i(3, 0), Vector2i(0, -3), Vector2i(0, 3), Vector2i(-2, -2), Vector2i(2, 2), Vector2i(-2, 2), Vector2i(2, -2)]:
                var nx:int = x + d.x;
                var ny:int = y + d.y;
                if nx >= 0 and ny >= 0 and nx < BIG and ny < BIG and src.get_pixel(nx, ny).a > 0.01:
                    near = true;
                    break;
            if near:
                img.set_pixel(x, y, OUTLINE);

# --------------------------------
# The icons

static func _make(id:StringName) -> Texture2D:
    var img:Image = Image.create(BIG, BIG, false, Image.FORMAT_RGBA8);
    img.fill(Color(0, 0, 0, 0));
    match id:
        &"wood":         # a log lying down, its end showing rings
            _rect(img, 0.12, 0.34, 0.62, 0.36, Color(0.52, 0.34, 0.18));
            _rect(img, 0.12, 0.34, 0.62, 0.08, Color(0.64, 0.44, 0.24));
            _ellipse(img, 0.74, 0.52, 0.17, 0.2, Color(0.82, 0.64, 0.4));
            _ellipse(img, 0.74, 0.52, 0.1, 0.12, Color(0.68, 0.48, 0.28));
            _ellipse(img, 0.74, 0.52, 0.04, 0.05, Color(0.82, 0.64, 0.4));
        &"firewood":     # a small stack of split logs
            for row in [[0.1, 0.62], [0.42, 0.62], [0.26, 0.34]]:
                _rect(img, row[0], row[1], 0.32, 0.26, Color(0.74, 0.5, 0.26));
                _rect(img, row[0], row[1], 0.32, 0.07, Color(0.88, 0.66, 0.38));
                _ellipse(img, row[0] + 0.32, row[1] + 0.13, 0.05, 0.13, Color(0.9, 0.74, 0.5));
        &"coal":         # dark lumps with a glint
            _poly(img, PackedVector2Array([Vector2(0.1, 0.78), Vector2(0.18, 0.46), Vector2(0.42, 0.36), Vector2(0.56, 0.6), Vector2(0.5, 0.82)]), Color(0.2, 0.2, 0.23));
            _poly(img, PackedVector2Array([Vector2(0.42, 0.8), Vector2(0.5, 0.3), Vector2(0.74, 0.2), Vector2(0.9, 0.5), Vector2(0.84, 0.82)]), Color(0.28, 0.28, 0.32));
            _rect(img, 0.55, 0.3, 0.1, 0.06, Color(0.62, 0.64, 0.72));
            _rect(img, 0.2, 0.5, 0.07, 0.05, Color(0.5, 0.52, 0.6));
        &"stone":        # a grey boulder
            _poly(img, PackedVector2Array([Vector2(0.1, 0.78), Vector2(0.14, 0.48), Vector2(0.36, 0.26), Vector2(0.68, 0.24), Vector2(0.9, 0.5), Vector2(0.9, 0.78)]), Color(0.55, 0.55, 0.52));
            _poly(img, PackedVector2Array([Vector2(0.14, 0.48), Vector2(0.36, 0.26), Vector2(0.68, 0.24), Vector2(0.5, 0.44)]), Color(0.72, 0.72, 0.68));
            _poly(img, PackedVector2Array([Vector2(0.5, 0.44), Vector2(0.9, 0.5), Vector2(0.9, 0.78), Vector2(0.5, 0.78)]), Color(0.42, 0.42, 0.4));
        &"iron":         # an ingot with a blue-grey sheen
            _poly(img, PackedVector2Array([Vector2(0.06, 0.74), Vector2(0.22, 0.38), Vector2(0.82, 0.38), Vector2(0.94, 0.74)]), Color(0.5, 0.56, 0.64));
            _poly(img, PackedVector2Array([Vector2(0.22, 0.38), Vector2(0.82, 0.38), Vector2(0.78, 0.5), Vector2(0.2, 0.5)]), Color(0.78, 0.84, 0.9));
            _rect(img, 0.06, 0.66, 0.88, 0.1, Color(0.36, 0.4, 0.48));
        &"food":         # a loaf: golden bread with a slash
            _ellipse(img, 0.5, 0.58, 0.42, 0.28, Color(0.82, 0.58, 0.26));
            _ellipse(img, 0.5, 0.5, 0.38, 0.2, Color(0.92, 0.7, 0.36));
            for x in [0.3, 0.5, 0.7]:
                _poly(img, PackedVector2Array([Vector2(x - 0.04, 0.58), Vector2(x, 0.4), Vector2(x + 0.06, 0.44), Vector2(x + 0.02, 0.6)]), Color(0.7, 0.44, 0.18));
        &"pop":          # a person: head and shoulders
            _ellipse(img, 0.5, 0.28, 0.17, 0.2, Color(0.9, 0.74, 0.58));
            _poly(img, PackedVector2Array([Vector2(0.14, 0.9), Vector2(0.18, 0.62), Vector2(0.34, 0.5), Vector2(0.66, 0.5), Vector2(0.82, 0.62), Vector2(0.86, 0.9)]), Color(0.36, 0.56, 0.78));
        &"idle":         # a speech bubble with three dots
            _rect(img, 0.08, 0.16, 0.84, 0.5, Color(1.0, 0.9, 0.5));
            _ellipse(img, 0.08, 0.41, 0.07, 0.25, Color(1.0, 0.9, 0.5));
            _ellipse(img, 0.92, 0.41, 0.07, 0.25, Color(1.0, 0.9, 0.5));
            _poly(img, PackedVector2Array([Vector2(0.24, 0.62), Vector2(0.4, 0.62), Vector2(0.2, 0.88)]), Color(1.0, 0.9, 0.5));
            for x in [0.3, 0.5, 0.7]:
                _ellipse(img, x, 0.41, 0.06, 0.08, Color(0.45, 0.32, 0.1));
        &"homeless":     # a house with a red cross over it
            _rect(img, 0.22, 0.46, 0.56, 0.42, Color(0.7, 0.62, 0.5));
            _poly(img, PackedVector2Array([Vector2(0.1, 0.5), Vector2(0.5, 0.14), Vector2(0.9, 0.5)]), Color(0.62, 0.3, 0.24));
            _poly(img, PackedVector2Array([Vector2(0.62, 0.62), Vector2(0.72, 0.52), Vector2(0.96, 0.78), Vector2(0.86, 0.88)]), Color(0.95, 0.3, 0.25));
            _poly(img, PackedVector2Array([Vector2(0.86, 0.52), Vector2(0.96, 0.62), Vector2(0.72, 0.88), Vector2(0.62, 0.78)]), Color(0.95, 0.3, 0.25));
        _:
            _ellipse(img, 0.5, 0.5, 0.35, 0.35, Color(0.7, 0.7, 0.7));
    _outline(img);
    img.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS);
    return ImageTexture.create_from_image(img);
