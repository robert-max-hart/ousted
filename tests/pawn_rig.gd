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
    for part in ["torso_m", "torso_f", "head_0", "head_1", "head_2", "head_3", "head_4", "arm_l", "arm_r", "leg_l", "leg_r", "axe", "hammer", "pick", "hoe", "basket"]:
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
        rig.pose(PawnRig.Mode.WORK, PI / 2.0 / PawnRig.WORK_RATE * 3.0, 1.0, id, false);            # sin = -1: the strike
        var down:float = rig._arm_r.rotation.x;
        rig.pose(PawnRig.Mode.WORK, PI / 2.0 / PawnRig.WORK_RATE, 1.0, id, false);                  # sin = +1: the top
        var up:float = rig._arm_r.rotation.x;
        _expect("%s: the arm comes down at the strike (%.2f) and rises (%.2f)" % [id, down, up], up < down - 0.2 or id == &"rustle");
        _expect("%s: the tool is shown" % id, rig._prop.visible and rig._prop.mesh != null);
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
    print("PAWN RIG %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    if ok:
        print("PASS: ", what);
    else:
        _fails += 1;
        print("FAIL: ", what);
