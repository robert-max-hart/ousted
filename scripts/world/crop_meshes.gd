# ----------------------------------------------------------------
# CropMeshes
#     The small plant models a field's plots are drawn with, one per
#     plant shape (grain, bush, leafy, vine). Each is a clump that
#     fills about one cell, 1 unit tall, tinted per plot through the
#     instance colour. Built once and shared.
# ----------------------------------------------------------------
class_name CropMeshes extends RefCounted;

# crop id -> plant shape; anything missing is leafy
const SHAPE_OF:Dictionary = {
    &"wheat": &"grain", &"barley": &"grain", &"beans": &"bush", &"potato": &"bush",
    &"radish": &"leafy", &"lettuce": &"leafy", &"cabbage": &"leafy", &"pumpkin": &"vine",
    &"apple": &"tree", &"pear": &"tree", &"cherry": &"tree", &"peach": &"tree", &"plum": &"tree", &"walnut": &"tree", &"pecan": &"tree",
};
const SHAPES:Array[StringName] = [&"grain", &"bush", &"leafy", &"vine"];      # drawn from the code-built meshes below; orchard trees are models

# The fruit trees (assets/models/plants/orchard_<crop>_<part>.obj, made by tools/make_plants.py): a field draws each species as a trunk,
# a crown (tinted with the leaves' colour of the season) and the fruit (shown while ripe, tinted with the crop's colour).
const ORCHARD_DIR:String = "res://assets/models/plants/";
const ORCHARD_PARTS:Array[StringName] = [&"trunk", &"crown", &"fruit"];
const BLOSSOMING:Array[StringName] = [&"apple", &"pear", &"cherry", &"peach", &"plum"];
const LEAF_TONE:Dictionary = {
    &"apple": Color(1.0, 1.0, 1.0), &"pear": Color(0.95, 1.05, 0.9), &"cherry": Color(1.0, 1.02, 0.95), &"peach": Color(0.95, 1.05, 0.85),
    &"plum": Color(0.8, 0.9, 0.85), &"walnut": Color(0.8, 0.95, 0.7), &"pecan": Color(0.85, 1.0, 0.75),
};
const LEAF_GREEN:Color = Color(0.45, 0.66, 0.3);
const BLOSSOM:Color = Color(1.0, 0.86, 0.9);
const LEAF_AUTUMN:Color = Color(0.92, 0.64, 0.2);
const ORCHARD_SWAY:float = 0.05;
const ORCHARD_HEIGHT:float = 1.6;

static var _orchard_meshes:Dictionary = {};
static var _orchard_mats:Dictionary = {};

static func orchard_mesh(crop:StringName, part:StringName) -> Mesh:
    var key:String = "%s_%s" % [crop, part];
    if not _orchard_meshes.has(key):
        _orchard_meshes[key] = load("%sorchard_%s.obj" % [ORCHARD_DIR, key]) as Mesh;
    return _orchard_meshes[key];

# One swaying material per part, shared by every orchard (the instance colour does the tinting).
static func orchard_material(part:StringName) -> ShaderMaterial:
    if not _orchard_mats.has(part):
        _orchard_mats[part] = WindSway.make(Color(0.55, 0.42, 0.3) if part == &"trunk" else Color.WHITE, ORCHARD_SWAY, ORCHARD_HEIGHT);
    return _orchard_mats[part];

# The colour of a tree's leaves now, by the day of the year: blossom in early spring (for the trees that blossom), green through the
# summer, gold in autumn. Transparent black when the crown is bare (winter, in a climate with one).
static func leaf_colour(crop:StringName) -> Color:
    var f:float = GameClock.year_fraction_seasons() if Climate.data()["winter"] else 1.3;
    if f >= 3.0:
        return Color(0, 0, 0, 0);
    var col:Color = LEAF_GREEN;
    if f < 0.7 and crop in BLOSSOMING:
        col = BLOSSOM.lerp(LEAF_GREEN, clampf(inverse_lerp(0.35, 0.7, f), 0.0, 1.0));
    elif f > 2.0:
        col = LEAF_GREEN.lerp(LEAF_AUTUMN, clampf(inverse_lerp(2.0, 2.6, f), 0.0, 1.0));
    return col * LEAF_TONE.get(crop, Color.WHITE);


static var _meshes:Dictionary = {};
static var _material:StandardMaterial3D = null;

static func shape_of(crop:StringName) -> StringName:
    return SHAPE_OF.get(crop, &"leafy");

static func material() -> StandardMaterial3D:
    if _material == null:
        _material = StandardMaterial3D.new();
        _material.vertex_color_use_as_albedo = true;
        _material.vertex_color_is_srgb = true;
        _material.roughness = 1.0;
        _material.cull_mode = BaseMaterial3D.CULL_DISABLED;
    return _material;

static func mesh_for(shape:StringName) -> ArrayMesh:
    if not _meshes.has(shape):
        _meshes[shape] = _build(shape);
    return _meshes[shape];

static func _build(shape:StringName) -> ArrayMesh:
    var mesh:ArrayMesh = ArrayMesh.new();
    var mat:StandardMaterial3D = material();
    match shape:
        &"grain":
            # a tuft of thin stalks, leaning a little, with a fat tip standing for the ear
            for i in 9:
                var a:float = i * 2.399;                    # golden angle: an even scatter
                var r:float = 0.06 + 0.3 * sqrt((i + 0.5) / 9.0);
                var base:Vector3 = Vector3(cos(a) * r, 0.0, sin(a) * r);
                var lean:Basis = Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, 0.12 + 0.05 * (i % 3));
                var stalk:CylinderMesh = CylinderMesh.new();
                stalk.top_radius = 0.004;
                stalk.bottom_radius = 0.022;
                stalk.height = 0.9 + 0.1 * (i % 3) * 0.5;
                stalk.radial_segments = 3;
                stalk.rings = 1;
                ResourceRenderer.add_part(mesh, stalk, Transform3D(lean, base + lean * Vector3(0, stalk.height * 0.5, 0)), mat);
                var ear:SphereMesh = SphereMesh.new();
                ear.radius = 0.035;
                ear.height = 0.22;
                ear.radial_segments = 4;
                ear.rings = 2;
                ResourceRenderer.add_part(mesh, ear, Transform3D(lean, base + lean * Vector3(0, stalk.height - 0.05, 0)), mat);
        &"bush":
            # a low clump of leaf blobs on short stems
            for i in 5:
                var a:float = i * 2.399;
                var r:float = 0.08 + 0.22 * (i % 3) / 2.0;
                var leaf:SphereMesh = SphereMesh.new();
                leaf.radius = 0.2;
                leaf.height = 0.34;
                leaf.radial_segments = 6;
                leaf.rings = 3;
                ResourceRenderer.add_part(mesh, leaf, Transform3D(Basis(), Vector3(cos(a) * r, 0.2 + 0.14 * (i % 2), sin(a) * r)), mat);
        &"leafy":
            # a rosette of flat leaves around a heart
            for i in 6:
                var a:float = i * TAU / 6.0;
                var leaf:SphereMesh = SphereMesh.new();
                leaf.radius = 0.19;
                leaf.height = 0.16;
                leaf.radial_segments = 6;
                leaf.rings = 2;
                var tilt:Basis = Basis(Vector3.UP, a) * Basis(Vector3.FORWARD, 0.5);
                ResourceRenderer.add_part(mesh, leaf, Transform3D(tilt, Vector3(cos(a) * 0.2, 0.22, sin(a) * 0.2)), mat);
            var heart:SphereMesh = SphereMesh.new();
            heart.radius = 0.17;
            heart.height = 0.3;
            heart.radial_segments = 6;
            heart.rings = 3;
            ResourceRenderer.add_part(mesh, heart, Transform3D(Basis(), Vector3(0, 0.2, 0)), mat);
        _:
            # vine: a couple of broad leaves and the fruit
            for i in 3:
                var a:float = 0.6 + i * 2.1;
                var leaf:SphereMesh = SphereMesh.new();
                leaf.radius = 0.24;
                leaf.height = 0.12;
                leaf.radial_segments = 6;
                leaf.rings = 2;
                ResourceRenderer.add_part(mesh, leaf, Transform3D(Basis(), Vector3(cos(a) * 0.28, 0.3, sin(a) * 0.28)), mat);
            var fruit:SphereMesh = SphereMesh.new();
            fruit.radius = 0.2;
            fruit.height = 0.32;
            fruit.radial_segments = 8;
            fruit.rings = 4;
            ResourceRenderer.add_part(mesh, fruit, Transform3D(Basis(), Vector3(0.05, 0.16, -0.05)), mat);
    return mesh;
