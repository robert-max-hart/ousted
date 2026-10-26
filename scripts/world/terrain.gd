# ----------------------------------------------------------------
# Terrain
#     Heightmap grid rendered as chunked meshes. Heights live on cell
#     corners ((SIZE+1)^2); cells carry a surface overlay (road, tilled).
#     Edits mark nearby chunks dirty and they rebuild next frame.
# ----------------------------------------------------------------
class_name Terrain extends Node3D;

signal changed(rect:Rect2i);
signal ground_changed(rect:Rect2i);       # the ground's look changed: sculpting or a road, field or site laid or removed

enum Overlay { NONE, ROAD, TILLED, SITE };

const SIZE              :int = 128;
const CHUNK             :int = 32;
const CHUNKS            :int = 4;       # SIZE / CHUNK
const WATER_LEVEL       :float = 0.0;
const MAX_HEIGHT        :float = 40.0;
const MIN_HEIGHT        :float = -6.0;

const COLOR_SAND        :Color = Color(0.74, 0.68, 0.5);
const COLOR_ROCK        :Color = Color(0.48, 0.46, 0.43);
const COLOR_ROAD        :Color = Color(0.56, 0.46, 0.33);
const COLOR_TILLED      :Color = Color(0.36, 0.25, 0.16);
const COLOR_SITE        :Color = Color(0.62, 0.52, 0.34);      # a field being dug: pale, bare soil
const COLOR_SNOW        :Color = Color(0.88, 0.9, 0.94);
const DETAIL_AMOUNT     :float = 0.055;
const DETAIL_SATURATION :float = 1.15;
const GRASS_BY_SEASON   :Array[Color] = [
    Color(0.3, 0.47, 0.2), Color(0.36, 0.47, 0.18), Color(0.5, 0.45, 0.22), Color(0.8, 0.83, 0.86),
];

var heights :PackedFloat32Array;
var overlay :PackedByteArray;
var _chunks :Array[MeshInstance3D] = [];
var _dirty  :Dictionary = {};
var _material:StandardMaterial3D;
var _season :int = 0;
var _tint_noise:FastNoiseLite;
var _detail_noise:FastNoiseLite;

func _ready() -> void:
    _material = StandardMaterial3D.new();
    _material.vertex_color_use_as_albedo = true;
    _material.vertex_color_is_srgb = true;
    _material.roughness = 1.0;
    for i in CHUNKS * CHUNKS:
        var mi:MeshInstance3D = MeshInstance3D.new();
        mi.material_override = _material;
        add_child(mi);
        _chunks.append(mi);

func _process(_delta:float) -> void:
    if _dirty.is_empty():
        return;
    for ci in _dirty:
        _build_chunk(ci);
    _dirty.clear();

# --------------------------------
# Generation

func generate(world_seed:int) -> void:
    _tint_noise = FastNoiseLite.new();
    _tint_noise.seed = world_seed + 3;
    _tint_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH;
    _tint_noise.frequency = 0.04;
    _detail_noise = FastNoiseLite.new();
    _detail_noise.seed = world_seed + 4;
    _detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH;
    _detail_noise.frequency = 0.3;
    _detail_noise.fractal_type = FastNoiseLite.FRACTAL_FBM;
    _detail_noise.fractal_octaves = 2;
    var base:FastNoiseLite = FastNoiseLite.new();
    base.seed = world_seed;
    base.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH;
    base.frequency = 0.012;
    base.fractal_octaves = 4;
    var hills_mask:FastNoiseLite = FastNoiseLite.new();
    hills_mask.seed = world_seed + 1;
    hills_mask.frequency = 0.009;
    var ridges:FastNoiseLite = FastNoiseLite.new();
    ridges.seed = world_seed + 2;
    ridges.frequency = 0.03;
    ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED;
    ridges.fractal_octaves = 3;

    var n:int = SIZE + 1;
    heights.resize(n * n);
    for z in n:
        for x in n:
            var h:float = base.get_noise_2d(x, z) * 9.0 + 2.0;
            var mask:float = clampf((hills_mask.get_noise_2d(x, z) - 0.15) * 3.0, 0.0, 1.0);
            h += mask * (ridges.get_noise_2d(x, z) * 0.5 + 0.5) * 14.0;
            heights[z * n + x] = h;
    overlay = PackedByteArray();
    overlay.resize(SIZE * SIZE);
    mark_all_dirty();

# --------------------------------
# Queries

func corner(x:int, z:int) -> float:
    x = clampi(x, 0, SIZE);
    z = clampi(z, 0, SIZE);
    return heights[z * (SIZE + 1) + x];

func set_corner(x:int, z:int, h:float) -> void:
    heights[z * (SIZE + 1) + x] = clampf(h, MIN_HEIGHT, MAX_HEIGHT);

# Bilinear height at a world position.
func height_at(x:float, z:float) -> float:
    x = clampf(x, 0.0, SIZE - 0.001);
    z = clampf(z, 0.0, SIZE - 0.001);
    var ix:int = int(x);
    var iz:int = int(z);
    var fx:float = x - ix;
    var fz:float = z - iz;
    var h0:float = lerpf(corner(ix, iz), corner(ix + 1, iz), fx);
    var h1:float = lerpf(corner(ix, iz + 1), corner(ix + 1, iz + 1), fx);
    return lerpf(h0, h1, fz);

func in_bounds(c:Vector2i) -> bool:
    return c.x >= 0 and c.y >= 0 and c.x < SIZE and c.y < SIZE;

func index(c:Vector2i) -> int:
    return c.y * SIZE + c.x;

func world_to_cell(p:Vector3) -> Vector2i:
    return Vector2i(floori(p.x), floori(p.z));

func cell_height(c:Vector2i) -> float:
    return (corner(c.x, c.y) + corner(c.x + 1, c.y) + corner(c.x, c.y + 1) + corner(c.x + 1, c.y + 1)) * 0.25;

func cell_center(c:Vector2i) -> Vector3:
    return Vector3(c.x + 0.5, height_at(c.x + 0.5, c.y + 0.5), c.y + 0.5);

func cell_slope(c:Vector2i) -> float:
    var a:float = corner(c.x, c.y);
    var b:float = corner(c.x + 1, c.y);
    var d:float = corner(c.x, c.y + 1);
    var e:float = corner(c.x + 1, c.y + 1);
    return maxf(maxf(a, b), maxf(d, e)) - minf(minf(a, b), minf(d, e));

func is_water(c:Vector2i) -> bool:
    return cell_height(c) < WATER_LEVEL + 0.1;

func get_overlay(c:Vector2i) -> int:
    return overlay[index(c)];

func set_overlay(c:Vector2i, value:int) -> void:
    if overlay[index(c)] == value:
        return;
    overlay[index(c)] = value;
    _mark_dirty_rect(Rect2i(c, Vector2i.ONE));
    ground_changed.emit(Rect2i(c, Vector2i.ONE));

# Min/max corner height inside a rect, as Vector2(min, max).
func rect_height_range(r:Rect2i) -> Vector2:
    var lo:float = INF;
    var hi:float = -INF;
    for z in range(r.position.y, r.end.y + 1):
        for x in range(r.position.x, r.end.x + 1):
            var h:float = corner(x, z);
            lo = minf(lo, h);
            hi = maxf(hi, h);
    return Vector2(lo, hi);

# --------------------------------
# Editing

# Levels every corner of the rect to its average height.
func flatten_rect(r:Rect2i) -> void:
    var total:float = 0.0;
    var count:int = 0;
    for z in range(r.position.y, r.end.y + 1):
        for x in range(r.position.x, r.end.x + 1):
            total += corner(x, z);
            count += 1;
    var target:float = maxf(total / count, WATER_LEVEL + 0.3);
    for z in range(r.position.y, r.end.y + 1):
        for x in range(r.position.x, r.end.x + 1):
            set_corner(x, z, target);
    _after_edit(r.grow(1));

# Raises (amount > 0), lowers (amount < 0) or flattens toward flatten_to
# (when not NAN) with a soft circular brush. is_locked(x, z) -> bool skips corners.
func apply_brush(center:Vector3, radius:float, amount:float, flatten_to:float, is_locked:Callable) -> void:
    var r:int = ceili(radius);
    var cx:int = roundi(center.x);
    var cz:int = roundi(center.z);
    var touched:bool = false;
    for z in range(cz - r, cz + r + 1):
        for x in range(cx - r, cx + r + 1):
            if x < 0 or z < 0 or x > SIZE or z > SIZE:
                continue;
            var d:float = Vector2(x - center.x, z - center.z).length();
            if d > radius or is_locked.call(x, z):
                continue;
            var w:float = 1.0 - smoothstep(radius * 0.4, radius, d);
            var h:float = corner(x, z);
            if is_nan(flatten_to):
                set_corner(x, z, h + amount * w);
            else:
                set_corner(x, z, move_toward(h, flatten_to, absf(amount) * w));
            touched = true;
    if touched:
        _after_edit(Rect2i(cx - r - 1, cz - r - 1, r * 2 + 3, r * 2 + 3));

func _after_edit(r:Rect2i) -> void:
    r = r.intersection(Rect2i(0, 0, SIZE, SIZE));
    _mark_dirty_rect(r);
    changed.emit(r);
    ground_changed.emit(r);

# --------------------------------
# Ray picking (no physics needed)

# Returns the hit point as Vector3, or null if the ray misses.
func raycast(from:Vector3, dir:Vector3, max_dist:float = 800.0) -> Variant:
    dir = dir.normalized();
    var t:float = 0.0;
    # skip straight down to the height band the terrain can occupy
    if from.y > MAX_HEIGHT and dir.y < 0.0:
        t = (from.y - MAX_HEIGHT) / -dir.y;
    var step:float = 0.4;
    while t < max_dist:
        var p:Vector3 = from + dir * t;
        if p.x >= 0.0 and p.z >= 0.0 and p.x <= SIZE and p.z <= SIZE and p.y <= height_at(p.x, p.z):
            var lo:float = maxf(0.0, t - step);
            var hi:float = t;
            for i in 10:
                var mid:float = (lo + hi) * 0.5;
                var q:Vector3 = from + dir * mid;
                if q.y <= height_at(q.x, q.z):
                    hi = mid;
                else:
                    lo = mid;
            return from + dir * hi;
        t += step;
    return null;

# --------------------------------
# Rendering

func set_season(s:int) -> void:
    _season = s;
    mark_all_dirty();

func mark_all_dirty() -> void:
    for i in CHUNKS * CHUNKS:
        _dirty[i] = true;

@warning_ignore("integer_division")
func _mark_dirty_rect(r:Rect2i) -> void:
    # normals reach one corner further, so grow by one before mapping to chunks
    r = r.grow(1);
    var c0:Vector2i = Vector2i(clampi(r.position.x / CHUNK, 0, CHUNKS - 1), clampi(r.position.y / CHUNK, 0, CHUNKS - 1));
    var c1:Vector2i = Vector2i(clampi((r.end.x - 1) / CHUNK, 0, CHUNKS - 1), clampi((r.end.y - 1) / CHUNK, 0, CHUNKS - 1));
    for cz in range(c0.y, c1.y + 1):
        for cx in range(c0.x, c1.x + 1):
            _dirty[cz * CHUNKS + cx] = true;

func _corner_normal(x:int, z:int) -> Vector3:
    return Vector3(corner(x - 1, z) - corner(x + 1, z), 2.0, corner(x, z - 1) - corner(x, z + 1)).normalized();

func _cell_color(c:Vector2i) -> Color:
    var col:Color;
    match overlay[index(c)]:
        Overlay.ROAD:
            col = COLOR_ROAD;
        Overlay.SITE:
            col = COLOR_SITE;
        Overlay.TILLED:
            col = COLOR_SNOW.lerp(COLOR_TILLED, 0.4) if _season == GameClock.Season.WINTER else COLOR_TILLED;
        _:
            var slope:float = cell_slope(c);
            if cell_height(c) < WATER_LEVEL + 0.35:
                col = COLOR_SAND;
            elif slope > 1.4:
                col = COLOR_ROCK.lerp(COLOR_SNOW, 0.5) if _season == GameClock.Season.WINTER else COLOR_ROCK;
            else:
                col = GRASS_BY_SEASON[_season].lerp(COLOR_ROCK, clampf((slope - 0.8) / 0.6, 0.0, 1.0));
    # soft, low-frequency patches plus a faint per-cell speckle so the grid doesn't look flat
    var v:float = float(absi(hash(c)) % 1000) / 1000.0 * 0.012 - 0.006;
    if _tint_noise != null:
        v += _tint_noise.get_noise_2d(c.x, c.y) * 0.04;
    return Color(col.r + v, col.g + v, col.b + v);

# Fine texture sampled per corner (shared by the cells around it, so it stays smooth) plus a little
# extra saturation to counter the washed-out look. Roads and fields don't use this.
func _detail(col:Color, x:int, z:int) -> Color:
    var d:float = _detail_noise.get_noise_2d(x, z) if _detail_noise != null else 0.0;
    var gray:float = col.get_luminance();
    var out:Color = Color(gray, gray, gray).lerp(col, DETAIL_SATURATION);
    # brighter and yellower in one direction, darker and bluer in the other
    return Color(out.r + d * DETAIL_AMOUNT * 1.2, out.g + d * DETAIL_AMOUNT, out.b + d * DETAIL_AMOUNT * 0.5);

@warning_ignore("integer_division")
func _build_chunk(ci:int) -> void:
    var cx0:int = (ci % CHUNKS) * CHUNK;
    var cz0:int = (ci / CHUNKS) * CHUNK;
    var cells:int = CHUNK * CHUNK;
    var verts:PackedVector3Array = PackedVector3Array();
    var normals:PackedVector3Array = PackedVector3Array();
    var colors:PackedColorArray = PackedColorArray();
    var indices:PackedInt32Array = PackedInt32Array();
    verts.resize(cells * 4);
    normals.resize(cells * 4);
    colors.resize(cells * 4);
    indices.resize(cells * 6);
    # cell colors for this chunk plus a one-cell border, so natural surfaces can blend across cells
    var span:int = CHUNK + 2;
    var cell_cols:Array[Color] = [];
    cell_cols.resize(span * span);
    for z in span:
        for x in span:
            var c:Vector2i = Vector2i(clampi(cx0 + x - 1, 0, SIZE - 1), clampi(cz0 + z - 1, 0, SIZE - 1));
            cell_cols[z * span + x] = _cell_color(c);
    var v:int = 0;
    var k:int = 0;
    for z in range(cz0, cz0 + CHUNK):
        for x in range(cx0, cx0 + CHUNK):
            var cell:Vector2i = Vector2i(x, z);
            var li:int = (z - cz0 + 1) * span + (x - cx0 + 1);
            var own:Color = cell_cols[li];
            # each cell gets its own 4 vertices; roads and fields stay crisp, natural ground blends
            verts[v] = Vector3(x, corner(x, z), z);
            verts[v + 1] = Vector3(x + 1, corner(x + 1, z), z);
            verts[v + 2] = Vector3(x + 1, corner(x + 1, z + 1), z + 1);
            verts[v + 3] = Vector3(x, corner(x, z + 1), z + 1);
            normals[v] = _corner_normal(x, z);
            normals[v + 1] = _corner_normal(x + 1, z);
            normals[v + 2] = _corner_normal(x + 1, z + 1);
            normals[v + 3] = _corner_normal(x, z + 1);
            if overlay[index(cell)] == Overlay.ROAD:
                for j in 4:       # packed earth is mottled: each corner a little lighter or darker
                    var speck:float = float((((x * 2 + (j & 1)) * 73856093) ^ ((z * 2 + (j >> 1)) * 19349663)) & 1023) / 1023.0;
                    colors[v + j] = Color(own.r * (0.88 + speck * 0.24), own.g * (0.88 + speck * 0.24), own.b * (0.9 + speck * 0.2));
            elif overlay[index(cell)] != Overlay.NONE:
                for j in 4:
                    colors[v + j] = own;
            else:
                # corner j touches the cells on its (dx, dz) side; average the natural ones
                for j in 4:
                    var dx:int = 1 if (j == 1 or j == 2) else -1;
                    var dz:int = 1 if (j == 2 or j == 3) else -1;
                    var sum:Color = own;
                    var n:int = 1;
                    for o in [Vector2i(dx, 0), Vector2i(0, dz), Vector2i(dx, dz)]:
                        var nc:Vector2i = cell + o;
                        if in_bounds(nc) and overlay[index(nc)] == Overlay.NONE:
                            sum += cell_cols[li + o.y * span + o.x];
                            n += 1;
                    colors[v + j] = _detail(sum / float(n), x + (1 if (j == 1 or j == 2) else 0), z + (1 if (j == 2 or j == 3) else 0));
            # clockwise winding seen from above
            indices[k] = v;
            indices[k + 1] = v + 1;
            indices[k + 2] = v + 2;
            indices[k + 3] = v;
            indices[k + 4] = v + 2;
            indices[k + 5] = v + 3;
            v += 4;
            k += 6;
    var arrays:Array = [];
    arrays.resize(Mesh.ARRAY_MAX);
    arrays[Mesh.ARRAY_VERTEX] = verts;
    arrays[Mesh.ARRAY_NORMAL] = normals;
    arrays[Mesh.ARRAY_COLOR] = colors;
    arrays[Mesh.ARRAY_INDEX] = indices;
    var mesh:ArrayMesh = ArrayMesh.new();
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays);
    _chunks[ci].mesh = mesh;
