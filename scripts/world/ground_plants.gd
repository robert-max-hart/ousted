# ----------------------------------------------------------------
# GroundPlants
#     The small plants of the ground, for life up close: meadow flowers in patches on open grass (one colour
#     to a patch, in spring and summer, a few asters in autumn), ferns under and beside trees, and reeds with
#     cattails along the water's edge and in the shallows. Models in assets/models/ground (tools/make_ground.py,
#     a reduced set beside it). Laid out like GrassDetail: 16 by 16 cell blocks of multimeshes, drawn within
#     DRAW_DISTANCE of the camera, places fixed by a hash of the cell, rebuilt a few a frame when the terrain
#     or the season changes. They sway with the grass setting and their numbers follow it (Off draws none).
# ----------------------------------------------------------------
class_name GroundPlants extends Node3D;

const BLOCK         :int = 16;
const DIR           :String = "res://assets/models/ground/";
const DRAW_DISTANCE :float = 46.0;
const REBUILDS_PER_FRAME:int = 2;
var rebuilds_per_frame:int = REBUILDS_PER_FRAME;       # more while the loading screen is up
const FLOWER_DENSITY:float = 0.9;       # flower clumps per cell inside a flower patch
const FERN_DENSITY  :float = 0.55;      # ferns per cell beside trees
const REED_DENSITY  :float = 1.1;       # reed clumps per cell at the water's edge, inside a reed patch
const FLOWER_SHARE  :Array[float] = [1.0, 0.8, 0.12, 0.0];       # by season (spring to winter)
const REED_WINTER   :float = 0.45;
const PALETTE       :Array[Color] = [
    Color(1.0, 1.0, 0.95), Color(1.0, 0.85, 0.2), Color(0.96, 0.55, 0.7), Color(0.62, 0.45, 0.88), Color(0.4, 0.6, 0.95), Color(0.95, 0.4, 0.25),
];
const AUTUMN_FLOWER :Color = Color(0.7, 0.5, 0.85);
const STEMS_BY_SEASON:Array[Color] = [Color(0.3, 0.55, 0.2), Color(0.33, 0.52, 0.18), Color(0.55, 0.5, 0.22), Color(0.5, 0.45, 0.3)];
const FERN_BY_SEASON :Array[Color] = [Color(0.25, 0.5, 0.2), Color(0.2, 0.45, 0.16), Color(0.62, 0.4, 0.14), Color(0.5, 0.42, 0.25)];
const REED_BY_SEASON :Array[Color] = [Color(0.42, 0.55, 0.25), Color(0.4, 0.52, 0.22), Color(0.65, 0.55, 0.3), Color(0.62, 0.55, 0.38)];
# What each kind is made of: [model name, material key]. Parts of a kind share the transforms.
const LAYERS        :Dictionary = {
    &"flower_a": [["flower_a_stems", &"stems"], ["flower_a_heads", &"heads"]],
    &"flower_b": [["flower_b_stems", &"stems"], ["flower_b_heads", &"heads"]],
    &"fern": [["fern", &"fern"]],
    &"reed": [["reed_stalks", &"reed"], ["reed_heads", &"cattail"]],
};

var _world      :World;
var _blocks     :Dictionary = {};       # "bx,bz,kind:part" -> MultiMeshInstance3D
var _spots      :Dictionary = {};       # block -> {kind -> PackedVector3Array} (the render server keeps no readable copy)
var _dirty      :Array[Vector2i] = [];
var _mats       :Dictionary = {};       # material key -> ShaderMaterial
var _meshes     :Dictionary = {};
var _patch      :FastNoiseLite;
var _colour     :FastNoiseLite;
var _reed       :FastNoiseLite;
var _reduced    :bool = false;
var _flower_share:float = 1.0;

func _init(w:World) -> void:
    _world = w;
    _patch = _noise(11, 0.06);
    _colour = _noise(23, 0.11);
    _reed = _noise(37, 0.09);
    var s:int = Climate.look(GameClock.season());
    _mats[&"stems"] = WindSway.make(STEMS_BY_SEASON[s], 0.05, 0.3, true);
    _mats[&"heads"] = WindSway.make(Color(1, 1, 1), 0.06, 0.3, true);
    _mats[&"fern"] = WindSway.make(FERN_BY_SEASON[s], 0.04, 0.4, true);
    _mats[&"reed"] = WindSway.make(REED_BY_SEASON[s], 0.12, 1.0, true);
    _mats[&"cattail"] = WindSway.make(Color(0.5, 0.33, 0.2), 0.12, 1.0, true);
    _load_meshes();

func _noise(offset:int, freq:float) -> FastNoiseLite:
    var n:FastNoiseLite = FastNoiseLite.new();
    n.seed = _world.terrain.world_seed_for_textures * 7 + offset;
    n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH;
    n.frequency = freq;
    return n;

func _load_meshes() -> void:
    _reduced = Settings.models_reduced();
    _meshes.clear();
    for kind in LAYERS:
        for layer in LAYERS[kind]:
            _meshes[layer[0]] = load("%s%s.obj" % [Settings.model_dir(DIR), layer[0]]) as Mesh;

func _ready() -> void:
    _world.terrain.ground_changed.connect(_on_terrain_changed);
    GameClock.season_changed.connect(_on_season);
    reload();

func _on_season(s:int) -> void:
    var look:int = Climate.look(s);
    WindSway.set_color(_mats[&"stems"], STEMS_BY_SEASON[look]);
    WindSway.set_color(_mats[&"fern"], FERN_BY_SEASON[look]);
    WindSway.set_color(_mats[&"reed"], REED_BY_SEASON[look]);
    reload();

# Rebuilds every block (a season change, or a setting).
func reload() -> void:
    if Settings.models_reduced() != _reduced:
        _load_meshes();
        for key in _blocks:
            (_blocks[key] as MultiMeshInstance3D).queue_free();
        _blocks.clear();
    _dirty.clear();
    var n:int = Terrain.SIZE / BLOCK;
    for bz in n:
        for bx in n:
            _dirty.append(Vector2i(bx, bz));

func _on_terrain_changed(r:Rect2i) -> void:
    var lo:Vector2i = Vector2i(maxi(r.position.x - 1, 0), maxi(r.position.y - 1, 0)) / BLOCK;
    var hi:Vector2i = Vector2i(mini(r.end.x + 1, Terrain.SIZE - 1), mini(r.end.y + 1, Terrain.SIZE - 1)) / BLOCK;
    for bz in range(lo.y, hi.y + 1):
        for bx in range(lo.x, hi.x + 1):
            var b:Vector2i = Vector2i(bx, bz);
            if not _dirty.has(b):
                _dirty.append(b);

func _process(_delta:float) -> void:
    for i in mini(rebuilds_per_frame, _dirty.size()):
        _rebuild(_dirty.pop_front());

func _hash(x:int, z:int, k:int) -> int:
    return (((x * 73856093) ^ (z * 19349663)) * (k + 3) + k * 40503) & 0xffffff;

func _copies(want:float, h:int) -> int:
    return floori(want) + (1 if float(h & 255) / 255.0 < want - floorf(want) else 0);

func _rebuild(b:Vector2i) -> void:
    var t:Terrain = _world.terrain;
    var share:float = Settings.grass_share();
    var look:int = Climate.look(GameClock.season());
    var dormant:bool = Climate.is_dormant();
    _flower_share = float(Climate.data().get("flowers", 1.0));
    var found:Dictionary = {};            # kind -> Array of [position, yaw, scale, tint, flower colour]
    for kind in LAYERS:
        found[kind] = [];
    if share > 0.0:
        for z in range(b.y * BLOCK, (b.y + 1) * BLOCK):
            for x in range(b.x * BLOCK, (b.x + 1) * BLOCK):
                var c:Vector2i = Vector2i(x, z);
                if _free(c):
                    _land_plants(c, found, share, look, dormant);
                _reeds(c, found, share, dormant);
    var key:String = "%d,%d," % [b.x, b.y];
    var spots:Dictionary = {};
    for kind in LAYERS:
        var list:Array = found[kind];
        var pts:PackedVector3Array = PackedVector3Array();
        for e in list:
            pts.append(e[0]);
        spots[kind] = pts;
        for layer in LAYERS[kind]:
            _fill(key + "%s:%s" % [kind, layer[1]], layer[0], layer[1], list, layer[1] == &"heads");
    _spots[b] = spots;

# Flowers and ferns on an open grassy cell.
func _land_plants(c:Vector2i, found:Dictionary, share:float, look:int, dormant:bool) -> void:
    var bloom:float = 0.0 if dormant else FLOWER_SHARE[look] * _flower_share;
    var n:float = _patch.get_noise_2d(c.x, c.y);
    if bloom > 0.0 and n > 0.1:
        var h:int = _hash(c.x, c.y, 1);
        var want:float = FLOWER_DENSITY * share * bloom * smoothstep(0.1, 0.45, n);
        # one colour to a patch (from the coarse colour noise), the odd stray of another
        var pick:int = clampi(int((_colour.get_noise_2d(c.x, c.y) * 0.5 + 0.5) * PALETTE.size() * 1.0), 0, PALETTE.size() - 1);
        for k in _copies(want, h):
            var hk:int = _hash(c.x, c.y, k + 5);
            var col:Color = PALETTE[pick] if (hk >> 20) % 5 != 0 else PALETTE[hk % PALETTE.size()];
            if look == 2:
                col = AUTUMN_FLOWER;
            _add(found[&"flower_a" if hk % 3 != 0 else &"flower_b"], c, hk, 0.8, 1.2, col);
    if not dormant and _trees_near(c) >= 2:
        var hf:int = _hash(c.x, c.y, 2);
        for k in _copies(FERN_DENSITY * share, hf):
            _add(found[&"fern"], c, _hash(c.x, c.y, k + 9), 0.8, 1.25, Color.WHITE);

# Reeds on the shore and in the shallows.
func _reeds(c:Vector2i, found:Dictionary, share:float, dormant:bool) -> void:
    var t:Terrain = _world.terrain;
    if not t.in_bounds(c) or t.get_overlay(c) != Terrain.Overlay.NONE or _world.occupant[_world.idx(c)] != null or _world.is_bridge(c):
        return;
    if t.is_water(c):
        if not t.is_shallow(c):
            return;
    elif t.cell_height(c) > Terrain.WATER_LEVEL + 0.5 or not _wet_near(c):
        return;
    var n:float = _reed.get_noise_2d(c.x, c.y);
    if n < -0.05:
        return;
    var want:float = REED_DENSITY * share * smoothstep(-0.05, 0.4, n) * (REED_WINTER if dormant else 1.0);
    for k in _copies(want, _hash(c.x, c.y, 3)):
        _add(found[&"reed"], c, _hash(c.x, c.y, k + 13), 0.85, 1.25, Color.WHITE);

func _add(list:Array, c:Vector2i, hk:int, lo:float, hi:float, col:Color) -> void:
    var t:Terrain = _world.terrain;
    var px:float = c.x + float(hk & 255) / 256.0;
    var pz:float = c.y + float((hk >> 8) & 255) / 256.0;
    var s:float = lerpf(lo, hi, float((hk >> 16) & 255) / 255.0);
    var tint:float = 0.85 + float((hk >> 4) & 15) / 15.0 * 0.15;
    list.append([Vector3(px, t.height_at(px, pz) - 0.02, pz), float(hk % 628) / 100.0, s, tint, col]);

func _fill(key:String, model:String, mat_key:StringName, list:Array, is_heads:bool) -> void:
    var mmi:MultiMeshInstance3D = _blocks.get(key);
    if list.is_empty() and mmi == null:
        return;
    if mmi == null:
        var mm:MultiMesh = MultiMesh.new();
        mm.transform_format = MultiMesh.TRANSFORM_3D;
        mm.use_colors = true;
        mm.mesh = _meshes[model];
        mmi = MultiMeshInstance3D.new();
        mmi.multimesh = mm;
        mmi.material_override = _mats[mat_key];
        mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
        mmi.visibility_range_end = DRAW_DISTANCE;
        mmi.visibility_range_end_margin = 4.0;
        add_child(mmi);
        _blocks[key] = mmi;
    var multi:MultiMesh = mmi.multimesh;
    multi.instance_count = list.size();
    for i in list.size():
        var e:Array = list[i];
        var sc:float = e[2];
        multi.set_instance_transform(i, Transform3D(Basis(Vector3.UP, e[1]).scaled(Vector3(sc, sc, sc)), e[0]));
        var tint:float = e[3];
        multi.set_instance_color(i, (e[4] as Color) * tint if is_heads else Color(tint, tint, tint));

# Trees (crowns that shade the ground) within two cells.
func _trees_near(c:Vector2i) -> int:
    var n:int = 0;
    for dz in range(-2, 3):
        for dx in range(-2, 3):
            var cc:Vector2i = c + Vector2i(dx, dz);
            if _world.terrain.in_bounds(cc):
                var rn:Variant = _world.node_at[_world.idx(cc)];
                if rn != null and (rn as ResourceNode).is_tree():
                    n += 1;
    return n;

func _wet_near(c:Vector2i) -> bool:
    for dz in range(-1, 2):
        for dx in range(-1, 2):
            var cc:Vector2i = c + Vector2i(dx, dz);
            if _world.terrain.in_bounds(cc) and _world.terrain.is_water(cc):
                return true;
    return false;

# How many of a kind stand in a cell (for tests).
func count_in_cell(kind:StringName, c:Vector2i) -> int:
    var spots:Dictionary = _spots.get(c / BLOCK, {});
    var n:int = 0;
    for p in spots.get(kind, PackedVector3Array()):
        if floori(p.x) == c.x and floori(p.z) == c.y:
            n += 1;
    return n;

# Open grass: dry, gentle, no road, field or building on it, and nothing growing in it.
func _free(c:Vector2i) -> bool:
    var t:Terrain = _world.terrain;
    if t.is_water(c) or t.get_overlay(c) != Terrain.Overlay.NONE or _world.occupant[_world.idx(c)] != null or _world.node_at[_world.idx(c)] != null:
        return false;
    return t.cell_height(c) >= Terrain.WATER_LEVEL + 0.5 and t.cell_slope(c) < 0.9;
