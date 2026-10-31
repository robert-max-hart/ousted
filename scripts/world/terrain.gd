# ----------------------------------------------------------------
# Terrain
#     Heightmap grid rendered as chunked meshes. Heights live on cell
#     corners ((SIZE+1)^2); cells carry a surface overlay (road, tilled).
#     Edits mark nearby chunks dirty and they rebuild next frame.
# ----------------------------------------------------------------
class_name Terrain extends Node3D;

signal changed(rect:Rect2i);
signal ground_changed(rect:Rect2i);       # the ground's look changed: sculpting or a road, field or site laid or removed

enum Overlay { NONE, ROAD, TILLED, SITE, GRAVE, ROAD_SITE, CHANNEL, CHANNEL_WET, ORCHARD };      # (new ids go last: saves keep the numbers)

# The map's side in cells. A new game picks one of MAP_SIZES (see set_size) before the World is built, a loaded
# game takes the saved one; SIZE and CHUNKS are read like constants everywhere.
const DEFAULT_SIZE      :int = 160;
const MAP_SIZES         :Array[int] = [96, 128, 160, 192];
const MAP_SIZE_NAMES    :Array[String] = ["Small", "Medium", "Large", "Huge"];
const CHUNK             :int = 32;
static var SIZE         :int = DEFAULT_SIZE;
static var CHUNKS       :int = DEFAULT_SIZE / CHUNK;       # SIZE / CHUNK

# A multiple of CHUNK, so the map divides into whole chunks.
static func set_size(cells:int) -> void:
    SIZE = maxi(CHUNK * 2, cells / CHUNK * CHUNK);
    CHUNKS = SIZE / CHUNK;
const WATER_LEVEL       :float = 0.0;
const SHALLOW_FROM      :float = -0.45;       # water no deeper than this (below the surface) can be waded through
const MAX_HEIGHT        :float = 40.0;
const MIN_HEIGHT        :float = -6.0;

const COLOR_SAND        :Color = Color(0.6, 0.54, 0.38);
const COLOR_ROCK        :Color = Color(0.47, 0.44, 0.39);
const COLOR_ROAD        :Color = Color(0.56, 0.46, 0.33);
const COLOR_TILLED      :Color = Color(0.36, 0.25, 0.16);
const COLOR_GRAVE       :Color = Color(0.24, 0.33, 0.2);        # a graveyard: mossy, mown grass
const COLOR_SITE        :Color = Color(0.62, 0.52, 0.34);      # a field being dug: pale, bare soil
const COLOR_ORCHARD     :Color = Color(0.26, 0.4, 0.19);       # an orchard: mown grass between the trees
const COLOR_CHANNEL     :Color = Color(0.34, 0.27, 0.19);      # a dug channel with no water in it
const COLOR_CHANNEL_WET :Color = Color(0.2, 0.38, 0.5);        # one connected to water
const DETAIL_AMOUNT     :float = 0.055;
const DETAIL_SATURATION :float = 1.15;
const GRASS_BY_SEASON   :Array[Color] = [
    Color(0.22, 0.37, 0.14), Color(0.28, 0.38, 0.12), Color(0.42, 0.34, 0.15), Color(0.4, 0.37, 0.25),
];

var heights :PackedFloat32Array;
var overlay :PackedByteArray;
var _chunks :Array[MeshInstance3D] = [];
var _dirty  :Dictionary = {};
var soil_view :bool = false;            # colour the ground by soil fertility (set_soil_view)
var slope_view :bool = false;           # colour the ground by how steep it is for building (set_slope_view)
var water_view :bool = false;           # colour the ground by reach of water (where a building that needs a water source may stand)
var water_source :Callable;              # cell index -> distance (cells) to the nearest water source, set by World
var soil_source :Callable;               # cell index -> fertility 0..1, set by World
var _material:ShaderMaterial;       # shaders/terrain.gdshader
var _season :int = 0;
var world_seed_for_textures:int = 1;      # set by World before the terrain is added (the noise texture follows the map seed)
var _tint_noise:FastNoiseLite;
var _detail_noise:FastNoiseLite;

func _ready() -> void:
    _material = ShaderMaterial.new();
    _material.shader = load("res://shaders/terrain.gdshader") as Shader;
    _material.set_shader_parameter("noise_tex", TerrainTexture.make(world_seed_for_textures));
    _material.set_shader_parameter("snow", 0.0);
    _material.set_shader_parameter("overlay_view", 0.0);
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

# Shape of the land (the numbers behind generate): a gentle base, mostly level in the lowlands, with a few ridged hill
# regions on top. tests/terrain_probe prints the share of level, rolling and steep ground for a set of seeds.
const BASE_AMP       :float = 5.5;      # height range of the gentle base, +- this at most
const BASE_OFFSET    :float = 1.4;      # lifts the base so most of it is dry land
const BASE_OCTAVES   :int = 3;          # more octaves, more small bumps
const BASE_FREQ      :float = 0.010;
const HILLS_FREQ     :float = 0.008;    # how big the hill regions are
# How hilly the map is (the New Game screen's "Hills"): `from` is the hill mask noise above which hills rise (higher:
# fewer hill regions), `amp` how high the ridges stand. Normal is what the map always was. Rocks and iron ore appear on
# steep ground, so a flat map has little of either beyond the guaranteed few at the start.
enum Hills { FLAT, FEW, NORMAL, MANY };       # (new ids go last: saves keep the numbers)
const HILLS:Dictionary = {
    Hills.FLAT:   {"name": "Flat",   "from": 0.45, "amp": 5.0,  "desc": "Almost no hills, only gentle rises. Plenty of room to build, but little stone or iron beyond the start."},
    Hills.FEW:    {"name": "Few",    "from": 0.30, "amp": 11.0, "desc": "A few small hill regions in a mostly level land."},
    Hills.NORMAL: {"name": "Normal", "from": 0.19, "amp": 15.0, "desc": "Hill regions here and there, with level land between."},
    Hills.MANY:   {"name": "Many",   "from": 0.05, "amp": 18.0, "desc": "Hills across much of the map: rich in stone and iron, but little level ground."},
};
static var hills_level:int = Hills.NORMAL;

# A winding river from one edge of the map to the opposite one: it follows low ground where it can, widens downstream, and has
# a few shallow fords where citizens can wade across. tests/river_probe prints what it makes for a set of seeds.
const RIVER_HALF_UP   :float = 1.7;       # half the width (cells) at the source end
const RIVER_HALF_DOWN :float = 4.2;       # ... and at the mouth
const RIVER_BED       :float = -0.95;      # height of the bed in the middle of a deep stretch
const RIVER_BANK      :float = 8.0;       # cells over which the banks blend into the land
const RIVER_STEP      :float = 1.6;       # cells between points of the centre line
const FORDS           :int = 3;

# Water layouts (the New Game screen's "Water" choice; the code calls it river_style because it began as the river).
# "land" says how the water is made: a river (the rest of the entry: how hard its centre line wanders, `meander`
# scales the heading bias, `freq` is how fast it changes, `width` scales the half widths), none, a wetland (most of
# the map is shallow water, with a dry rise to start on) or a coast (one side of the map is ocean).
enum RiverStyle { NONE, GENTLE, WINDING, WILD, WIDE, WETLANDS, COAST };      # (new ids go last: saves keep the numbers)
const RIVER_STYLES:Dictionary = {
    RiverStyle.NONE:    {"name": "None",    "land": &"dry",      "desc": "No river. Water is only where the land dips into ponds, plus wells and rain.", "meander": 0.0, "freq": 0.03, "width": 1.0},
    RiverStyle.GENTLE:  {"name": "Gentle",  "land": &"river",    "desc": "A nearly straight river with a few lazy bends.",               "meander": 0.4, "freq": 0.02, "width": 1.0},
    RiverStyle.WINDING: {"name": "Winding", "land": &"river",    "desc": "One river that winds across the map.",                          "meander": 1.5, "freq": 0.03, "width": 1.0},
    RiverStyle.WILD:    {"name": "Wild",    "land": &"river",    "desc": "A river that doubles back on itself in tight loops.",           "meander": 2.8, "freq": 0.055, "width": 1.0},
    RiverStyle.WIDE:    {"name": "Wide",    "land": &"river",    "desc": "A broad river: more water, fewer places to cross.",             "meander": 1.2, "freq": 0.03, "width": 1.6},
    RiverStyle.WETLANDS:{"name": "Wetlands","land": &"wetlands", "desc": "Most of the map is shallow water you can wade through, with islands and rises of dry land. Build on the dry parts; bridge the deep channels.", "meander": 0.0, "freq": 0.03, "width": 1.0},
    RiverStyle.COAST:   {"name": "Coast",   "land": &"coast",    "desc": "One side of the map is open ocean, with a wandering shoreline and a shallow beach. Fish from piers.", "meander": 0.0, "freq": 0.03, "width": 1.0},
};
const WET_SHARE       :float = 0.74;      # wetlands: about this share of the map ends up under water
const WET_SOFT        :float = 4.5;       # ... and how gently it deepens (a bigger number keeps more of it wadeable)
const WET_ISLAND      :float = 1.8;       # height of the dry rise the colony starts on
const COAST_AT        :float = 0.21;      # the shoreline's mean distance from its edge, as a share of the map
const COAST_WOBBLE    :float = 0.07;      # how far it wanders, as a share of the map
const COAST_BEACH     :float = 10.0;      # cells over which the shore climbs from the sea to the land
const COAST_SLOPE     :float = 0.15;      # how fast the sea floor deepens (height per cell off the shore)
static var river_style:int = RiverStyle.WINDING;
const FORD_BED        :float = -0.35;     # a hand deep: there is water over the ford, and it can still be waded (SHALLOW_FROM)
const FORD_HALF       :int = 2;           # points on each side of a ford's middle that stay shallow
const FORD_RAMP       :int = 3;           # points over which the bed deepens again
const RIVER_FAR       :float = 45.0;      # how far from the centre line the distance field reaches
const RIVER_NEAR      :float = 10.0;      # cells from the river that still count as its valley (richer soil)

var river_path :PackedVector2Array;       # the centre line, in cells (empty when the map has no river)
var river_fords:PackedVector2Array;       # the middle of each ford, in cells
var river_dist :PackedFloat32Array;       # per corner: distance to the centre line, 999 beyond the valley

func _carve_river(world_seed:int) -> void:
    var style:Dictionary = RIVER_STYLES[river_style];
    var n:int = SIZE + 1;
    river_dist = PackedFloat32Array();
    river_dist.resize(n * n);
    river_dist.fill(999.0);
    river_path = PackedVector2Array();
    river_fords = PackedVector2Array();
    var rng:RandomNumberGenerator = RandomNumberGenerator.new();
    rng.seed = world_seed + 91;
    var meander:FastNoiseLite = FastNoiseLite.new();
    meander.seed = world_seed + 92;
    meander.frequency = float(style["freq"]);
    var side:int = rng.randi_range(0, 3);
    var a:float = rng.randf_range(0.25, 0.75) * SIZE;
    var b:float = rng.randf_range(0.25, 0.75) * SIZE;
    var from:Vector2 = [Vector2(a, 0.0), Vector2(SIZE, a), Vector2(a, SIZE), Vector2(0.0, a)][side];
    var goal:Vector2 = [Vector2(b, SIZE), Vector2(0.0, b), Vector2(b, 0.0), Vector2(SIZE, b)][side];
    var pos:Vector2 = from;
    var heading:float = (goal - from).angle();
    var points:PackedVector2Array = PackedVector2Array([pos]);
    for i in 600:
        var best:float = INF;
        var best_h:float = heading;
        var bias:float = meander.get_noise_1d(i) * float(style["meander"]);      # the heading the river wants, around the straight line to its goal
        for off in [-0.5, -0.25, 0.0, 0.25, 0.5]:
            var h:float = heading + off;
            var q:Vector2 = pos + Vector2.from_angle(h) * RIVER_STEP;
            var turn_to_goal:float = absf(angle_difference(h, (goal - pos).angle() + bias));
            var score:float = height_at(q.x, q.y) * 0.5 + absf(off) * 1.0 + turn_to_goal * 3.0;
            if pos.distance_to(goal) > 25.0 and (q.x < 8.0 or q.y < 8.0 or q.x > SIZE - 8.0 or q.y > SIZE - 8.0):
                score += 12.0;          # stay on the map until the last stretch
            if score < best:
                best = score;
                best_h = h;
        heading = best_h;
        pos += Vector2.from_angle(heading) * RIVER_STEP;
        points.append(pos);
        if pos.x < -1.0 or pos.y < -1.0 or pos.x > SIZE + 1.0 or pos.y > SIZE + 1.0:
            break;
    var count:int = points.size();
    if count < 20:
        return;
    river_path = points;
    var ford_at:Array[int] = [];
    for k in FORDS:
        ford_at.append(clampi(roundi(count * (0.2 + 0.65 * (k + rng.randf_range(0.2, 0.8)) / FORDS)), 0, count - 1));
        river_fords.append(points[ford_at[k]]);
    # each corner follows its nearest point of the centre line: first find it (out to RIVER_FAR cells), then carve
    var nearest:PackedInt32Array = PackedInt32Array();
    nearest.resize(n * n);
    nearest.fill(-1);
    for i in count:
        var p:Vector2 = points[i];
        for z in range(maxi(0, floori(p.y - RIVER_FAR)), mini(n, ceili(p.y + RIVER_FAR) + 1)):
            for x in range(maxi(0, floori(p.x - RIVER_FAR)), mini(n, ceili(p.x + RIVER_FAR) + 1)):
                var d:float = Vector2(x, z).distance_to(p);
                var k:int = z * n + x;
                if d < river_dist[k]:
                    river_dist[k] = d;
                    nearest[k] = i;
    var original:PackedFloat32Array = heights.duplicate();
    for k in n * n:
        var i:int = nearest[k];
        if i < 0:
            continue;
        var t:float = float(i) / float(count - 1);
        var half:float = lerpf(RIVER_HALF_UP, RIVER_HALF_DOWN, t) * float(style["width"]);
        var d:float = river_dist[k];
        if d > half + RIVER_BANK:
            continue;
        var gap:int = 999;
        for f in ford_at:
            gap = mini(gap, absi(i - f));
        var shallow:float = 1.0 - smoothstep(float(FORD_HALF), float(FORD_HALF + FORD_RAMP), float(gap));
        var bed:float = lerpf(RIVER_BED, FORD_BED, shallow);
        var level:float = bed * (1.0 - 0.5 * minf(d / half, 1.0) ** 2) if shallow < 0.5 else bed;
        heights[k] = minf(heights[k], lerpf(original[k], level, 1.0 - smoothstep(half, half + RIVER_BANK, d)));

# How far (cells) a cell is from the river's centre line; 999 when it is far from it or the map has none.
# Wetlands: the whole land is lowered until about WET_SHARE of it is under water (the underwater part is
# squeezed so most of it can be waded), and a dry level rise near the middle is where the colony starts.
func _flood(world_seed:int) -> void:
    var n:int = SIZE + 1;
    var sorted:PackedFloat32Array = heights.duplicate();
    sorted.sort();
    var shift:float = sorted[int(sorted.size() * WET_SHARE)];
    var rng:RandomNumberGenerator = RandomNumberGenerator.new();
    rng.seed = world_seed + 95;
    var mid:Vector2 = Vector2(SIZE * 0.5, SIZE * 0.5) + Vector2(rng.randf_range(-0.1, 0.1), rng.randf_range(-0.1, 0.1)) * SIZE;
    var radius:float = clampf(SIZE * 0.12, 14.0, 24.0);
    for z in n:
        for x in n:
            var h:float = heights[z * n + x] - shift;
            if h < 0.0:
                h = -0.9 * (1.0 - exp(h / WET_SOFT));
            var w:float = 1.0 - smoothstep(radius, radius + 12.0, Vector2(x, z).distance_to(mid));
            heights[z * n + x] = lerpf(h, WET_ISLAND + _detail_noise.get_noise_2d(x, z) * 0.15, w);

# Coast: one side of the map (by the seed) is sea. The shoreline wanders; off it the floor deepens, inland it
# climbs over COAST_BEACH cells to the land. river_dist holds the distance inland from the shore (the start site
# and the soil use it like a river's).
func _carve_coast(world_seed:int) -> void:
    var n:int = SIZE + 1;
    river_dist = PackedFloat32Array();
    river_dist.resize(n * n);
    river_dist.fill(999.0);
    var rng:RandomNumberGenerator = RandomNumberGenerator.new();
    rng.seed = world_seed + 93;
    var side:int = rng.randi_range(0, 3);
    var wobble:FastNoiseLite = FastNoiseLite.new();
    wobble.seed = world_seed + 94;
    wobble.frequency = 0.02;
    wobble.fractal_octaves = 2;
    for z in n:
        for x in n:
            var off:float = [float(z), float(SIZE - z), float(x), float(SIZE - x)][side];        # distance from the sea's edge
            var along:float = [float(x), float(x), float(z), float(z)][side];
            var inland:float = off - (SIZE * COAST_AT + wobble.get_noise_1d(along) * SIZE * COAST_WOBBLE * 2.0);
            var sea:float = -0.3 - COAST_SLOPE * clampf(-inland, 0.0, 14.0);
            var land:float = lerpf(sea, heights[z * n + x], smoothstep(0.0, COAST_BEACH, inland));
            heights[z * n + x] = land;
            river_dist[z * n + x] = maxf(inland, 0.0);

func river_distance(c:Vector2i) -> float:
    if river_dist.is_empty():
        return 999.0;
    return river_dist[clampi(c.y, 0, SIZE) * (SIZE + 1) + clampi(c.x, 0, SIZE)];

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
    base.frequency = BASE_FREQ;
    base.fractal_octaves = BASE_OCTAVES;
    var hills_mask:FastNoiseLite = FastNoiseLite.new();
    hills_mask.seed = world_seed + 1;
    hills_mask.frequency = HILLS_FREQ;
    var ridges:FastNoiseLite = FastNoiseLite.new();
    ridges.seed = world_seed + 2;
    ridges.frequency = 0.03;
    ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED;
    ridges.fractal_octaves = 3;

    var n:int = SIZE + 1;
    var hills_from:float = float(HILLS[hills_level]["from"]);
    var hills_amp:float = float(HILLS[hills_level]["amp"]);
    heights.resize(n * n);
    for z in n:
        for x in n:
            var h:float = base.get_noise_2d(x, z) * BASE_AMP + BASE_OFFSET;
            var mask:float = clampf((hills_mask.get_noise_2d(x, z) - hills_from) * 3.0, 0.0, 1.0);
            h += mask * (ridges.get_noise_2d(x, z) * 0.5 + 0.5) * hills_amp;
            heights[z * n + x] = h;
    river_dist = PackedFloat32Array();
    river_path = PackedVector2Array();
    river_fords = PackedVector2Array();
    match RIVER_STYLES[river_style]["land"]:
        &"wetlands":
            _flood(world_seed);
        &"coast":
            _carve_coast(world_seed);
        &"river":
            _carve_river(world_seed);
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

# Shallow water can be waded through (slowly); anything deeper blocks walking.
func is_shallow(c:Vector2i) -> bool:
    return is_water(c) and cell_height(c) >= WATER_LEVEL + SHALLOW_FROM;

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

# (Not used by the game: player terrain modification left the design, and this stays for a future map editor, M8, and the soak test.)
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

# The soil overlay: ground drawn from brown (worn out) through yellow to green (rich).
func set_soil_view(on:bool) -> void:
    if soil_view == on:
        return;
    soil_view = on;
    _overlay_changed();
    mark_all_dirty();

# The water overlay: ground within WATER_REACH of a water source shows blue-green (a Distillery or Potter's Workshop works
# there), all else stays a dull brown.
const WATER_REACH:float = 12.0;       # the "needs_water" radius of the Distillery and the Potter's Workshop

# The slope overlay: how much the ground rises and falls under a house-sized patch (3x3 cells around each cell), the
# number that decides whether a building fits (World.can_place): green is level, yellow needs some levelling, red is
# past BUILD_SLOPE (nothing small can go there, and a drag-sized building has double that).
const BUILD_SLOPE:float = 2.5;        # the most height difference a building's footprint may have
const SLOPE_EASY :float = 0.6;        # up to this the ground is as good as level

func set_slope_view(on:bool) -> void:
    if slope_view == on:
        return;
    slope_view = on;
    _overlay_changed();
    mark_all_dirty();

# The height range over the 3x3 cells around c.
func relief(c:Vector2i) -> float:
    var hr:Vector2 = rect_height_range(Rect2i(c - Vector2i.ONE, Vector2i(3, 3)));
    return hr.y - hr.x;

static func slope_color(r:float) -> Color:
    if r <= SLOPE_EASY:
        return Color(0.25, 0.7, 0.3);
    if r <= BUILD_SLOPE:       # yellow, turning orange as it nears the limit
        return Color(0.9, 0.82, 0.25).lerp(Color(0.95, 0.5, 0.15), (r - SLOPE_EASY) / (BUILD_SLOPE - SLOPE_EASY));
    return Color(0.82, 0.18, 0.15);

func set_water_view(on:bool) -> void:
    if water_view == on:
        return;
    water_view = on;
    _overlay_changed();
    mark_all_dirty();

static func water_color(d:float) -> Color:
    if d > WATER_REACH:
        return Color(0.42, 0.38, 0.32);
    return Color(0.1, 0.5, 0.72).lerp(Color(0.4, 0.78, 0.5), clampf(d / WATER_REACH, 0.0, 1.0));

# Redraws a rect (the soil or water colours changed).
func refresh_rect(r:Rect2i) -> void:
    if soil_view or water_view:
        _mark_dirty_rect(r);

static func soil_color(f:float) -> Color:
    var poor:Color = Color(0.5, 0.3, 0.16);
    var middling:Color = Color(0.82, 0.74, 0.25);
    var rich:Color = Color(0.2, 0.62, 0.2);
    return poor.lerp(middling, clampf(f / 0.5, 0.0, 1.0)) if f < 0.5 else middling.lerp(rich, clampf((f - 0.5) / 0.4, 0.0, 1.0));

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
    if slope_view and not is_water(c):
        return slope_color(relief(c));
    if water_view and water_source.is_valid() and overlay[index(c)] != Overlay.ROAD and not is_water(c):
        return water_color(water_source.call(index(c)));
    if soil_view and soil_source.is_valid() and overlay[index(c)] != Overlay.ROAD and overlay[index(c)] != Overlay.CHANNEL and overlay[index(c)] != Overlay.CHANNEL_WET and not is_water(c) and cell_height(c) >= WATER_LEVEL + 0.35 and cell_slope(c) <= 1.4:
        return soil_color(soil_source.call(index(c)));
    match overlay[index(c)]:
        Overlay.ROAD:
            col = COLOR_ROAD;
        Overlay.SITE:
            col = COLOR_SITE;
        Overlay.ORCHARD:
            col = COLOR_ORCHARD;
        Overlay.CHANNEL:
            col = COLOR_CHANNEL;
        Overlay.CHANNEL_WET:
            col = COLOR_CHANNEL_WET;
        Overlay.GRAVE:
            col = COLOR_GRAVE;
        Overlay.TILLED:
            col = COLOR_TILLED;
        _:
            var slope:float = cell_slope(c);
            if cell_height(c) < WATER_LEVEL + 0.35:
                col = COLOR_SAND;
            elif slope > 1.4:
                col = COLOR_ROCK;
            else:
                col = GRASS_BY_SEASON[_season].lerp(COLOR_ROCK, clampf((slope - 0.8) / 0.6, 0.0, 1.0));
            if overlay[index(c)] == Overlay.ROAD_SITE:
                col = col.lerp(COLOR_ROAD, 0.4);       # a staked road: worn ground with crisp edges, but flat: no mottling or pebbles like a finished road
    # soft, low-frequency patches plus a faint per-cell speckle so the grid doesn't look flat
    var v:float = float(absi(hash(c)) % 1000) / 1000.0 * 0.012 - 0.006;
    if _tint_noise != null:
        v += _tint_noise.get_noise_2d(c.x, c.y) * 0.04;
    return Color(col.r + v, col.g + v, col.b + v);

# The vertex colour's alpha is how well snow lies on the ground (read by shaders/terrain.gdshader): packed roads and
# ploughed fields hold less, a channel none.
const SNOW_HOLD_ROAD :float = 0.25;
const SNOW_HOLD_FIELD:float = 0.5;

func _snow_hold(o:int) -> float:
    match o:
        Overlay.CHANNEL, Overlay.CHANNEL_WET:
            return 0.0;
        Overlay.ROAD:
            return SNOW_HOLD_ROAD;
        Overlay.TILLED, Overlay.SITE:
            return SNOW_HOLD_FIELD;
        Overlay.ROAD_SITE:
            return 0.6;
        Overlay.GRAVE, Overlay.ORCHARD:
            return 0.85;
    return 1.0;

# How much of the ground is under snow, 0 to 1 (the weather sets it: see WorldVisuals).
func set_snow(cover:float) -> void:
    _material.set_shader_parameter("snow", clampf(cover, 0.0, 1.0));

# The overlays (soil, water, slope) paint the ground a flat colour: the shader shows it plain then.
func _overlay_changed() -> void:
    _material.set_shader_parameter("overlay_view", 1.0 if (soil_view or water_view or slope_view) else 0.0);

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
                    colors[v + j] = Color(own.r * (0.95 + speck * 0.1), own.g * (0.95 + speck * 0.1), own.b * (0.96 + speck * 0.08), SNOW_HOLD_ROAD);
            elif overlay[index(cell)] == Overlay.TILLED or overlay[index(cell)] == Overlay.SITE:
                for j in 4:       # ploughed ground: a ridge along each row's top edge and a furrow along its bottom, with some mottling
                    var crumb:float = float((((x * 2 + (j & 1)) * 83492791) ^ ((z * 2 + (j >> 1)) * 2654435761)) & 1023) / 1023.0;
                    var row:float = 1.0 if overlay[index(cell)] == Overlay.SITE else (1.1 if j < 2 else 0.86);
                    var shade:float = row * (0.94 + crumb * 0.12);
                    colors[v + j] = Color(own.r * shade, own.g * shade, own.b * shade, SNOW_HOLD_FIELD);
            elif overlay[index(cell)] != Overlay.NONE:
                var hold:float = _snow_hold(overlay[index(cell)]);
                for j in 4:
                    colors[v + j] = Color(own.r, own.g, own.b, hold);
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
