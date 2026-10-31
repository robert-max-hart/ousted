# ----------------------------------------------------------------
# CropMeshes
#     What a field's plots are drawn with. Field crops are models
#     (assets/models/crops, made by tools/make_crops.py): per crop a
#     young, a grown and a ripe plant, with a seedling and a withered
#     plot shared by plant class (grain, leafy, bush, vine), picked by
#     crop_key. Orchard trees are models too (orchard_*, see
#     tools/make_plants.py): trunk, crown and fruit. Also the plain
#     vertex-colour material the pasture animals use.
# ----------------------------------------------------------------
class_name CropMeshes extends RefCounted;

# crop id -> plant shape; anything missing is leafy
const SHAPE_OF:Dictionary = {
    &"wheat": &"grain", &"barley": &"grain", &"beans": &"bush", &"potato": &"bush",
    &"radish": &"leafy", &"lettuce": &"leafy", &"cabbage": &"leafy", &"pumpkin": &"vine",
    &"apple": &"tree", &"pear": &"tree", &"cherry": &"tree", &"peach": &"tree", &"plum": &"tree", &"walnut": &"tree", &"pecan": &"tree",
};
const CROP_DIR:String = "res://assets/models/crops/";
const SEEDLING_UNTIL:float = 0.25;        # growth under this: a seedling; under YOUNG_UNTIL a young plant; then a grown one (until it is ripe)
const YOUNG_UNTIL:float = 0.6;
const CROP_SWAY:float = 0.05;
const CROP_HEIGHT:float = 0.9;
static var _crop_meshes:Dictionary = {};
static var _crop_mat:ShaderMaterial = null;

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
        _orchard_meshes[key] = load("%sorchard_%s.obj" % [Settings.model_dir(ORCHARD_DIR), key]) as Mesh;
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

# The model for a plot: which of a crop's files it is drawn with now. `ripe` plots are the ripe model, withered ones the class's
# dead plot, and the rest follow growth through seedling, young and grown.
static func crop_key(crop:StringName, state:int, growth:float) -> String:
    var cls:StringName = shape_of(crop);
    if state == Field.Plot.DEAD:
        return "dead_%s" % cls;
    if state == Field.Plot.RIPE:
        return "%s_ripe" % crop;
    if growth < SEEDLING_UNTIL:
        return "sprout_%s" % cls;
    return "%s_%s" % [crop, "young" if growth < YOUNG_UNTIL else "grown"];

# How far through its stage a plant is, 0 to 1 (a ripe plant is full size): the model grows a little within its stage.
static func stage_progress(state:int, growth:float) -> float:
    if state == Field.Plot.RIPE or state == Field.Plot.DEAD:
        return 1.0;
    if growth < SEEDLING_UNTIL:
        return growth / SEEDLING_UNTIL;
    if growth < YOUNG_UNTIL:
        return (growth - SEEDLING_UNTIL) / (YOUNG_UNTIL - SEEDLING_UNTIL);
    return (growth - YOUNG_UNTIL) / (1.0 - YOUNG_UNTIL);

static func crop_model(key:String) -> Mesh:
    if not _crop_meshes.has(key):
        _crop_meshes[key] = load("%scrop_%s.obj" % [Settings.model_dir(CROP_DIR), key]) as Mesh;
    return _crop_meshes[key];

static var _loaded_low:bool = false;

# Forgets the loaded crop and orchard models when the model detail has changed (they are loaded again from the other set).
static func reload_if_needed() -> void:
    if Settings.models_reduced() != _loaded_low:
        _loaded_low = Settings.models_reduced();
        _crop_meshes.clear();
        _orchard_meshes.clear();

# The crops sway in the wind like the grass (and follow the grass sway setting).
static func crop_material() -> ShaderMaterial:
    if _crop_mat == null:
        _crop_mat = WindSway.make(Color.WHITE, CROP_SWAY, CROP_HEIGHT, true);
    return _crop_mat;
