# ----------------------------------------------------------------
# ResourceRenderer
#     Draws every ResourceNode through multimeshes, one kind of model per
#     ChunkedLayer (a multimesh per 48 by 48 block, so the renderer can skip
#     the blocks out of view or past the draw distance), plus floating
#     markers over designated nodes. Rebuilds lazily. The models are the
#     full or the reduced set (Settings), and apply_settings swaps them.
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
# Rocks, ore and shrubs come in a few shapes each (assets/models/plants, made by tools/make_plants.py), chosen like a tree's.
const PLANT_DIR:String = "res://assets/models/plants/";
const PLANT_VARIANTS:Dictionary = {&"rock": 4, &"ore": 2, &"bush": 2, &"hazel": 2};
const SAPLING_OF:Dictionary = {&"tree": &"sapling_pine", &"oak": &"sapling_broad", &"birch": &"sapling_broad", &"palm": &"sapling_palm"};

var _layers     :Dictionary = {};   # layer key -> ChunkedLayer
var _trunk_color:Color = Color(0.4, 0.27, 0.17);
var _models_low :bool = false;      # which model set the layers were made from
var _leaves_on  :bool = true;
var _markers    :MultiMeshInstance3D;
var _canopy_mat :ShaderMaterial;
const PICKED_MUSHROOM:StringName = &"mushroom_picked";       # a render layer, not a resource kind
var _bush_mat   :ShaderMaterial;
var _oak_leaf_mat:ShaderMaterial;
var _birch_leaf_mat:ShaderMaterial;
var _palm_leaf_mat:ShaderMaterial;
var _leaf_layers:Dictionary = {};     # layer key -> ChunkedLayer of the crowns that fall in winter (oaks and birches)
var _berry_layers:Dictionary = {};       # bush variant -> ChunkedLayer of the berries on the bushes that have fruit, one clump per bush
var _dirty      :bool = true;
var _preview_rect:Rect2i = Rect2i();
var _preview_filter:Callable = Callable();
func _ready() -> void:
    # trees, bushes and their trunks sway in the wind (WindSway); a trunk and its crown bend by the same rule, so they stay joined
    _canopy_mat = WindSway.make(CANOPY_BY_SEASON[0], PINE_SWAY, PINE_HEIGHT);
    _bush_mat = WindSway.make(BUSH_BY_SEASON[0], BUSH_SWAY, BUSH_HEIGHT);
    _oak_leaf_mat = WindSway.make(OAK_LEAVES[0][1], OAK_SWAY, OAK_HEIGHT);
    _birch_leaf_mat = WindSway.make(BIRCH_LEAVES[0][1], BIRCH_SWAY, BIRCH_HEIGHT);
    _palm_leaf_mat = WindSway.make(PALM_LEAVES, PALM_SWAY, PALM_HEIGHT);
    WindSway.hold_snow(_canopy_mat);
    WindSway.hold_snow(_bush_mat);
    _build_models();

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

# Makes the layers for the chosen model set (full or reduced).
func _build_models() -> void:
    _models_low = Settings.models_reduced();
    _make_tree_layers(_trunk_color);
    _make_plant_layers(_trunk_color);
    for dict in [_layers, _leaf_layers, _berry_layers]:
        for key in dict:
            (dict[key] as ChunkedLayer).set_distance(Settings.draw_distance());
    for key in _leaf_layers:
        (_leaf_layers[key] as ChunkedLayer).set_shown(_leaves_on);

# Follows the Settings: the draw distance, and the model set (the layers are made again when it changes).
func apply_settings() -> void:
    if Settings.models_reduced() != _models_low:
        for dict in [_layers, _leaf_layers, _berry_layers]:
            for key in dict:
                (dict[key] as ChunkedLayer).free_all();
            dict.clear();
        _build_models();
        _dirty = true;
    for dict in [_layers, _leaf_layers, _berry_layers]:
        for key in dict:
            (dict[key] as ChunkedLayer).set_distance(Settings.draw_distance());

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
    _leaves_on = f < 3.0;
    for key in _leaf_layers:
        (_leaf_layers[key] as ChunkedLayer).set_shown(_leaves_on);
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
    var parts:Array = [(_layers[key] as ChunkedLayer).mesh];
    if _leaf_layers.has(key) and _leaves_on:
        parts.append((_leaf_layers[key] as ChunkedLayer).mesh);
    var foot:Vector3 = _node_position(World.instance, rn);
    var s:float = rn.scale;
    if not rn.is_mature():
        s *= _growth_scale(rn.growth);
    var tree:FallingTree = FallingTree.new();
    add_child(tree);
    tree.setup(parts, foot, rn.yaw, s, foot - from);
    Sfx.at(&"treefall", foot);

# How many bushes are drawn with berries on them.
func berry_count() -> int:
    var n:int = 0;
    for v in _berry_layers:
        n += (_berry_layers[v] as ChunkedLayer).total();
    return n;

# Whether the crowns that fall in winter are drawn now.
func leaves_visible() -> bool:
    return _leaves_on and not _leaf_layers.is_empty();

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
    for trunk_mat in trunks.values():
        WindSway.hold_snow(trunk_mat);       # snow lies on the branches and the root flare
    var crowns:Dictionary = {&"tree": _canopy_mat, &"oak": _oak_leaf_mat, &"birch": _birch_leaf_mat, &"palm": _palm_leaf_mat};
    var young:Dictionary = {&"sapling_pine": &"tree", &"sapling_broad": &"oak", &"sapling_palm": &"palm"};
    for kind in TREE_SPECS:
        var spec:Dictionary = TREE_SPECS[kind];
        var base:StringName = young.get(kind, kind);
        for v in spec["variants"]:
            var name:String = spec["file"] if spec.get("single", false) else "%s_%d" % [spec["file"], v];
            var trunk:Mesh = load("%s%s_trunk.obj" % [Settings.model_dir(TREE_DIR), name]) as Mesh;
            var key:StringName = _key(kind, v);
            var mesh:ArrayMesh = ArrayMesh.new();
            _add_surface(mesh, trunk, trunks[base]);
            if spec["crown"]:
                var crown:Mesh = load("%s%s_crown.obj" % [Settings.model_dir(TREE_DIR), name]) as Mesh;
                if spec["leaves"]:
                    var cm:ArrayMesh = ArrayMesh.new();
                    _add_surface(cm, crown, crowns[base]);
                    _leaf_layers[key] = ChunkedLayer.new(self, cm);
                else:
                    _add_surface(mesh, crown, crowns[base]);
            _layers[key] = ChunkedLayer.new(self, mesh);

# The layers for rocks, ore, shrubs and mushrooms, from the plant models.
func _make_plant_layers(trunk_color:Color) -> void:
    var rock_mat:ShaderMaterial = _make_rock_material(Color(0.55, 0.54, 0.52));       # snow lies on these (shaders/rock.gdshader)
    var dark_mat:ShaderMaterial = _make_rock_material(Color(0.36, 0.35, 0.36));
    var rust_mat:ShaderMaterial = WindSway.make(Color(0.66, 0.31, 0.16), 0.0, 1.0);         # (sway materials that do not sway, so they thin out with the ore body)
    var glint_mat:ShaderMaterial = WindSway.make(Color(0.72, 0.74, 0.78), 0.0, 1.0);
    glint_mat.set_shader_parameter("roughness_value", 0.4);
    var twig_mat:ShaderMaterial = WindSway.make(trunk_color, BUSH_SWAY, BUSH_HEIGHT);
    var hazel_stem_mat:ShaderMaterial = WindSway.make(trunk_color, HAZEL_SWAY, HAZEL_HEIGHT);
    var hazel_mat:ShaderMaterial = WindSway.make(Color(0.6, 0.58, 0.2), HAZEL_SWAY, HAZEL_HEIGHT);
    var berry_mat:ShaderMaterial = WindSway.make(Color.WHITE, BUSH_SWAY, BUSH_HEIGHT);       # the colour comes from the instance, red or blue
    for v in PLANT_VARIANTS[&"rock"]:
        var rock:ArrayMesh = ArrayMesh.new();
        _add_surface(rock, _plant("rock_%d" % v), rock_mat);
        _layers[_key(&"rock", v)] = ChunkedLayer.new(self, rock);
    for v in PLANT_VARIANTS[&"ore"]:       # a dark outcrop with rusty seams breaking out of it and a few bright metallic flecks
        var ore:ArrayMesh = ArrayMesh.new();
        _add_surface(ore, _plant("ore_%d_body" % v), dark_mat);
        _add_surface(ore, _plant("ore_%d_rust" % v), rust_mat);
        _add_surface(ore, _plant("ore_%d_glint" % v), glint_mat);
        _layers[_key(&"ore", v)] = ChunkedLayer.new(self, ore);
    for v in PLANT_VARIANTS[&"bush"]:
        var bush:ArrayMesh = ArrayMesh.new();
        _add_surface(bush, _plant("bush_%d_leaves" % v), _bush_mat);
        _add_surface(bush, _plant("bush_%d_twigs" % v), twig_mat);
        _layers[_key(&"bush", v)] = ChunkedLayer.new(self, bush);
        var berries:ArrayMesh = ArrayMesh.new();
        _add_surface(berries, _plant("bush_%d_berries" % v), berry_mat);
        _berry_layers[v] = ChunkedLayer.new(self, berries);
    for v in PLANT_VARIANTS[&"hazel"]:
        var hazel:ArrayMesh = ArrayMesh.new();
        _add_surface(hazel, _plant("hazel_%d_leaves" % v), hazel_mat);
        _add_surface(hazel, _plant("hazel_%d_stems" % v), hazel_stem_mat);
        _layers[_key(&"hazel", v)] = ChunkedLayer.new(self, hazel);
    var plain:ShaderMaterial = WindSway.make(Color.WHITE, 0.0, 1.0);       # (a sway material that does not sway: it thins out at the draw distance)
    var ripe:ArrayMesh = ArrayMesh.new();
    _add_surface(ripe, _plant("mushroom_ripe"), plain);
    _layers[&"mushroom"] = ChunkedLayer.new(self, ripe);
    var herb:ArrayMesh = ArrayMesh.new();
    _add_surface(herb, _plant("herb_ripe"), plain);
    _layers[&"herb"] = ChunkedLayer.new(self, herb);
    for kind in [&"lingon", &"cactus", &"date", &"banana", &"coconut"]:        # the wild foods of the other climates: one coloured model each
        var wild:ArrayMesh = ArrayMesh.new();
        _add_surface(wild, _plant("%s_ripe" % kind), plain);
        _layers[kind] = ChunkedLayer.new(self, wild);
    var picked:ArrayMesh = ArrayMesh.new();            # picked: just the stumps left in the ground
    _add_surface(picked, _plant("mushroom_picked"), plain);
    _layers[PICKED_MUSHROOM] = ChunkedLayer.new(self, picked);

static func _plant(name:String) -> Mesh:
    return load("%s%s.obj" % [Settings.model_dir(PLANT_DIR), name]) as Mesh;

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
    if PLANT_VARIANTS.has(rn.kind):
        return _key(rn.kind, posmod(hash(rn.cell), int(PLANT_VARIANTS[rn.kind])));
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
    var groups:Dictionary = {};            # layer key -> block -> the nodes drawn there
    var marked:Array[ResourceNode] = [];
    for rn in world.nodes:
        var key:StringName = _layer_key(rn);
        var blocks:Dictionary = groups.get(key, {});
        groups[key] = blocks;
        var blk:Vector2i = ChunkedLayer.block_of(rn.cell);
        if not blocks.has(blk):
            blocks[blk] = [];
        blocks[blk].append(rn);
        if rn.designated:
            marked.append(rn);

    for k in _layers:
        var layer:ChunkedLayer = _layers[k];
        var leaf_layer:ChunkedLayer = _leaf_layers.get(k);
        layer.begin();
        if leaf_layer != null:
            leaf_layer.begin();
        for blk in groups.get(k, {}):
            var list:Array = groups[k][blk];
            var mm:MultiMesh = layer.fill(blk, list.size());
            var leaves:MultiMesh = leaf_layer.fill(blk, list.size()) if leaf_layer != null else null;
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
                var xf:Transform3D = Transform3D(Basis(Vector3.UP, rn.yaw).scaled(Vector3.ONE * s), _node_position(world, rn));
                mm.set_instance_transform(i, xf);
                mm.set_instance_color(i, tint);
                if leaves != null:
                    leaves.set_instance_transform(i, xf);
                    leaves.set_instance_color(i, tint);
        layer.finish();
        if leaf_layer != null:
            leaf_layer.finish();

    var fruiting:Dictionary = {};          # bush variant -> block -> bushes with fruit on them
    for v in PLANT_VARIANTS[&"bush"]:
        fruiting[v] = {};
    for rn in world.nodes:
        if rn.kind == &"bush" and rn.amount > 0:
            var blocks:Dictionary = fruiting[posmod(hash(rn.cell), int(PLANT_VARIANTS[&"bush"]))];
            var blk:Vector2i = ChunkedLayer.block_of(rn.cell);
            if not blocks.has(blk):
                blocks[blk] = [];
            blocks[blk].append(rn);
    for v in fruiting:
        var berry_layer:ChunkedLayer = _berry_layers[v];
        berry_layer.begin();
        for blk in fruiting[v]:
            var list:Array = fruiting[v][blk];
            var bm:MultiMesh = berry_layer.fill(blk, list.size());
            for i in list.size():
                var bush:ResourceNode = list[i];
                var ratio:float = float(bush.amount) / bush.max_amount;
                var s:float = bush.scale * (0.7 + 0.3 * ratio) * (0.6 + 0.4 * ratio);       # fewer berries shrink the clump
                bm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, bush.yaw).scaled(Vector3.ONE * s), _node_position(world, bush)));
                bm.set_instance_color(i, Color(0.85, 0.12, 0.18) if (bush.cell.x + bush.cell.y * 3) % 3 != 0 else Color(0.25, 0.3, 0.85));
        berry_layer.finish();

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

# Rock and ore bodies: lit like the plain material, with snow on top (WindSway.update gives it the snow cover).
func _make_rock_material(c:Color) -> ShaderMaterial:
    var m:ShaderMaterial = ShaderMaterial.new();
    m.shader = load("res://shaders/rock.gdshader") as Shader;
    m.set_shader_parameter("albedo", c);
    m.set_meta(&"fade", -1.0);               # thins out at the draw distance like the trees
    WindSway.track(m);
    return m;

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
