# ----------------------------------------------------------------
# Animal models test
#     Every animal part loads (body, head, legs for chicken, sheep and cow; the donkey's body and leg), each
#     kind has its gait, a pasture draws its herd in three layers whose counts follow the animals and are
#     rebuilt for the new kind when it changes, a herd led along the road is one whole mesh per animal, and
#     the animal shaders are on the shared clock so they hold when the game is paused.
#     godot --headless --path . --fixed-fps 60 res://tests/animal_models.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    for kind in Animals.RIG:
        for which in Animals.PARTS:
            _expect("%s %s loads" % [kind, which], Animals.part(kind, which) != null);
        var whole:ArrayMesh = Animals.whole(kind);
        _expect("%s whole has three surfaces" % kind, whole.get_surface_count() == 3);
        _expect("%s is in the animals' table" % kind, Defs.ANIMALS.has(kind));
    for n in ["animal_donkey_body", "animal_donkey_leg"]:
        _expect("%s loads" % n, load("%s%s.obj" % [Animals.DIR, n]) != null);
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    await get_tree().process_frame;
    var at:Vector2i = TestSite.spot(world, Vector2i(6, 6), Vector2i(-14, -14));
    var p:Pasture = world.place_building(&"pasture", at, Vector2i(6, 6), true) as Pasture;
    _expect("a pasture has body, head and leg layers", p._layers.size() == 3 and p._layers.has(&"legs"));
    p.set_kind(&"sheep");
    p.animals = 5;
    p._process(0.1);
    for part in p._layers:
        _expect("the %s layer holds the five sheep" % part, (p._layers[part] as MultiMeshInstance3D).multimesh.instance_count == 5);
    _expect("and is of the sheep's models", (p._layers[&"body"] as MultiMeshInstance3D).multimesh.mesh == Animals.part(&"sheep", &"body"));
    p.animals = 0;
    p._process(0.1);
    _expect("an empty pasture draws nothing", (p._layers[&"legs"] as MultiMeshInstance3D).multimesh.instance_count == 0);
    p.set_kind(&"cow");
    _expect("changing the animal changes the models", (p._layers[&"body"] as MultiMeshInstance3D).multimesh.mesh == Animals.part(&"cow", &"body"));
    var legs:ShaderMaterial = Animals.material(&"cow", &"legs") as ShaderMaterial;
    _expect("the legs are an animal shader with the cow's gait", legs != null and absf(float(legs.get_shader_parameter("hip_y")) - 0.52) < 0.01);
    GameClock.set_speed(1);
    world.visuals._update_water(0.5);
    var running:float = float(legs.get_shader_parameter("clock"));
    GameClock.set_speed(0);
    world.visuals._update_water(0.5);
    _expect("the animal clock runs with the game and holds when it is paused", running > 0.0 and is_equal_approx(float(legs.get_shader_parameter("clock")), running));
    var herd:GuidedHerd = GuidedHerd.lead(world, &"chicken", 3, world.pawns[0]);
    _expect("a led herd is three whole animals", herd._animals.size() == 3 and (herd._animals[0] as MeshInstance3D).mesh == Animals.whole(&"chicken"));
    herd.queue_free();
    print("ANIMAL MODELS %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    if ok:
        print("PASS: ", what);
    else:
        _fails += 1;
        print("FAIL: ", what);
