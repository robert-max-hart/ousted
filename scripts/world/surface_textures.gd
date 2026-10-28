# ----------------------------------------------------------------
# SurfaceTextures
#     Small tileable textures made in code (planks, stone blocks,
#     plaster, shingles) for building walls and roofs. They are pale
#     greys, so a building's own colour tints them. Materials use
#     them triplanar, so no mesh needs UVs.
# ----------------------------------------------------------------
class_name SurfaceTextures extends RefCounted;

const SIZE          :int = 128;
const METRES        :float = 2.5;          # world size one tile covers
const KINDS         :Array[StringName] = [&"planks", &"stone", &"plaster", &"shingle"];

static var _cache   :Dictionary = {};

# A building material with the texture applied triplanar; tint is the albedo colour.
static func material(kind:StringName, tint:Color) -> StandardMaterial3D:
    var m:StandardMaterial3D = StandardMaterial3D.new();
    m.albedo_color = tint;
    m.albedo_texture = texture(kind);
    m.uv1_triplanar = true;
    m.uv1_scale = Vector3.ONE / METRES;
    m.roughness = 0.9;
    return m;

static func texture(kind:StringName) -> ImageTexture:
    if not _cache.has(kind):
        var img:Image = Image.create(SIZE, SIZE, true, Image.FORMAT_RGB8);
        for y in SIZE:
            for x in SIZE:
                img.set_pixel(x, y, _pixel(kind, x, y));
        img.generate_mipmaps();
        _cache[kind] = ImageTexture.create_from_image(img);
    return _cache[kind];

# A cheap repeatable hash in 0..1 for a cell (a, b) of a given layer.
static func _h(a:int, b:int, layer:int) -> float:
    return float(hash(Vector3i(a, b, layer)) & 0xffff) / 65535.0;

static func _grey(v:float) -> Color:
    v = clampf(v, 0.0, 1.0);
    return Color(v, v, v);

static func _pixel(kind:StringName, x:int, y:int) -> Color:
    var grain:float = _h(x, y, 1) * 0.06;
    match kind:
        &"planks":
            var board:int = x / 16;
            var shade:float = 0.80 + _h(board, 0, 2) * 0.18;
            var streak:float = _h(x, y / 6, 3) * 0.08;       # long vertical grain
            var seam:float = 0.55 if x % 16 == 0 else 1.0;
            return _grey((shade - streak - grain) * seam);
        &"stone":
            var row:int = y / 32;
            var off:int = 0 if row % 2 == 0 else 22;
            var bx:int = (x + off) % 64;
            var block:int = (x + off) / 64;
            var shade:float = 0.72 + _h(block, row, 4) * 0.26;
            var mortar:bool = y % 32 < 3 or bx < 3;
            return _grey(0.45 if mortar else shade - grain * 1.5);
        &"shingle":
            var row2:int = y / 16;
            var off2:int = 0 if row2 % 2 == 0 else 12;
            var tx:int = (x + off2) % 24;
            var tile:int = (x + off2) / 24;
            var shade2:float = 0.74 + _h(tile, row2, 5) * 0.24;
            var edge:float = 0.6 if y % 16 > 12 else 1.0;     # shadow under each course
            return _grey((shade2 - grain) * edge * (0.7 if tx == 0 else 1.0));
        _:
            return _grey(0.92 - _h(x / 2, y / 2, 6) * 0.1 - grain);
