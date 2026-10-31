# ----------------------------------------------------------------
# ResourceRenderer
#     Draws every ResourceNode through one MultiMesh per kind, plus
#     floating markers over designated nodes. Rebuilds lazily.
# ----------------------------------------------------------------
class_name ResourceRenderer extends Node3D;

const DESIGNATED_TINT:Color = Color(1.0, 0.8, 0.45);
const PREVIEW_TINT:Color = Color(1.0, 0.3, 0.25);      # what a Harvest or Forage drag would mark
const CANOPY_BY_SEASON:Array[Color] = [
    Color(0.16, 0.38, 0.18), Color(0.15, 0.35, 0.16), Color(0.2, 0.34, 0.16), Color(0.55, 0.62, 0.6),
];
# Oak leaves over the year: [position in seasons (0 = first day of spring), colour]. They fall at the start of winter.
const OAK_LEAVES:Array = [
    [0.0, Color(0.45, 0.58, 0.27)], [0.6, Color(0.26, 0.48, 0.18)], [1.3, Color(0.15, 0.36, 0.15)],
    [2.0, Color(0.34, 0.47, 0.16)], [2.4, Color(0.76, 0.56, 0.14)], [2.75, Color(0.72, 0.3, 0.12)], [3.0, Color(0.5, 0.28, 0.14)],
];
# Shrubs are clumps of lobes: [centre, radius, shade]. A berry bush is low and spread; a hazel stool taller.
const BUSH_LOBES:Array = [
    [Vector3(0, 0.3, 0), 0.34, 1.0], [Vector3(0.32, 0.22, 0.1), 0.27, 0.9], [Vector3(-0.3, 0.24, 0.14), 0.28, 0.95],
    [Vector3(0.05, 0.2, -0.33), 0.27, 0.88], [Vector3(-0.1, 0.22, 0.34), 0.26, 0.92], [Vector3(0.12, 0.5, 0.0), 0.22, 1.1],
];
const HAZEL_LOBES:Array = [
    [Vector3(0, 1.15, 0), 0.34, 1.0], [Vector3(0.34, 0.9, 0.1), 0.28, 0.9], [Vector3(-0.34, 0.95, -0.1), 0.29, 0.94],
    [Vector3(0.05, 0.85, -0.36), 0.27, 0.88], [Vector3(-0.08, 0.88, 0.36), 0.27, 0.92], [Vector3(0.08, 1.6, 0.05), 0.26, 1.1],
    [Vector3(0.25, 1.45, -0.2), 0.22, 1.05], [Vector3(-0.2, 1.4, 0.15), 0.22, 1.02],
];

const BUSH_BY_SEASON:Array[Color] = [
    Color(0.3, 0.55, 0.22), Color(0.28, 0.5, 0.2), Color(0.55, 0.42, 0.2), Color(0.45, 0.42, 0.38),
];

# How far things bend in the wind: metres at the given height (the mesh's own units) in calm weather.
const PINE_SWAY :float = 0.12;
const PINE_HEIGHT:float = 3.2;
const OAK_SWAY  :float = 0.10;
const OAK_HEIGHT:float = 2.4;
const BUSH_SWAY :float = 0.04;
const BUSH_HEIGHT:float = 0.7;
const HAZEL_SWAY:float = 0.07;
const HAZEL_HEIGHT:float = 1.8;
const BIRCH_SWAY:float = 0.10;
const BIRCH_HEIGHT:float = 3.4;
const PALM_SWAY :float = 0.16;
const PALM_HEIGHT:float = 4.0;
const DEAD_SWAY :float = 0.03;
const DEAD_HEIGHT:float = 2.5;

# Birch leaves over the year (same scale as OAK_LEAVES): lighter, and yellow before the oaks turn.
const BIRCH_LEAVES:Array = [
    [0.0, Color(0.58, 0.72, 0.34)], [0.6, Color(0.4, 0.62, 0.24)], [1.3, Color(0.3, 0.52, 0.2)],
    [2.0, Color(0.5, 0.6, 0.2)], [2.4, Color(0.92, 0.76, 0.18)], [2.75, Color(0.85, 0.6, 0.14)], [3.0, Color(0.6, 0.4, 0.14)],
];
const PALM_LEAVES:Color = Color(0.3, 0.52, 0.2);

# The tree models (assets/models/trees, made by tools/make_trees.py): per kind, the files, how many variants there are,
# whether the crown is a separate layer that hides in winter (leaves), and whether it has a crown at all.
const TREE_DIR:String = "res://assets/models/trees/";
const SAPLING_UNTIL:float = 0.3;          # below this growth a tree is drawn as its sapling model
const TREE_SPECS:Dictionary = {
    &"tree":  {"file": "pine",  "variants": 3, "leaves": false, "crown": true},
    &"oak":   {"file": "oak",   "variants": 3, "leaves": true, "crown": true},
    &"birch": {"file": "birch", "variants": 2, "leaves": true, "crown": true},
    &"palm":  {"file": "palm",  "variants": 3, "leaves": false, "crown": true},
    &"dead":  {"file": "dead",  "variants": 3, "leaves": false, "crown": false},
    &"sapling_pine":  {"file": "sapling_pine",  "variants": 1, "leaves": false, "crown": true, "single": true},
    &"sapling_broad": {"file": "sapling_broad", "variants": 1, "leaves": true, "crown": true, "single": true},
    &"sapling_palm":  {"file": "sapling_palm",  "variants": 1, "leaves": false, "crown": true, "single": true},
};
const SAPLING_OF:Dictionary = {&"tree": &"sapling_pine", &"oak": &"sapling_broad", &"birch": &"sapling_broad", &"palm": &"sapling_palm"};

var _layers     :Dictionary = {};   # kind -> MultiMeshInstance3D
var _markers    :MultiMeshInstance3D;
var _canopy_mat :ShaderMaterial;
const PICKED_MUSHROOM:StringName = &"mushroom_picked";       # a render layer, not a resource kind
var _bush_mat   :ShaderMaterial;
var _oak_leaf_mat:ShaderMaterial;
var _birch_leaf_mat:ShaderMaterial;
var _palm_leaf_mat:ShaderMaterial;
var _leaf_layers:Dictionary = {};     # layer key -> MultiMeshInstance3D of the crowns that fall in winter (oaks and birches)
var _berries    :MultiMeshInstance3D;      # berries on the bushes that have fruit, one clump per bush
var _dirty      :bool = true;
var _preview_rect:Rect2i = Rect2i();
var _preview_filter:Callable = Callable();
func _ready() -> void:
    # trees, bushes and their trunks sway in the wind (WindSway); a trunk and its crown bend by the same rule, so they stay joined
    _canopy_mat = WindSway.make(CANOPY_BY_SEASON[0], PINE_SWAY, PINE_HEIGHT);
    _bush_mat = WindSway.make(BUSH_BY_SEASON[0], BUSH_SWAY, BUSH_HEIGHT);
    _oak_leaf_mat = WindSway.make(OAK_LEAVES[0][1], OAK_SWAY, OAK_HEIGHT);
    var trunk_color:Color = Color(0.4, 0.27, 0.17);
    _birch_leaf_mat = WindSway.make(BIRCH_LEAVES[0][1], BIRCH_SWAY, BIRCH_HEIGHT);
    _palm_leaf_mat = WindSway.make(PALM_LEAVES, PALM_SWAY, PALM_HEIGHT);
    var twig_mat:ShaderMaterial = WindSway.make(trunk_color, BUSH_SWAY, BUSH_HEIGHT);
    var hazel_stem_mat:ShaderMaterial = WindSway.make(trunk_color, HAZEL_SWAY, HAZEL_HEIGHT);
    WindSway.hold_snow(_canopy_mat);
    WindSway.hold_snow(_bush_mat);
    _make_tree_layers(trunk_color);

    var rock_shape:SphereMesh = SphereMesh.new();
    rock_shape.radius = 0.7;
    rock_shape.height = 1.0;
    rock_shape.radial_segments = 6;
    rock_shape.rings = 3;
    var rock:ArrayMesh = ArrayMesh.new();
    add_part(rock, rock_shape, Transform3D(Basis(), Vector3(0, 0.25, 0)), _make_material(Color(0.55, 0.54, 0.52)));
    var ore:ArrayMesh = ArrayMesh.new();
    # an outcrop: a dark boulder with rusty iron seams breaking out of it and a few bright metallic flecks
    add_part(ore, rock_shape, Transform3D(Basis(), Vector3(0, 0.25, 0)), _make_material(Color(0.36, 0.35, 0.36)));
    var rust_mat:StandardMaterial3D = _make_material(Color(0.66, 0.31, 0.16));
    var glint_mat:StandardMaterial3D = _make_material(Color(0.72, 0.74, 0.78));
    glint_mat.metallic = 0.7;
    glint_mat.roughness = 0.35;
    for k in 6:
        var chunk:BoxMesh = BoxMesh.new();
        var cs:float = 0.2 + 0.07 * (k % 3);
        chunk.size = Vector3(cs, cs * 1.5, cs * 0.8);
        var turn:Basis = Basis(Vector3.UP, k * 1.1) * Basis(Vector3.RIGHT, 0.5 + 0.15 * (k % 2)) * Basis(Vector3.FORWARD, 0.3 * (k % 3));
        var spot:Vector3 = Vector3(sin(k * 1.9) * 0.42, 0.3 + 0.08 * (k % 3) + (0.2 if k < 2 else 0.0), cos(k * 1.9) * 0.4);
        add_part(ore, chunk, Transform3D(turn, spot), rust_mat, Color(1.0, 0.85 + 0.05 * (k % 3), 0.85));
    for k in 3:
        var fleck:BoxMesh = BoxMesh.new();
        fleck.size = Vector3(0.1, 0.1, 0.1);
        var fturn:Basis = Basis(Vector3.UP, k * 2.3) * Basis(Vector3.RIGHT, 0.7);
        add_part(ore, fleck, Transform3D(fturn, Vector3(sin(k * 2.6 + 0.5) * 0.5, 0.42 + 0.06 * k, cos(k * 2.6 + 0.5) * 0.45)), glint_mat);

    var bush:ArrayMesh = ArrayMesh.new();
    add_lobes(bush, BUSH_LOBES, _bush_mat);
    for k in 5:                                  # a few bare twigs at the foot
        var twig:CylinderMesh = CylinderMesh.new();
        twig.top_radius = 0.01;
        twig.bottom_radius = 0.028;
        twig.height = 0.34;
        twig.radial_segments = 3;
        twig.rings = 1;
        var lean:Basis = Basis(Vector3.UP, k * 1.9) * Basis(Vector3.RIGHT, 0.55);
        add_part(bush, twig, Transform3D(lean, Vector3(0, 0.1, 0) + lean * Vector3(0, 0.12, 0)), twig_mat, Color(0.8, 0.8, 0.8));

    var cap_shape:SphereMesh = SphereMesh.new();
    cap_shape.radius = 0.22;
    cap_shape.height = 0.3;
    cap_shape.radial_segments = 6;
    cap_shape.rings = 3;
    var mushroom:ArrayMesh = ArrayMesh.new();       # ripe: stems with caps
    var picked:ArrayMesh = ArrayMesh.new();         # picked: just the stumps left in the ground
    var stem_mat:StandardMaterial3D = _make_material(Color(0.88, 0.84, 0.74));
    var spots:Array = [[Vector3(-0.2, 0, 0.1), Color(0.72, 0.5, 0.3)], [Vector3(0.15, 0, -0.1), Color(0.8, 0.35, 0.25)], [Vector3(0.05, 0, 0.25), Color(0.72, 0.5, 0.3)]];
    for spot in spots:
        var at:Vector3 = spot[0];
        var stem:CylinderMesh = CylinderMesh.new();
        stem.top_radius = 0.045;
        stem.bottom_radius = 0.06;
        stem.height = 0.16;
        stem.radial_segments = 5;
        stem.rings = 1;
        add_part(mushroom, stem, Transform3D(Basis(), at + Vector3(0, 0.08, 0)), stem_mat);
        add_part(mushroom, cap_shape, Transform3D(Basis(), at + Vector3(0, 0.17, 0)), _make_material(spot[1]));
        var stump:CylinderMesh = CylinderMesh.new();
        stump.top_radius = 0.04;
        stump.bottom_radius = 0.055;
        stump.height = 0.04;
        stump.radial_segments = 5;
        stump.rings = 1;
        add_part(picked, stump, Transform3D(Basis(), at + Vector3(0, 0.02, 0)), stem_mat, Color(0.8, 0.75, 0.65));
    var hazel:ArrayMesh = ArrayMesh.new();
    var hazel_mat:ShaderMaterial = WindSway.make(Color(0.6, 0.58, 0.2), HAZEL_SWAY, HAZEL_HEIGHT);
    for k in 5:                                  # several tall stems rising from one stool
        var stem:CylinderMesh = CylinderMesh.new();
        stem.top_radius = 0.025;
        stem.bottom_radius = 0.05;
        stem.height = 1.3;
        stem.radial_segments = 4;
        stem.rings = 1;
        var tilt:Basis = Basis(Vector3.UP, k * 2.1) * Basis(Vector3.RIGHT, 0.28);
        add_part(hazel, stem, Transform3D(tilt, tilt * Vector3(0, 0.65, 0)), hazel_stem_mat);
    add_lobes(hazel, HAZEL_LOBES, hazel_mat);

    var berry_shape:SphereMesh = SphereMesh.new();
    berry_shape.radius = 0.075;
    berry_shape.height = 0.15;
    berry_shape.radial_segments = 6;
    berry_shape.rings = 3;
    var berries:ArrayMesh = ArrayMesh.new();
    var berry_mat:ShaderMaterial = WindSway.make(Color.WHITE, BUSH_SWAY, BUSH_HEIGHT);       # the colour comes from the instance, red or blue
    for k in BUSH_LOBES.size():                  # one berry on the outside of each lobe, and a second on the bigger ones
        var lobe:Array = BUSH_LOBES[k];
        var centre:Vector3 = lobe[0];
        var out:Vector3 = Vector3(centre.x, 0.0, centre.z).normalized() if Vector2(centre.x, centre.z).length() > 0.01 else Vector3.RIGHT;
        for turn in ([0.0, 1.1] if lobe[1] > 0.27 else [0.0]):
            var dir:Vector3 = (Basis(Vector3.UP, turn * (1.0 if k % 2 == 0 else -1.0)) * (out * 0.75 + Vector3.UP * 0.65)).normalized();
            add_part(berries, berry_shape, Transform3D(Basis(), centre + dir * lobe[1] * 0.97), berry_mat);
    _berries = _make_layer(berries);
    _layers[&"rock"] = _make_layer(rock);
    _layers[&"ore"] = _make_layer(ore);
    _layers[&"bush"] = _make_layer(bush);
    _layers[&"mushroom"] = _make_layer(mushroom);
    _layers[PICKED_MUSHROOM] = _make_layer(picked);
    _layers[&"hazel"] = _make_layer(hazel);

    var marker_shape:SphereMesh = SphereMesh.new();
    marker_shape.radius = 0.18;
    marker_shape.height = 0.36;
    marker_shape.radial_segments = 4;
    marker_shape.rings = 2;
    var marker_mat:StandardMaterial3D = StandardMaterial3D.new();
    marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED;
    marker_mat.albedo_color = Color(1.0, 0.6, 0.1);
    var marker:ArrayMesh = ArrayMesh.new();
    add_part(marker, marker_shape, Transform3D(), marker_mat);
    _markers = _make_layer(marker);
    _markers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;

func mark_dirty() -> void:
    _dirty = true;

# Tints the things inside rect that filter accepts, while the player is dragging out a selection (an empty rect clears it).
func set_preview(rect:Rect2i, filter:Callable) -> void:
    if rect == _preview_rect:
        return;
    _preview_rect = rect;
    _preview_filter = filter;
    _dirty = true;

func set_season(s:int) -> void:
    WindSway.set_color(_canopy_mat, CANOPY_BY_SEASON[s]);
    WindSway.set_color(_bush_mat, BUSH_BY_SEASON[s]);
    update_foliage();

# Oak and birch leaves follow the day of the year: fresh green in spring, orange and red or yellow in autumn, gone in winter.
func update_foliage() -> void:
    var f:float = GameClock.year_fraction_seasons() if Climate.data()["winter"] else 1.3;       # no winter: green all year
    for key in _leaf_layers:
        (_leaf_layers[key] as MultiMeshInstance3D).visible = f < 3.0;
    WindSway.set_color(_oak_leaf_mat, _leaf_colour(OAK_LEAVES, f));
    WindSway.set_color(_birch_leaf_mat, _leaf_colour(BIRCH_LEAVES, f));

func _leaf_colour(table:Array, f:float) -> Color:
    var col:Color = table[0][1];
    for i in range(1, table.size()):
        var a:Array = table[i - 1];
        var b:Array = table[i];
        if f <= b[0]:
            col = (a[1] as Color).lerp(b[1], inverse_lerp(a[0], b[0], f));
            break;
    return col;

# A felled tree: shows it tipping over, away from `from` (where the woodcutter stood), as its own short-lived visual. Call it
# before the node is removed.
func fell(rn:ResourceNode, from:Vector3) -> void:
    var key:StringName = _layer_key(rn);
    if not _layers.has(key) or World.instance == null:
        return;
    var parts:Array = [(_layers[key] as MultiMeshInstance3D).multimesh.mesh];
    if _leaf_layers.has(key) and (_leaf_layers[key] as MultiMeshInstance3D).visible:
        parts.append((_leaf_layers[key] as MultiMeshInstance3D).multimesh.mesh);
    var foot:Vector3 = _node_position(World.instance, rn);
    var s:float = rn.scale;
    if not rn.is_mature():
        s *= _growth_scale(rn.growth);
    var tree:FallingTree = FallingTree.new();
    add_child(tree);
    tree.setup(parts, foot, rn.yaw, s, foot - from);
    Sfx.at(&"treefall", foot);

# Whether the crowns that fall in winter are drawn now.
func leaves_visible() -> bool:
    for key in _leaf_layers:
        return (_leaf_layers[key] as MultiMeshInstance3D).visible;
    return false;

# --------------------------------
# Trees: the models, and which one a node is drawn with

# Makes a layer per tree kind and variant, and per sapling model. A layer's mesh is the trunk with the crown on a second surface; for
# kinds whose crown falls in winter the crown is a layer of its own that follows the trunk's instances.
func _make_tree_layers(trunk_color:Color) -> void:
    var trunks:Dictionary = {
        &"tree": WindSway.make(trunk_color, PINE_SWAY, PINE_HEIGHT), &"oak": WindSway.make(trunk_color, OAK_SWAY, OAK_HEIGHT),
        &"birch": WindSway.make(Color(0.88, 0.86, 0.8), BIRCH_SWAY, BIRCH_HEIGHT), &"palm": WindSway.make(Color(0.62, 0.5, 0.36), PALM_SWAY, PALM_HEIGHT),
        &"dead": WindSway.make(Color(0.52, 0.47, 0.42), DEAD_SWAY, DEAD_HEIGHT),
    };
    var crowns:Dictionary = {&"tree": _canopy_mat, &"oak": _oak_leaf_mat, &"birch": _birch_leaf_mat, &"palm": _palm_leaf_mat};
    var young:Dictionary = {&"sapling_pine": &"tree", &"sapling_broad": &"oak", &"sapling_palm": &"palm"};
    for kind in TREE_SPECS:
        var spec:Dictionary = TREE_SPECS[kind];
        var base:StringName = young.get(kind, kind);
        for v in spec["variants"]:
            var name:String = spec["file"] if spec.get("single", false) else "%s_%d" % [spec["file"], v];
            var trunk:Mesh = load("%s%s_trunk.obj" % [TREE_DIR, name]) as Mesh;
            var key:StringName = _key(kind, v);
            var mesh:ArrayMesh = ArrayMesh.new();
            _add_surface(mesh, trunk, trunks[base]);
            if spec["crown"]:
                var crown:Mesh = load("%s%s_crown.obj" % [TREE_DIR, name]) as Mesh;
                if spec["leaves"]:
                    var cm:ArrayMesh = ArrayMesh.new();
                    _add_surface(cm, crown, crowns[base]);
                    _leaf_layers[key] = _make_layer(cm);
                else:
                    _add_surface(mesh, crown, crowns[base]);
            _layers[key] = _make_layer(mesh);

static func _add_surface(target:ArrayMesh, src:Mesh, mat:Material) -> void:
    target.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, src.surface_get_arrays(0));
    target.surface_set_material(target.get_surface_count() - 1, mat);

static func _key(kind:StringName, variant:int) -> StringName:
    return StringName("%s:%d" % [kind, variant]);

# The layer a node is drawn in: a tree by kind, variant (from its cell, so it never changes) and age; picked mushrooms are their own.
func _layer_key(rn:ResourceNode) -> StringName:
    if rn.is_tree():
        var kind:StringName = rn.kind;
        if rn.growth < SAPLING_UNTIL and SAPLING_OF.has(kind):
            kind = SAPLING_OF[kind];
        return _key(kind, posmod(hash(rn.cell), int(TREE_SPECS[kind]["variants"])));
    return PICKED_MUSHROOM if rn.kind == &"mushroom" and rn.amount <= 0 else rn.kind;

# How big a young tree is drawn: saplings grow into the sapling model's full size, and then the young tree grows into the full one.
static func _growth_scale(g:float) -> float:
    if g < SAPLING_UNTIL:
        return lerpf(0.55, 1.0, g / SAPLING_UNTIL);
    return lerpf(0.5, 1.0, (g - SAPLING_UNTIL) / (1.0 - SAPLING_UNTIL));

func _process(_delta:float) -> void:
    if _dirty:
        _dirty = false;
        _rebuild();

func _rebuild() -> void:
    var world:World = World.instance;
    var by_kind:Dictionary = {};
    for k in _layers:
        by_kind[k] = [];
    var marked:Array[ResourceNode] = [];
    for rn in world.nodes:
        by_kind[_layer_key(rn)].append(rn);
        if rn.designated:
            marked.append(rn);

    for k in _layers:
        var list:Array = by_kind[k];
        var mm:MultiMesh = (_layers[k] as MultiMeshInstance3D).multimesh;
        mm.instance_count = list.size();
        var leaves:MultiMesh = (_leaf_layers[k] as MultiMeshInstance3D).multimesh if _leaf_layers.has(k) else null;
        if leaves != null:
            leaves.instance_count = list.size();
        for i in list.size():
            var rn:ResourceNode = list[i];
            var s:float = rn.scale;
            if not rn.is_mature():
                s *= _growth_scale(rn.growth);
            var tint:Color = Color.WHITE;
            if rn.regrows:
                # bushes shrink and dull as they are picked clean
                var ratio:float = float(rn.amount) / rn.max_amount;
                s *= 0.7 + 0.3 * ratio;
                tint = Color(1.0, lerpf(0.8, 1.0, 1.0 - ratio), lerpf(0.8, 1.0, 1.0 - ratio));
            if rn.designated:
                tint = DESIGNATED_TINT;
            elif _preview_rect.has_point(rn.cell) and _preview_filter.is_valid() and _preview_filter.call(rn):
                tint = PREVIEW_TINT;
            mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rn.yaw).scaled(Vector3.ONE * s), _node_position(world, rn)));
            mm.set_instance_color(i, tint);
            if leaves != null:
                leaves.set_instance_transform(i, mm.get_instance_transform(i));
                leaves.set_instance_color(i, tint);

    var fruiting:Array = (by_kind[&"bush"] as Array).filter(func(b:ResourceNode) -> bool: return b.amount > 0);
    var bm:MultiMesh = _berries.multimesh;
    bm.instance_count = fruiting.size();
    for i in fruiting.size():
        var bush:ResourceNode = fruiting[i];
        var ratio:float = float(bush.amount) / bush.max_amount;
        var s:float = bush.scale * (0.7 + 0.3 * ratio) * (0.6 + 0.4 * ratio);       # fewer berries shrink the clump
        bm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, bush.yaw).scaled(Vector3.ONE * s), _node_position(world, bush)));
        bm.set_instance_color(i, Color(0.85, 0.12, 0.18) if (bush.cell.x + bush.cell.y * 3) % 3 != 0 else Color(0.25, 0.3, 0.85));

    var mmm:MultiMesh = _markers.multimesh;
    mmm.instance_count = marked.size();
    for i in marked.size():
        var top:float = 4.2 if marked[i].is_tree() else 1.6;
        mmm.set_instance_transform(i, Transform3D(Basis(), _node_position(world, marked[i]) + Vector3(0, top, 0)));
        mmm.set_instance_color(i, Color.WHITE);

func _node_position(world:World, rn:ResourceNode) -> Vector3:
    var x:float = rn.cell.x + 0.5 + rn.offset.x;
    var z:float = rn.cell.y + 0.5 + rn.offset.y;
    return Vector3(x, world.terrain.height_at(x, z), z);

func _make_material(c:Color) -> StandardMaterial3D:
    var m:StandardMaterial3D = StandardMaterial3D.new();
    m.albedo_color = c;
    m.vertex_color_use_as_albedo = true;    # multiplies in the per-instance tint
    m.vertex_color_is_srgb = true;
    m.roughness = 0.95;
    return m;

func _make_layer(mesh:Mesh) -> MultiMeshInstance3D:
    var mm:MultiMesh = MultiMesh.new();
    mm.transform_format = MultiMesh.TRANSFORM_3D;
    mm.use_colors = true;
    mm.mesh = mesh;
    var mmi:MultiMeshInstance3D = MultiMeshInstance3D.new();
    mmi.multimesh = mm;
    add_child(mmi);
    return mmi;

# Adds a clump of squashed spheres to a mesh: lobes are [centre, radius, shade].
static func add_lobes(target:ArrayMesh, lobes:Array, mat:Material) -> void:
    for lobe in lobes:
        var ball:SphereMesh = SphereMesh.new();
        ball.radius = lobe[1];
        ball.height = lobe[1] * 1.6;
        ball.radial_segments = 7;
        ball.rings = 3;
        var shade:float = lobe[2];
        add_part(target, ball, Transform3D(Basis(), lobe[0]), mat, Color(shade, shade, shade));

# Bakes a primitive into target as a new surface, offset by xf.
# tint: multiplied into the part's colour (a little shading variation inside one mesh).
static func add_part(target:ArrayMesh, prim:PrimitiveMesh, xf:Transform3D, mat:Material, tint:Color = Color.WHITE) -> void:
    var arrays:Array = prim.get_mesh_arrays();
    var verts:PackedVector3Array = arrays[Mesh.ARRAY_VERTEX];
    var normals:PackedVector3Array = arrays[Mesh.ARRAY_NORMAL];
    for i in verts.size():
        verts[i] = xf * verts[i];
        normals[i] = (xf.basis * normals[i]).normalized();
    arrays[Mesh.ARRAY_VERTEX] = verts;
    arrays[Mesh.ARRAY_NORMAL] = normals;
    arrays[Mesh.ARRAY_TANGENT] = null;
    if tint != Color.WHITE:
        var colors:PackedColorArray = PackedColorArray();
        colors.resize(verts.size());
        colors.fill(tint);
        arrays[Mesh.ARRAY_COLOR] = colors;
    target.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays);
    target.surface_set_material(target.get_surface_count() - 1, mat);
