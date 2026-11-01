# ----------------------------------------------------------------
# PawnRig test
#     Every model part loads with vertex colours, a body builds for either
#     sex from many looks, the pose changes the joints, size follows age,
#     clothes change the shirt colour, carried goods show as that good, and
#     every work sound has a pose and a tool.
#     godot --headless --path . --fixed-fps 60 res://tests/pawn_rig.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;

func _ready() -> void:
    for part in ["torso_m", "torso_f", "head_0", "head_1", "head_2", "head_3", "head_4", "arm_l", "arm_r", "forearm", "leg_l", "leg_r", "shin", "axe", "hammer", "pick", "hoe", "basket"]:
        var mesh:Mesh = PawnRig.part(part);
        _expect("part %s loads" % part, mesh != null and mesh.get_surface_count() > 0);
        if mesh != null:
            _expect("part %s has colours" % part, (mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray).size() > 0);
    var rng:RandomNumberGenerator = RandomNumberGenerator.new();
    var rigs:int = 0;
    for i in 40:
        rng.seed = i;
        var rig:PawnRig = PawnRig.new();
        add_child(rig);
        rig.build(i % 2 == 0, rng);
        rigs += 1;
        rig.pose(PawnRig.Mode.WALK, 0.3, 1.0, &"", false);
        rig.queue_free();
    _expect("40 bodies build", rigs == 40);

    var rig:PawnRig = PawnRig.new();
    add_child(rig);
    rng.seed = 7;
    rig.build(true, rng);
    rig.pose(PawnRig.Mode.IDLE, 0.0, 1.0, &"", false);
    var still:float = rig._leg_l.rotation.x;
    rig.pose(PawnRig.Mode.WALK, 0.2, 1.0, &"", false);
    _expect("walking swings the legs", absf(rig._leg_l.rotation.x - still) > 0.2 and signf(rig._leg_l.rotation.x) != signf(rig._leg_r.rotation.x));
    rig.pose(PawnRig.Mode.WALK, 0.2, 1.0, &"", true);
    _expect("carrying holds the arms out front", rig._arm_l.rotation.x < -1.0 and rig._arm_r.rotation.x < -1.0);
    for id in PawnRig.SWINGS:
        var sw:Dictionary = PawnRig.SWINGS[id];
        var rate:float = PawnRig.rate_of(id);
        rig.pose(PawnRig.Mode.WORK, 1.5 * PI / rate, 1.0, id, false);            # the strike
        var down:float = rig._arm_r.rotation.x;
        rig.pose(PawnRig.Mode.WORK, 0.5 * PI / rate, 1.0, id, false);            # most of the way up the swing
        var up:float = rig._arm_r.rotation.x;
        var gentle:bool = sw["style"] == &"gentle";
        _expect("%s: the arm moves between the strike (%.2f) and the lift (%.2f)" % [id, down, up], gentle or absf(up - down) > 0.5);
        _expect("%s: the tool shown is the one it should be" % id, (rig._prop.visible and rig._prop.mesh != null) == (sw["prop"] != &""));
    rig.pose(PawnRig.Mode.IDLE, 0.0, 1.0, &"", false);
    _expect("no tool when not working", not rig._prop.visible);
    rig.pose(PawnRig.Mode.SLEEP, 0.0, 1.0, &"", false);
    for k in 30:
        rig.pose(PawnRig.Mode.SLEEP, 0.0, 1.0, &"", false);
    _expect("sleeping in the open lies down", rig.rotation.x < -1.0);
    rig.pose(PawnRig.Mode.IDLE, 0.0, 1.0, &"", false);
    for k in 60:
        rig.pose(PawnRig.Mode.IDLE, 0.0, 1.0, &"", false);

    rig.set_stage(30.0, false, true, false);
    var adult:float = rig.scale.y;
    rig.set_stage(10.0, false, false, false);
    var child:float = rig.scale.y;
    rig.set_stage(2.0, true, false, false);
    var baby:float = rig.scale.y;
    _expect("babies are smaller than children, children than adults (%.2f %.2f %.2f)" % [baby, child, adult], baby < child and child < adult);
    var plain:Color = rig._mat.get_shader_parameter("shirt");
    rig.set_clothing(&"clothes_fine");
    _expect("clothes change the shirt colour", rig._mat.get_shader_parameter("shirt") != plain);
    rig.set_clothing(&"");
    _expect("and taking them off restores it", rig._mat.get_shader_parameter("shirt") == plain);
    var hair_before:Color = rig._mat.get_shader_parameter("hair");
    rig.set_stage(70.0, false, true, true);
    _expect("elders go grey", (rig._mat.get_shader_parameter("hair") as Color).get_luminance() > hair_before.get_luminance());
    rig.set_carry(&"wood", 5);
    _expect("carried wood shows as logs", rig._carry.visible and rig._carry.mesh == PileGoods.mesh_for(&"log"));
    rig.set_carry(&"", 0);
    _expect("and hides again", not rig._carry.visible);
    # the stride follows the distance given, not the clock
    rig.pose(PawnRig.Mode.WALK, 0.0, 1.0, &"", false, 0.5);
    var a:float = rig._leg_l.rotation.x;
    rig.pose(PawnRig.Mode.WALK, 99.0, 1.0, &"", false, 0.5);
    _expect("a walk with a given stride ignores the clock", is_equal_approx(a, rig._leg_l.rotation.x));
    # sitting: legs out in front, hips down; eating lifts a hand to the mouth
    for i in 40:
        rig.pose(PawnRig.Mode.SIT, 1.0, 1.0, &"", false);
    _expect("sitting puts the legs out in front", rig._leg_l.rotation.x < -1.2 and rig._leg_r.rotation.x < -1.2);
    _expect("and the hips on the ground", rig.position.y < -0.35);
    var low_reach:float = 9.0;
    var high_reach:float = 0.0;
    for i in 60:
        rig.pose(PawnRig.Mode.EAT, i * 0.1, 1.0, &"", false);
        var reach:float = -(rig._arm_r.rotation.x + rig._fore_r.rotation.x);          # how far the hand is folded up (shoulder and elbow)
        low_reach = minf(low_reach, reach);
        high_reach = maxf(high_reach, reach);
    _expect("eating raises a hand to the mouth and lowers it again (%.2f to %.2f)" % [low_reach, high_reach], high_reach > 2.8 and low_reach < 1.3 and rig.position.y < -0.35);
    for i in 40:
        rig.pose(PawnRig.Mode.IDLE, 0.0, 1.0, &"", false);
    _expect("standing up lifts the hips again", rig.position.y > -0.05);
    rig.pose(PawnRig.Mode.DRINK, 0.3, 1.0, &"", false);
    _expect("drinking bends over", rig._upper.rotation.x > 0.4);
    # jointed limbs: knees bend one way, elbows the other, in every pose
    var worst_knee:float = 9.0;
    var worst_elbow:float = -9.0;
    for mode in [PawnRig.Mode.WALK, PawnRig.Mode.WORK, PawnRig.Mode.IDLE, PawnRig.Mode.SIT, PawnRig.Mode.EAT, PawnRig.Mode.DRINK, PawnRig.Mode.SLEEP]:
        for i in 80:
            rig.pose(mode, i * 0.11, 1.0, &"chop", i % 3 == 0, i * 0.3);
            worst_knee = minf(worst_knee, minf(rig._knee_l.rotation.x, rig._knee_r.rotation.x));
            worst_elbow = maxf(worst_elbow, maxf(rig._fore_l.rotation.x, rig._fore_r.rotation.x));
    _expect("knees never bend backwards (%.2f) and elbows never bend backwards (%.2f)" % [worst_knee, worst_elbow], worst_knee > -0.02 and worst_elbow < 0.3);
    _expect("the tool is held in the hand: it hangs from the forearm", rig._prop.get_parent() == rig._fore_r);
    # joints settle on springs: a step to a new pose overshoots a little and ends on it
    rig.pose(PawnRig.Mode.IDLE, 0.0, 1.0, &"", false);
    var top:float = 0.0;
    for i in 90:
        rig.pose(PawnRig.Mode.SIT, 1.0, 0.5, &"", false, -1.0, 1.0 / 60.0);
        top = minf(top, rig._leg_l.rotation.x);
    _expect("a leg swings to the seated pose, past it a little (%.2f against -1.5) and back" % top, top < -1.5 and top > -1.75 and absf(rig._leg_l.rotation.x + 1.5) < 0.05);
    # the face follows the mood
    rig.set_mood(0.9);
    var happy:Mesh = rig._mouth.mesh;
    rig.set_mood(0.2);
    var sad:Mesh = rig._mouth.mesh;
    rig.set_mood(0.55);
    _expect("three different mouths for happy, sad and in between", happy != sad and rig._mouth.mesh != happy and rig._mouth.mesh != sad);
    print("PAWN RIG %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    if ok:
        print("PASS: ", what);
    else:
        _fails += 1;
        print("FAIL: ", what);
