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
#     Jointed at the hip, knee, shoulder and elbow, the neck and the waist;
#     the motion follows curves with a wind-up, a strike and a rebound
#     (RigMotion), joints settle on springs (so they overshoot a little and
#     the forearms and the head lag behind), every citizen has their own
#     tempo, build and mood in the way they move, and the ones standing
#     about shift their weight and glance round, stretch or scratch.
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
    &"chop":   {"down": -0.7, "up": -2.6, "e_down": -0.15, "e_up": -1.25, "lean": 0.12, "bend": 0.25, "both": true, "prop": &"axe", "style": &"heavy"},
    &"pick":   {"down": -0.75, "up": -2.3, "e_down": -0.15, "e_up": -1.1, "lean": 0.14, "bend": 0.2, "both": true, "prop": &"pick", "style": &"heavy"},
    &"hammer": {"down": -0.55, "up": -1.9, "e_down": -0.25, "e_up": -1.4, "lean": 0.12, "bend": 0.1, "both": false, "prop": &"hammer", "style": &"quick"},
    &"anvil":  {"down": -0.5, "up": -1.7, "e_down": -0.2, "e_up": -1.25, "lean": 0.1, "bend": 0.08, "both": false, "prop": &"hammer", "style": &"quick"},
    &"dig":    {"down": -0.45, "up": -1.35, "e_down": -0.1, "e_up": -0.55, "lean": 0.5, "bend": 0.12, "both": true, "prop": &"hoe", "style": &"push"},
    &"rustle": {"down": -1.35, "up": -1.0, "e_down": -0.7, "e_up": -0.35, "lean": 0.4, "bend": 0.05, "both": false, "prop": &"basket", "style": &"gentle"},
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
var _fore_l   :Node3D;            # the forearms hang from the elbows
var _fore_r   :Node3D;
var _leg_l    :Node3D;
var _leg_r    :Node3D;
var _knee_l   :Node3D;            # and the shins from the knees
var _knee_r   :Node3D;
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
var _young    :float = 0.0;       # 1 for a child (bouncier steps), 0 for an adult
var _val      :Dictionary = {};   # joint key -> where the spring has it
var _vel      :Dictionary = {};   # ... and how fast it is moving
var _mood     :float = 0.55;
var _energy   :float = 1.0;
var _tempo    :float = 1.0;       # this citizen's own pace and the size of their steps (a few tenths either way)
var _bounce   :float = 1.0;       # how springy they are
var _fid_rng  :RandomNumberGenerator = RandomNumberGenerator.new();
var _fid_kind :StringName = &"";  # the fidget under way while standing about (glance, stretch, scratch, hips)
var _fid_start:float = 0.0;
var _fid_end  :float = 0.0;
var _fid_next :float = 3.0;
var _fid_side :float = 1.0;
var _last_stride:float = 0.0;
var _walk_speed:float = 0.0;      # how briskly they are walking now, 0 to 1.2

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

    _tempo = rng.randf_range(0.88, 1.12);
    _bounce = rng.randf_range(0.8, 1.25);
    _fid_rng.seed = rng.randi();
    _fid_next = _fid_rng.randf_range(1.0, 8.0);
    _leg_l = _joint(self, "leg_l", Vector3(-0.085, HIP, 0.0));
    _leg_r = _joint(self, "leg_r", Vector3(0.085, HIP, 0.0));
    _knee_l = _joint(_leg_l, "shin", Vector3(0.0, -0.2, 0.0));
    _knee_r = _joint(_leg_r, "shin", Vector3(0.0, -0.2, 0.0));
    _upper = Node3D.new();
    _upper.position = Vector3(0, HIP, 0);
    add_child(_upper);
    _mesh_on(_upper, "torso_m" if is_male else "torso_f");
    var sx:float = 0.2 if is_male else 0.175;
    _arm_l = _joint(_upper, "arm_l", Vector3(-sx, SHOULDER_Y, 0.0));
    _arm_r = _joint(_upper, "arm_r", Vector3(sx, SHOULDER_Y, 0.0));
    _fore_l = _joint(_arm_l, "forearm", Vector3(0.0, -0.26, 0.0));
    _fore_r = _joint(_arm_r, "forearm", Vector3(0.0, -0.26, 0.0));
    _head = _joint(_upper, "head_%d" % style, Vector3(0, NECK, 0.0));
    _mouth = _mesh_on(_head, "mouth_neutral");
    _mouth_kind = &"neutral";
    _prop = MeshInstance3D.new();
    _prop.material_override = _mat;
    _prop.position = Vector3(0, -0.24, 0.0);          # in the right hand
    _prop.visible = false;
    _fore_r.add_child(_prop);
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
    _mood = mood;
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
    _young = 1.0 if not adult and not baby else 0.0;
    _mat.set_shader_parameter("hair", _hair.lerp(GREY, 0.75 if elder else 0.0));

# How rested they are (0 to 1): the tired shuffle and slump.
func set_energy(e:float) -> void:
    _energy = e;

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

# How fast each joint spring turns (radians a second): the body follows quickly, the hands and the head later, which gives the follow-through.
const OMEGA:Dictionary = {
    "ll": 30.0, "lr": 30.0, "kl": 28.0, "kr": 28.0, "al": 24.0, "ar": 24.0, "el": 18.0, "er": 18.0,
    "lean": 16.0, "twist": 15.0, "roll": 13.0, "head": 12.0, "head_y": 9.0, "head_z": 10.0, "y": 24.0, "azl": 12.0, "azr": 12.0,
};
const ZETA:float = 0.72;          # a little under critical damping: a joint overshoots by a few percent and settles
const FIDGETS:Array[StringName] = [&"glance", &"stretch", &"scratch", &"hips", &"glance"];
const FIDGET_SECONDS:Dictionary = {&"glance": 2.2, &"stretch": 2.6, &"scratch": 2.0, &"hips": 3.4};

# One frame of animation. `t` is the animation clock (it runs at the game speed), `work` is the sound id of the work being done
# (&"" for none, see Pawn._work_sound) and `carrying` whether goods are held. `k` under 1 lets the joints settle on their springs
# (the real time since the last frame is `dt`, taken from the engine if it is left out); 1 or more puts them straight at the pose.
func pose(mode:Mode, t:float, k:float, work:StringName, carrying:bool, stride:float = -1.0, dt:float = -1.0) -> void:
    var snap:bool = k >= 1.0;
    if dt < 0.0:
        dt = get_process_delta_time();
    var ang:Dictionary = {"ll": 0.0, "lr": 0.0, "kl": 0.06, "kr": 0.06, "al": 0.0, "ar": 0.0, "el": -0.2, "er": -0.2, "lean": 0.0, "twist": 0.0, "roll": 0.0,
            "head": 0.0, "head_y": 0.0, "head_z": 0.0, "y": 0.0, "azl": -0.08, "azr": 0.08};
    var lie:float = 0.0;
    var prop:StringName = &"";
    var sit:float = 0.0;
    var stoop:float = (0.14 if _elder else 0.0) + 0.12 * clampf((0.35 - _energy) / 0.35, 0.0, 1.0);        # elders stoop and the tired slump
    var droop:float = clampf((0.55 - _mood) * 0.5, -0.1, 0.22);                                              # an unhappy head hangs, a happy one is held up
    var spirit:float = lerpf(0.85, 1.15, clampf(_mood, 0.0, 1.0)) * lerpf(0.8, 1.0, clampf(_energy * 1.5, 0.0, 1.0));       # the spring in the step
    match mode:
        Mode.WALK:
            var phi:float = (stride if stride >= 0.0 else t * WALK_RATE) * _tempo;
            if snap:
                _walk_speed = 1.0;
            elif stride >= 0.0 and dt > 0.0:
                _walk_speed = lerpf(_walk_speed, clampf(absf(stride - _last_stride) / dt / 13.8, 0.0, 1.2), 1.0 - exp(-dt * 6.0));
            _last_stride = stride;
            var amp:float = lerpf(0.55, 1.0, clampf(_walk_speed, 0.0, 1.0)) * spirit * (1.0 + 0.2 * _young) * _tempo;
            var th:Vector2 = RigMotion.thigh(phi, amp);
            var kn:Vector2 = RigMotion.knee(phi, amp);
            var sh:Vector2 = RigMotion.shoulder(phi, amp);
            var el:Vector2 = RigMotion.elbow(phi, amp);
            ang["ll"] = th.x;
            ang["lr"] = th.y;
            ang["kl"] = kn.x;
            ang["kr"] = kn.y;
            ang["al"] = sh.x;
            ang["ar"] = sh.y;
            ang["el"] = el.x;
            ang["er"] = el.y;
            ang["y"] = RigMotion.bob(phi, amp * _bounce * (1.0 + 0.5 * _young));
            ang["twist"] = RigMotion.twist(phi, amp);
            ang["roll"] = RigMotion.roll(phi, amp);
            ang["head"] = droop;
            ang["head_y"] = -0.55 * ang["twist"];          # the eyes stay on the way ahead while the shoulders turn
            ang["head_z"] = -0.6 * ang["roll"];
            ang["lean"] = 0.04 + 0.06 * amp + stoop;
            if carrying:
                ang["al"] = -1.1 + 0.04 * cos(2.0 * phi);
                ang["ar"] = -1.1 + 0.04 * cos(2.0 * phi);
                ang["el"] = -0.35;
                ang["er"] = -0.35;
                ang["azl"] = 0.12;
                ang["azr"] = -0.12;
                ang["ll"] *= 0.8;
                ang["lr"] *= 0.8;
                ang["kl"] += 0.12;
                ang["kr"] += 0.12;
                ang["twist"] *= 0.3;
                ang["lean"] = -0.03 + stoop * 0.5;
                ang["y"] *= 1.2;
        Mode.WORK:
            var sw:Dictionary = SWINGS.get(work, SWINGS[&"dig"]);
            prop = sw["prop"];
            var u:float = RigMotion.work_u(fposmod(t * WORK_RATE, TAU) / TAU, sw["style"]);       # 0 at the strike, 1 at the top of the swing
            var low:float = clampf(1.0 - u, 0.0, 1.0);
            var a:float = lerpf(sw["down"], sw["up"], u);
            var e:float = lerpf(sw["e_down"], sw["e_up"], u);
            ang["ar"] = a;
            ang["er"] = e;
            ang["al"] = a * 0.92 if sw["both"] else -0.9 + 0.1 * sin(t * WORK_RATE);
            ang["el"] = e if sw["both"] else -0.55;
            ang["lean"] = sw["lean"] + sw["bend"] * low + stoop;
            ang["ll"] = 0.2 + 0.1 * low;
            ang["lr"] = -0.14 - 0.1 * low;
            ang["kl"] = 0.14 + 0.38 * pow(low, 1.4);       # the knees give as the tool comes down
            ang["kr"] = 0.18 + 0.32 * pow(low, 1.4);
            ang["y"] = -0.07 * pow(low, 1.5);
            ang["twist"] = 0.22 * (u - 0.45);              # the body winds up and unwinds into the blow
            ang["roll"] = 0.03 * low;
            ang["head"] = -0.15 * low + droop * 0.3;
            ang["head_y"] = -0.5 * ang["twist"];
            if work == &"rustle":
                ang["al"] = lerpf(-1.3, -1.0, u);
                ang["ar"] = lerpf(-1.1, -1.5, u);
                ang["el"] = lerpf(-0.7, -0.35, u);
                ang["er"] = lerpf(-0.45, -0.9, u);
                ang["twist"] = 0.1 * sin(t * WORK_RATE * 0.5);
        Mode.SLEEP:
            lie = 1.0;
            ang["al"] = -0.15;
            ang["ar"] = 0.1;
            ang["lean"] = 0.012 * sin(t * 1.3);
        Mode.SIT, Mode.EAT:
            # sitting on the ground, legs out in front, hands on the knees; eating brings a hand to the mouth now and then
            sit = 1.0;
            ang["ll"] = -1.5;
            ang["lr"] = -1.42;
            ang["kl"] = 0.12;
            ang["kr"] = 0.14;
            ang["lean"] = 0.08 + stoop;
            ang["al"] = -0.65;
            ang["ar"] = -0.6;
            ang["el"] = -0.45;
            ang["er"] = -0.45;
            ang["head"] = droop;
            ang["head_y"] = 0.3 * sin(t * 0.5) * (0.5 + 0.5 * sin(t * 0.19));
            if mode == Mode.EAT:
                var c:float = (sin(t * 4.2) + 1.0) * 0.5;
                var bite:float = RigMotion.ease_in_out(clampf(c * 1.5 - 0.25, 0.0, 1.0));          # lingers at the mouth and at the knee
                ang["ar"] = lerpf(-0.65, -1.15, bite);
                ang["er"] = lerpf(-0.4, -2.2, bite);
                ang["al"] = -0.55;
                ang["head"] = droop + 0.1 * bite + 0.03 * sin(t * 13.0) * bite;          # a nod to the mouthful, and the jaw going
                ang["head_y"] = 0.0;
            else:
                ang["lean"] += 0.012 * sin(t * 1.6);
                ang["roll"] = 0.02 * sin(t * 0.31);
        Mode.DRINK:
            # bent over, cupped hands scooped up to the mouth
            var scoop:float = RigMotion.ease_in_out((sin(t * 3.4) + 1.0) * 0.5);
            ang["lean"] = lerpf(0.75, 0.5, scoop) + stoop;
            ang["al"] = lerpf(-0.6, -1.0, scoop);
            ang["ar"] = lerpf(-0.62, -1.0, scoop);
            ang["el"] = lerpf(-1.3, -2.0, scoop);
            ang["er"] = lerpf(-1.3, -2.0, scoop);
            ang["ll"] = 0.12;
            ang["lr"] = -0.1;
            ang["kl"] = 0.25;
            ang["kr"] = 0.3;
            ang["head"] = lerpf(0.15, 0.0, scoop);
        _:
            var breath:float = sin(t * 1.6);
            var shift:float = tanh(3.0 * sin(t * 0.28 + _bounce * 5.0));          # the weight goes from one foot to the other every so often
            ang["lean"] = stoop + 0.012 * breath;
            ang["al"] = 0.04 * breath;
            ang["ar"] = -0.04 * breath;
            ang["el"] = -0.25 + 0.04 * breath;
            ang["er"] = -0.25 - 0.04 * breath;
            ang["roll"] = 0.045 * shift;
            ang["kl"] = 0.06 + 0.14 * maxf(0.0, shift);
            ang["kr"] = 0.06 + 0.14 * maxf(0.0, -shift);
            ang["y"] = -0.01 * absf(shift);
            ang["head"] = droop;
            ang["head_y"] = 0.35 * sin(t * 0.45) * (0.5 + 0.5 * sin(t * 0.17));
            ang["head_z"] = -0.5 * ang["roll"];
            if carrying:
                ang["al"] = -1.1;
                ang["ar"] = -1.1;
                ang["el"] = -0.35;
                ang["er"] = -0.35;
                ang["azl"] = 0.12;
                ang["azr"] = -0.12;
            else:
                _fidget(t, ang);
    if mode != Mode.IDLE:
        _fid_kind = &"";
    _set_prop(prop);
    var f:float = 1.0 if snap else 1.0 - exp(-dt * 9.0);
    _leg_l.rotation.x = _drive("ll", ang["ll"], dt, snap);
    _leg_r.rotation.x = _drive("lr", ang["lr"], dt, snap);
    _knee_l.rotation.x = _drive("kl", ang["kl"], dt, snap);
    _knee_r.rotation.x = _drive("kr", ang["kr"], dt, snap);
    _arm_l.rotation.x = _drive("al", ang["al"], dt, snap);
    _arm_r.rotation.x = _drive("ar", ang["ar"], dt, snap);
    _fore_l.rotation.x = _drive("el", ang["el"], dt, snap);
    _fore_r.rotation.x = _drive("er", ang["er"], dt, snap);
    _arm_l.rotation.z = _drive("azl", ang["azl"], dt, snap);
    _arm_r.rotation.z = _drive("azr", ang["azr"], dt, snap);
    var lean:float = _drive("lean", ang["lean"], dt, snap);
    _upper.rotation.x = lean;
    _upper.rotation.y = _drive("twist", ang["twist"], dt, snap);
    _upper.rotation.z = _drive("roll", ang["roll"], dt, snap);
    _upper.position.y = HIP + _drive("y", ang["y"], dt, snap);
    _head.rotation.x = _drive("head", ang["head"], dt, snap) - lean * 0.5;
    _head.rotation.y = _drive("head_y", ang["head_y"], dt, snap);
    _head.rotation.z = _drive("head_z", ang["head_z"], dt, snap);
    rotation.x = lerpf(rotation.x, -PI * 0.5 * lie, f if snap else 1.0 - exp(-dt * 10.0));
    var floor_y:float = 0.22 + 0.01 * sin(t * 2.0) if lie > 0.0 else (-(HIP - 0.07) if sit > 0.0 else 0.0);       # (sitting: the hips come down to the ground)
    position.y = lerpf(position.y, floor_y, f if snap else 1.0 - exp(-dt * 10.0));

# Moves a joint towards its target on a spring (a slight overshoot, and the further joints trail the nearer ones).
func _drive(key:String, target:float, dt:float, snap:bool) -> float:
    if snap or not _val.has(key):
        _val[key] = target;
        _vel[key] = 0.0;
        return target;
    var x:float = _val[key];
    var v:float = _vel[key];
    var w:float = OMEGA[key];
    var steps:int = clampi(ceili(dt * 120.0), 1, 12);
    var h:float = dt / steps;
    for i in steps:
        v += (w * w * (target - x) - 2.0 * ZETA * w * v) * h;
        x += v * h;
    _val[key] = x;
    _vel[key] = v;
    return x;

# Standing about: now and then a glance round, a stretch, a scratch of the head, or hands on hips, laid over the pose.
func _fidget(t:float, ang:Dictionary) -> void:
    if _fid_kind == &"":
        if t < _fid_next:
            return;
        _fid_kind = FIDGETS[_fid_rng.randi() % FIDGETS.size()];
        _fid_start = t;
        _fid_end = t + float(FIDGET_SECONDS[_fid_kind]);
        _fid_side = -1.0 if _fid_rng.randf() < 0.5 else 1.0;
    if t > _fid_end:
        _fid_kind = &"";
        _fid_next = t + _fid_rng.randf_range(4.0, 11.0);
        return;
    var u:float = (t - _fid_start) / (_fid_end - _fid_start);
    var env:float = RigMotion.pulse(u, 0.25, 0.7, 0.3);
    match _fid_kind:
        &"glance":
            ang["head_y"] += env * 0.95 * _fid_side;
            ang["twist"] += env * 0.12 * _fid_side;
            ang["head"] -= env * 0.04;
        &"stretch":
            ang["al"] = lerpf(ang["al"], -2.9, env);
            ang["ar"] = lerpf(ang["ar"], -2.9, env);
            ang["el"] = lerpf(ang["el"], -0.15, env);
            ang["er"] = lerpf(ang["er"], -0.15, env);
            ang["lean"] = lerpf(ang["lean"], -0.12, env);
            ang["head"] -= env * 0.25;
            ang["y"] += env * 0.02;
        &"scratch":
            ang["ar"] = lerpf(ang["ar"], -2.25, env);
            ang["er"] = lerpf(ang["er"], -2.1 + 0.3 * sin(t * 14.0), env);
            ang["head_z"] += env * 0.12;
            ang["head_y"] += env * 0.1;
        &"hips":
            ang["azl"] = lerpf(ang["azl"], -0.7, env);
            ang["azr"] = lerpf(ang["azr"], 0.7, env);
            ang["el"] = lerpf(ang["el"], -1.5, env);
            ang["er"] = lerpf(ang["er"], -1.5, env);
            ang["lean"] -= env * 0.04;

func _set_prop(id:StringName) -> void:
    if id == _prop_id:
        return;
    _prop_id = id;
    _prop.visible = id != &"";
    if id != &"":
        _prop.mesh = part(String(id));
