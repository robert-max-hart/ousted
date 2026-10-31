# ----------------------------------------------------------------
# GrassDetail
#     Small tufts of grass over open grassy ground, for texture up
#     close. The map is cut into 16x16 cell blocks, one MultiMesh
#     each, and a block is only drawn within DRAW_DISTANCE of the
#     camera, so the cost stays small however big the map is. Tufts
#     keep to the same places for a cell (a hash of it), skip water,
#     sand, steep ground, roads, fields and buildings, take the
#     season's colour and are sparse and dry in winter. Blocks are
#     rebuilt (a few a frame) when the terrain under them changes.
#     The Grass setting (Settings) scales DENSITY; Off draws none.
# ----------------------------------------------------------------
class_name GrassDetail extends Node3D;

const BLOCK         :int = 16;
const DENSITY       :float = 2.4;       # tufts per grassy cell (the knob if it costs too much frame rate)
const WINTER_SHARE  :float = 0.3;       # share of the tufts that still stick out of the snow
const GRASS_SWAY    :float = 0.07;      # metres the tips bend in calm weather
const GRASS_HEIGHT  :float = 0.2;       # (a blade is 0.2 tall)
const DRAW_DISTANCE :float = 52.0;      # metres from the camera to a block's middle
const REBUILDS_PER_FRAME:int = 4;
const BY_SEASON     :Array[Color] = [
    Color(0.36, 0.58, 0.22), Color(0.4, 0.57, 0.2), Color(0.64, 0.52, 0.22), Color(0.66, 0.6, 0.42),
];

var _world      :World;
var _blocks     :Dictionary = {};       # block index (Vector2i) -> MultiMeshInstance3D
var _spots      :Dictionary = {};       # block index -> PackedVector3Array of its tuft positions (the render server keeps them in a buffer that can't be read back)
var _dirty      :Array[Vector2i] = [];
var _mat        :ShaderMaterial;
var _mesh       :ArrayMesh;

func _init(w:World) -> void:
    _world = w;
    _mat = WindSway.make(BY_SEASON[Climate.look(GameClock.season())], GRASS_SWAY, GRASS_HEIGHT, true);       # blades sway in the wind (WindSway)
    _mesh = _make_tuft();

func _ready() -> void:
    _world.terrain.ground_changed.connect(_on_terrain_changed);
    GameClock.season_changed.connect(_on_season);
    var n:int = Terrain.SIZE / BLOCK;
    for bz in n:
        for bx in n:
            _dirty.append(Vector2i(bx, bz));

func _on_season(s:int) -> void:
    WindSway.set_color(_mat, BY_SEASON[Climate.look(s)]);
    reload();       # the winter cover differs, so every block is rebuilt

# Rebuilds every block (a season change, or the density setting).
func reload() -> void:
    _dirty.clear();
    var n:int = Terrain.SIZE / BLOCK;
    for bz in n:
        for bx in n:
            _dirty.append(Vector2i(bx, bz));

func _on_terrain_changed(r:Rect2i) -> void:
    var lo:Vector2i = Vector2i(maxi(r.position.x, 0), maxi(r.position.y, 0)) / BLOCK;
    var hi:Vector2i = Vector2i(mini(r.end.x, Terrain.SIZE - 1), mini(r.end.y, Terrain.SIZE - 1)) / BLOCK;
    for bz in range(lo.y, hi.y + 1):
        for bx in range(lo.x, hi.x + 1):
            var b:Vector2i = Vector2i(bx, bz);
            if not _dirty.has(b):
                _dirty.append(b);

func _process(_delta:float) -> void:
    for i in mini(REBUILDS_PER_FRAME, _dirty.size()):
        _rebuild(_dirty.pop_front());

# Three crossed blades that lean a little.
func _make_tuft() -> ArrayMesh:
    var mesh:ArrayMesh = ArrayMesh.new();
    for i in 4:
        var blade:CylinderMesh = CylinderMesh.new();
        blade.top_radius = 0.0;
        blade.bottom_radius = 0.022;
        blade.height = 0.2;
        blade.radial_segments = 3;
        blade.rings = 1;
        blade.cap_bottom = false;
        var lean:Basis = Basis(Vector3.UP, i * 1.6) * Basis(Vector3.RIGHT, 0.2 + 0.05 * i);
        ResourceRenderer.add_part(mesh, blade, Transform3D(lean, lean * Vector3(0, 0.1, 0)), _mat);
    return mesh;

func _rebuild(b:Vector2i) -> void:
    var t:Terrain = _world.terrain;
    var winter:bool = Climate.is_dormant();
    var spots:Array[Vector3] = [];
    var tints:Array[float] = [];
    for z in range(b.y * BLOCK, (b.y + 1) * BLOCK):
        for x in range(b.x * BLOCK, (b.x + 1) * BLOCK):
            var c:Vector2i = Vector2i(x, z);
            if not _grassy(c):
                continue;
            var h:int = ((x * 73856093) ^ (z * 19349663)) & 0xffffff;
            var want:float = DENSITY * Settings.grass_share() * (WINTER_SHARE if winter else 1.0);
            var copies:int = floori(want) + (1 if float(h & 255) / 255.0 < want - floor(want) else 0);
            for k in copies:
                var hk:int = (h * (k + 3) + k * 40503) & 0xffffff;
                var px:float = x + float(hk & 255) / 255.0;
                var pz:float = z + float((hk >> 8) & 255) / 255.0;
                spots.append(Vector3(px, t.height_at(px, pz) - 0.02, pz));
                tints.append(0.82 + float((hk >> 16) & 255) / 255.0 * 0.18);
    var mmi:MultiMeshInstance3D = _blocks.get(b);
    if mmi == null:
        mmi = MultiMeshInstance3D.new();
        var mm:MultiMesh = MultiMesh.new();
        mm.transform_format = MultiMesh.TRANSFORM_3D;
        mm.use_colors = true;
        mm.mesh = _mesh;
        mmi.multimesh = mm;
        mmi.material_override = _mat;
        mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
        mmi.visibility_range_end = DRAW_DISTANCE;
        mmi.visibility_range_end_margin = 4.0;
        add_child(mmi);
        _blocks[b] = mmi;
    _spots[b] = PackedVector3Array(spots);
    var multi:MultiMesh = mmi.multimesh;
    multi.instance_count = spots.size();
    for i in spots.size():
        var s:float = 0.5 + tints[i] * 0.55;
        var yaw:float = float(i * 7919 % 628) / 100.0;
        multi.set_instance_transform(i, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s * 0.9, s)), spots[i]));
        multi.set_instance_color(i, Color(tints[i], tints[i], tints[i]));

# How many tufts stand in a cell.
func tufts_in_cell(c:Vector2i) -> int:
    var spots:PackedVector3Array = _spots.get(c / BLOCK, PackedVector3Array());
    var n:int = 0;
    for p in spots:
        if floori(p.x) == c.x and floori(p.z) == c.y:
            n += 1;
    return n;

# Open grass: dry, gentle, no road, field or building on it.
func _grassy(c:Vector2i) -> bool:
    var t:Terrain = _world.terrain;
    if t.is_water(c) or t.get_overlay(c) != Terrain.Overlay.NONE or _world.occupant[_world.idx(c)] != null:
        return false;
    return t.cell_height(c) >= Terrain.WATER_LEVEL + 0.5 and t.cell_slope(c) < 0.9;
