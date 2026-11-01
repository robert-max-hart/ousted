# ----------------------------------------------------------------
# PawnRig
#     A citizen's body: head, torso, two arms and two legs, each an OBJ
#     in assets/models/citizens (tools/make_citizens.py) on its own joint,
#     coloured by shaders/citizen.gdshader (shirt, trousers, skin and hair
#     come from the citizen's look seed). The Pawn tells it what it is
#     doing each frame (pose) and the rig turns the joints: a walk cycle
#     with swinging arms, a different swing for each kind of work with the
#     tool in hand, both arms out front while carrying a good (shown as
#     that good), a slow breath when idle, lying down to sleep in the open.
#     Size follows age (babies and children are smaller), elders stoop and
#     go grey. Purely visual: nothing here changes the simulation.
# ----------------------------------------------------------------
class_name PawnRig extends Node3D;

enum Mode { IDLE, WALK, WORK, SLEEP, SIT, EAT, DRINK }

const DIR      :String = "res://assets/models/citizens/";
const HIP      :float = 0.55;
const NECK     :float = 0.46;
const SHOULDER_Y:float = 0.37;
const WORK_RATE:float = 7.0;          # radians a second of the work swing (Pawn._strike listens to the same clock)
const WALK_RATE:float = 9.0;
const STRIDE_PER_METRE:float = 4.6;   # radians of the leg cycle per metre walked (a full cycle is two steps, about 1.4 m): feet keep up with the ground
const MOOD_HAPPY:float = 0.7;         # at or over this the face smiles, under MOOD_SAD it frowns
const MOOD_SAD:float = 0.4;

# Joint angles at the bottom (strike) and top of a work swing, and how far the body leans, per sound id.
const SWINGS:Dictionary = {
    &"chop":   {"down": -0.7, "up": -2.6, "lean": 0.12, "bend": 0.25, "both": true, "prop": &"axe"},
    &"pick":   {"down": -0.75, "up": -2.3, "lean": 0.14, "bend": 0.2, "both": true, "prop": &"pick"},
    &"hammer": {"down": -0.55, "up": -1.9, "lean": 0.12, "bend": 0.1, "both": false, "prop": &"hammer"},
    &"anvil":  {"down": -0.5, "up": -1.7, "lean": 0.1, "bend": 0.08, "both": false, "prop": &"hammer"},
    &"dig":    {"down": -0.45, "up": -1.35, "lean": 0.5, "bend": 0.12, "both": true, "prop": &"hoe"},
    &"rustle": {"down": -1.35, "up": -1.0, "lean": 0.4, "bend": 0.05, "both": false, "prop": &"basket"},
};

const SHIRTS_M:Array[Color] = [Color(0.25, 0.35, 0.6), Color(0.3, 0.5, 0.3), Color(0.55, 0.3, 0.25), Color(0.5, 0.45, 0.3)];
const SHIRTS_F:Array[Color] = [Color(0.6, 0.3, 0.4), Color(0.55, 0.45, 0.6), Color(0.65, 0.5, 0.3), Color(0.35, 0.5, 0.55)];
const TROUSERS:Array[Color] = [Color(0.3, 0.25, 0.2), Color(0.25, 0.28, 0.35), Color(0.35, 0.3, 0.22), Color(0.22, 0.22, 0.24)];
const HAIRS:Array[Color] = [Color(0.1, 0.08, 0.06), Color(0.25, 0.15, 0.08), Color(0.4, 0.26, 0.12), Color(0.55, 0.3, 0.14), Color(0.78, 0.62, 0.3), Color(0.5, 0.35, 0.2)];
const GREY:Color = Color(0.78, 0.78, 0.8);

static var _meshes:Dictionary = {};

var _mat      :ShaderMaterial;
var _upper    :Node3D;            # everything above the hips: leans to work
var _head     :Node3D;
var _mouth    :MeshInstance3D;
var _mouth_kind:StringName = &"";
var _arm_l    :Node3D;
var _arm_r    :Node3D;
var _leg_l    :Node3D;
var _leg_r    :Node3D;
var _prop     :MeshInstance3D;
var _prop_id  :StringName = &"";
var _carry    :MeshInstance3D;
var _carry_mat:ShaderMaterial;
var _base_shirt:Color;
var _hair     :Color;
var _male     :bool = true;
var _height   :float = 1.0;       # this citizen's own build, a few percent either way
var _size_key :int = -1;
var _elder    :bool = false;

# Forgets the loaded meshes (the model detail changed).
static func drop_caches() -> void:
    _meshes.clear();

static func part(name:String) -> Mesh:
    if not _meshes.has(name):
        _meshes[name] = load("%s%s.obj" % [Settings.model_dir(DIR), name]) as Mesh;
    return _meshes[name];

# Builds the body. `rng` is seeded from the citizen's look seed.
func build(is_male:bool, rng:RandomNumberGenerator) -> void:
    _male = is_male;
    _base_shirt = (SHIRTS_M if is_male else SHIRTS_F)[rng.randi() % 4];
    _hair = HAIRS[rng.randi() % HAIRS.size()];
    var skin:Color = Color(0.93, 0.78, 0.65).darkened(rng.randf() * 0.4);
    _height = rng.randf_range(0.96, 1.04);
    var style:int;
    if is_male:
        var roll:float = rng.randf();
        style = 0 if roll < 0.5 else 4 if roll < 0.8 else 3;
    else:
        style = 1 if rng.randf() < 0.55 else 2;
    _mat = ShaderMaterial.new();
    _mat.shader = load("res://shaders/citizen.gdshader") as Shader;
    _mat.set_shader_parameter("shirt", _base_shirt);
    _mat.set_shader_parameter("trousers", TROUSERS[rng.randi() % TROUSERS.size()]);
    _mat.set_shader_parameter("skin", skin);
    _mat.set_shader_parameter("hair", _hair);

    _leg_l = _joint(self, "leg_l", Vector3(-0.085, HIP, 0.0));
    _leg_r = _joint(self, "leg_r", Vector3(0.085, HIP, 0.0));
    _upper = Node3D.new();
    _upper.position = Vector3(0, HIP, 0);
    add_child(_upper);
    _mesh_on(_upper, "torso_m" if is_male else "torso_f");
    var sx:float = 0.2 if is_male else 0.175;
    _arm_l = _joint(_upper, "arm_l", Vector3(-sx, SHOULDER_Y, 0.0));
    _arm_r = _joint(_upper, "arm_r", Vector3(sx, SHOULDER_Y, 0.0));
    _head = _joint(_upper, "head_%d" % style, Vector3(0, NECK, 0.0));
    _mouth = _mesh_on(_head, "mouth_neutral");
    _mouth_kind = &"neutral";
    _prop = MeshInstance3D.new();
    _prop.material_override = _mat;
    _prop.position = Vector3(0, -0.5, 0.0);
    _prop.visible = false;
    _arm_r.add_child(_prop);
    _carry = MeshInstance3D.new();
    _carry_mat = PileGoods.carry_material();
    _carry.material_override = _carry_mat;
    _carry.position = Vector3(0, 0.5, 0.36);
    _carry.scale = Vector3.ONE * 0.8;
    _carry.visible = false;
    add_child(_carry);
    set_stage(30.0, false, true, false);

func _joint(parent:Node3D, part_name:String, at:Vector3) -> Node3D:
    var j:Node3D = Node3D.new();
    j.position = at;
    parent.add_child(j);
    _mesh_on(j, part_name);
    return j;

func _mesh_on(parent:Node3D, part_name:String) -> MeshInstance3D:
    var mi:MeshInstance3D = MeshInstance3D.new();
    mi.mesh = part(part_name);
    mi.material_override = _mat;
    parent.add_child(mi);
    return mi;

# --------------------------------
# Look: size by age, grey elders, clothes

# The face follows the mood: a smile when happy, a frown when unhappy (babies have no mood: pass 0.55).
func set_mood(mood:float) -> void:
    var kind:StringName = &"happy" if mood >= MOOD_HAPPY else &"sad" if mood < MOOD_SAD else &"neutral";
    if kind == _mouth_kind:
        return;
    _mouth_kind = kind;
    _mouth.mesh = part("mouth_%s" % kind);

# Babies and children are smaller and grow; elders stoop and go grey.
func set_stage(age:float, baby:bool, adult:bool, elder:bool) -> void:
    var key:int = roundi(age * 4.0) + (1000 if elder else 0);
    if key == _size_key:
        return;
    _size_key = key;
    var s:float = 1.0;
    if baby:
        s = 0.42;
    elif not adult:
        s = lerpf(0.58, 0.92, clampf((age - Defs.BABY_UNTIL) / maxf(1.0, Defs.ADULT_AT - Defs.BABY_UNTIL), 0.0, 1.0));
    scale = Vector3.ONE * s * _height;
    _elder = elder;
    _mat.set_shader_parameter("hair", _hair.lerp(GREY, 0.75 if elder else 0.0));

# Wears clothes of an item (see Defs.ITEMS "clothing"), or the plain shirt for &"".
func set_clothing(item:StringName) -> void:
    var c:Color = _base_shirt;
    if item != &"" and Defs.ITEMS.has(item):
        c = _base_shirt.lerp(Defs.ITEMS[item]["color"], 0.7);
    _mat.set_shader_parameter("shirt", c);

# Shows the good being carried (or none).
func set_carry(item:StringName, amount:int) -> void:
    _carry.visible = amount > 0 and item != &"";
    if _carry.visible:
        _carry.mesh = PileGoods.mesh_for(PileGoods.form_of(item));
        _carry_mat.set_shader_parameter("item_tint", Defs.ITEMS[item].get("color", Color.GRAY));

# --------------------------------
# Posing

# One frame of animation. `t` is the animation clock (it runs at the game speed), `k` how quickly joints settle (0 to 1),
# `work` is the sound id of the work being done (&"" for none, see Pawn._work_sound) and `carrying` whether goods are held.
func pose(mode:Mode, t:float, k:float, work:StringName, carrying:bool, stride:float = -1.0) -> void:
    var ang:Dictionary = {"ll": 0.0, "lr": 0.0, "al": 0.0, "ar": 0.0, "lean": 0.0, "z": 0.05, "head": 0.0, "head_y": 0.0, "y": 0.0};
    var lie:float = 0.0;
    var prop:StringName = &"";
    var stoop:float = 0.14 if _elder else 0.0;
    var swing:float = sin(t * WALK_RATE if stride < 0.0 else stride);       # (the stride is the distance walked, in radians of the cycle)
    var sit:float = 0.0;
    match mode:
        Mode.WALK:
            ang["ll"] = swing * 0.7;
            ang["lr"] = -swing * 0.7;
            ang["al"] = -swing * 0.55;
            ang["ar"] = swing * 0.55;
            ang["lean"] = 0.05 + stoop;
            ang["y"] = 0.045 * absf(swing);
            ang["head_y"] = 0.0;
            if carrying:
                ang["al"] = -1.15;
                ang["ar"] = -1.15;
                ang["lean"] = 0.0 + stoop * 0.5;
        Mode.WORK:
            var sw:Dictionary = SWINGS.get(work, SWINGS[&"dig"]);
            prop = sw["prop"];
            var u:float = (sin(t * WORK_RATE) + 1.0) * 0.5;       # 0 at the strike, 1 at the top of the swing
            var a:float = lerpf(sw["down"], sw["up"], u);
            ang["ar"] = a;
            ang["al"] = a * 0.92 if sw["both"] else -0.9 + 0.1 * sin(t * WORK_RATE);
            ang["lean"] = sw["lean"] + sw["bend"] * (1.0 - u) + stoop;
            ang["ll"] = 0.18;
            ang["lr"] = -0.12;
            ang["head"] = -0.15 * (1.0 - u);
            ang["y"] = -0.03 * (1.0 - u);
            if work == &"rustle":
                ang["al"] = lerpf(-1.3, -1.0, u);
                ang["ar"] = lerpf(-1.1, -1.5, u);
        Mode.SLEEP:
            lie = 1.0;
            ang["al"] = -0.15;
            ang["ar"] = 0.1;
        Mode.SIT, Mode.EAT:
            # sitting on the ground, legs out in front, hands on the knees; eating brings a hand to the mouth now and then
            sit = 1.0;
            ang["ll"] = -1.5;
            ang["lr"] = -1.42;
            ang["lean"] = 0.08 + stoop;
            ang["al"] = -0.65;
            ang["ar"] = -0.6;
            ang["head_y"] = 0.3 * sin(t * 0.5) * (0.5 + 0.5 * sin(t * 0.19));
            if mode == Mode.EAT:
                var bite:float = (sin(t * 4.2) + 1.0) * 0.5;
                ang["ar"] = lerpf(-0.5, -2.05, bite);
                ang["al"] = -0.55;
                ang["head"] = 0.08 * bite;
                ang["head_y"] = 0.0;
            else:
                ang["lean"] += 0.01 * sin(t * 1.6);
        Mode.DRINK:
            # bent over, cupped hands scooped up to the mouth
            var scoop:float = (sin(t * 3.4) + 1.0) * 0.5;
            ang["lean"] = lerpf(0.75, 0.5, scoop) + stoop;
            ang["al"] = lerpf(-1.2, -1.95, scoop);
            ang["ar"] = lerpf(-1.25, -1.9, scoop);
            ang["ll"] = 0.12;
            ang["lr"] = -0.1;
            ang["head"] = lerpf(0.15, 0.0, scoop);
        _:
            var breath:float = sin(t * 1.6);
            ang["lean"] = stoop + 0.01 * breath;
            ang["al"] = 0.04 * breath;
            ang["ar"] = -0.04 * breath;
            ang["head_y"] = 0.35 * sin(t * 0.45) * (0.5 + 0.5 * sin(t * 0.17));
            if carrying:
                ang["al"] = -1.15;
                ang["ar"] = -1.15;
    _set_prop(prop);
    _leg_l.rotation.x = lerpf(_leg_l.rotation.x, ang["ll"], k);
    _leg_r.rotation.x = lerpf(_leg_r.rotation.x, ang["lr"], k);
    _arm_l.rotation.x = lerpf(_arm_l.rotation.x, ang["al"], k);
    _arm_r.rotation.x = lerpf(_arm_r.rotation.x, ang["ar"], k);
    _arm_l.rotation.z = lerpf(_arm_l.rotation.z, -0.08 if not carrying else 0.12, k);
    _arm_r.rotation.z = lerpf(_arm_r.rotation.z, 0.08 if not carrying else -0.12, k);
    _upper.rotation.x = lerpf(_upper.rotation.x, ang["lean"], k);
    _upper.position.y = lerpf(_upper.position.y, HIP + ang["y"], k);
    _head.rotation.x = lerpf(_head.rotation.x, ang["head"] - ang["lean"] * 0.5, k);
    _head.rotation.y = lerpf(_head.rotation.y, ang["head_y"], k * 0.5);
    rotation.x = lerpf(rotation.x, -PI * 0.5 * lie, 0.15);
    var low:float = 0.22 + 0.01 * sin(t * 2.0) if lie > 0.0 else (-(HIP - 0.07) if sit > 0.0 else 0.0);       # (sitting: the hips come down to the ground)
    position.y = lerpf(position.y, low, 0.15);

func _set_prop(id:StringName) -> void:
    if id == _prop_id:
        return;
    _prop_id = id;
    _prop.visible = id != &"";
    if id != &"":
        _prop.mesh = part(String(id));
