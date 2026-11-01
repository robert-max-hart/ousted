# ----------------------------------------------------------------
# PileGoods
#     The goods stacked on a stockpile, so what it holds and how full
#     it is can be seen: logs, split firewood, stone blocks, ingots,
#     sacks of grain, crates of produce, barrels, bales, pots and so
#     on (meshes in assets/models/goods, made by tools/make_goods.py;
#     form_of picks one per item). The more it holds, the more of them
#     and the higher they stack; each item gets its own share of the
#     squares, tinted with the item's colour. Reads the building's
#     stock twice a second and only rebuilds when what it shows would
#     change.
# ----------------------------------------------------------------
class_name PileGoods extends Node3D;

const MAX_LEVELS:int = 3;
const LEVEL     :float = 0.46;       # how high one layer of goods is (the forms are at most this tall)
const DIR       :String = "res://assets/models/goods/";
const DEFAULT_FORM:StringName = &"crate";

# The form for an item; anything not listed is a crate with its colour on top.
const FORMS:Dictionary = {
    &"wood": &"log", &"firewood": &"split", &"stone": &"block", &"coal": &"lump", &"manure": &"lump",
    &"iron": &"ingot", &"silver": &"ingot", &"gold": &"ingot",
    &"wheat": &"sack", &"barley": &"sack", &"beans": &"sack", &"hazelnuts": &"sack", &"walnuts": &"sack",
    &"pecans": &"sack", &"potato": &"sack",
    &"milk": &"barrel", &"honey": &"barrel", &"spirits": &"barrel",
    &"wool": &"bale", &"leather": &"bale", &"clothes_wool": &"bale", &"clothes_leather": &"bale", &"clothes_fine": &"bale",
    &"pottery": &"pot",
    &"tool_wood": &"tools", &"tool_iron": &"tools", &"tool_steel": &"tools",
};
const STACKED_CROSSWISE:Array[StringName] = [&"log", &"split", &"block", &"ingot", &"bale", &"tools"];   # long forms: each layer turns a quarter

static var _meshes:Dictionary = {};
static var _material:ShaderMaterial;

var _b          :Building;
var _timer      :float = 0.0;
var _shown      :String = "";
var _forms      :Dictionary = {};       # form -> MultiMeshInstance3D

static func form_of(item:StringName) -> StringName:
    return FORMS.get(item, DEFAULT_FORM);

# Forgets the loaded meshes (the model detail changed).
static func drop_caches() -> void:
    _meshes.clear();

static func mesh_for(form:StringName) -> Mesh:
    if not _meshes.has(form):
        _meshes[form] = load("%s%s.obj" % [Settings.model_dir(DIR), form]) as Mesh;
    return _meshes[form];

static func _mat() -> ShaderMaterial:
    if _material == null:
        _material = ShaderMaterial.new();
        _material.shader = load("res://shaders/goods.gdshader") as Shader;
    return _material;

# A material for one good carried by a citizen: tinted with a colour of its own (set the "item_tint" parameter).
static func carry_material() -> ShaderMaterial:
    var m:ShaderMaterial = ShaderMaterial.new();
    m.shader = load("res://shaders/goods.gdshader") as Shader;
    m.set_shader_parameter("use_item_tint", 1.0);
    return m;

func _init(b:Building) -> void:
    _b = b;
    top_level = true;

func _process(delta:float) -> void:
    _timer -= delta;
    if _timer > 0.0:
        return;
    _timer = 0.5;
    var done:bool = _b.state == Building.State.COMPLETE;
    visible = done;
    if done:
        _refresh();

# The multimesh for a form, made when first needed.
func _form_node(form:StringName) -> MultiMeshInstance3D:
    if not _forms.has(form):
        var mm:MultiMesh = MultiMesh.new();
        mm.transform_format = MultiMesh.TRANSFORM_3D;
        mm.use_colors = true;             # kept white: the item's colour goes in the custom data, so it can tint only some parts
        mm.use_custom_data = true;
        mm.mesh = mesh_for(form);
        var node:MultiMeshInstance3D = MultiMeshInstance3D.new();
        node.multimesh = mm;
        node.material_override = _mat();
        add_child(node);
        _forms[form] = node;
    return _forms[form];

func _refresh() -> void:
    var cap:int = maxi(1, _b.capacity());
    var cells:int = _b.size.x * _b.size.y;
    var items:Array = _b.stored.keys();
    items.sort();
    var counts:Array[int] = [];
    var sig:String = "%d:" % cells;
    var total:int = 0;
    for item in items:
        var n:int = roundi(float(_b.stored[item]) / cap * cells * MAX_LEVELS);
        n = maxi(n, 1 if _b.stored[item] > 0 else 0);
        counts.append(n);
        total += n;
        sig += "%s=%d," % [item, n];
    if sig == _shown:
        return;
    _shown = sig;
    total = mini(total, cells * MAX_LEVELS);
    # give each item a block of squares in proportion, then stack its goods over them
    var placed:Dictionary = {};          # form -> Array of [Transform3D, Color]
    var k:int = 0;
    var cell_at:int = 0;
    var t:Terrain = _b.world.terrain;
    for j in items.size():
        var n:int = counts[j];
        var group:int = clampi(ceili(float(n) / MAX_LEVELS), 1, maxi(1, cells - cell_at));
        var col:Color = Defs.ITEMS[items[j]].get("color", Color.GRAY);
        var form:StringName = form_of(items[j]);
        if not placed.has(form):
            placed[form] = [];
        for m in n:
            if k >= total:
                break;
            var cell_i:int = mini(cell_at + (m % group), cells - 1);       # (an over-full store still stays on its square)
            var level:int = m / group;
            var c:Vector2i = _b.origin + Vector2i(cell_i % _b.size.x, cell_i / _b.size.x);
            var jitter:float = float(hash(Vector3i(c.x, c.y, level)) & 0xff) / 255.0;
            var yaw:float = (jitter - 0.5) * 0.5;
            if form in STACKED_CROSSWISE and level % 2 == 1:
                yaw += PI * 0.5;
            var pos:Vector3 = Vector3(c.x + 0.5 + (jitter - 0.5) * 0.1, t.height_at(c.x + 0.5, c.y + 0.5) + 0.05 + LEVEL * level, c.y + 0.5 + (jitter - 0.5) * 0.08);
            placed[form].append([Transform3D(Basis(Vector3.UP, yaw), pos), col.lerp(Color.WHITE, 0.04 + jitter * 0.1)]);
            k += 1;
        cell_at += group;
    for form in placed:
        _fill(_form_node(form), placed[form]);
    for form in _forms:
        if not placed.has(form):
            (_forms[form] as MultiMeshInstance3D).multimesh.instance_count = 0;

func _fill(node:MultiMeshInstance3D, list:Array) -> void:
    var mm:MultiMesh = node.multimesh;
    mm.instance_count = list.size();
    for i in list.size():
        mm.set_instance_transform(i, list[i][0]);
        mm.set_instance_color(i, Color.WHITE);
        mm.set_instance_custom_data(i, list[i][1]);
