# ----------------------------------------------------------------
# Tree models test
#     Every tree model file loads with vertex colours; each climate grows the kinds it should (and
#     only those), temperate has all three of its kinds and dead trees; the layer a tree is drawn
#     in depends on its kind, age and cell (and is the same every time); young trees use the
#     sapling models; a felled tree tips over, lies, sinks and is gone, and holds when paused.
#     godot --headless --path . --fixed-fps 60 res://tests/tree_models.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Weather.drought_enabled = false;
    # the files
    for kind in ResourceRenderer.TREE_SPECS:
        var spec:Dictionary = ResourceRenderer.TREE_SPECS[kind];
        for v in spec["variants"]:
            var name:String = spec["file"] if spec.get("single", false) else "%s_%d" % [spec["file"], v];
            var trunk:Mesh = load("%s%s_trunk.obj" % [ResourceRenderer.TREE_DIR, name]) as Mesh;
            _expect("%s trunk loads" % name, trunk != null and (trunk.surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray).size() > 0);
            if spec["crown"]:
                _expect("%s crown loads" % name, load("%s%s_crown.obj" % [ResourceRenderer.TREE_DIR, name]) != null);
    # what each climate grows
    var keep:int = Climate.current;
    for id in [Climate.Id.TEMPERATE, Climate.Id.ARCTIC, Climate.Id.DESERT, Climate.Id.TROPICAL]:
        Climate.current = id;
        var seen:Dictionary = {};
        for i in 4000:
            var kind:StringName = Climate.pick_tree(randf_range(-1.0, 1.0), Vector2i(i, i * 7));
            seen[kind] = int(seen.get(kind, 0)) + 1;
        for e in Climate.DEFS[id]["species"]:
            _expect("%s grows %s" % [Climate.name_of(id), e[0]], seen.has(e[0]));
        for kind in seen:
            _expect("%s grows nothing it should not (%s)" % [Climate.name_of(id), kind], kind == &"dead" or Climate.DEFS[id]["species"].any(func(e:Array) -> bool: return e[0] == kind));
        var dead:float = float(seen.get(&"dead", 0)) / 4000.0;
        _expect("%s: %.0f%% dead trees, about the %.0f%% it should have" % [Climate.name_of(id), dead * 100.0, float(Climate.DEFS[id]["dead"]) * 100.0], absf(dead - float(Climate.DEFS[id]["dead"])) < 0.03);
        for i in 50:
            _expect("%s plants living trees of its own kinds" % Climate.name_of(id), Climate.plant_kind(randf()) != &"dead" and Climate.DEFS[id]["species"].any(func(e:Array) -> bool: return e[0] == Climate.plant_kind(0.0)));
            break;
    Climate.current = keep;

    # drawing
    Defs.difficulty = &"easy";
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    await get_tree().process_frame;
    var at:Vector2i = TestSite.spot(world, Vector2i(3, 3), Vector2i(-12, -12));
    var oak:ResourceNode = world.add_node(&"oak", at);
    var key:StringName = world.renderer._layer_key(oak);
    _expect("a mature oak is drawn in an oak layer", String(key).begins_with("oak:"));
    _expect("and always the same one", world.renderer._layer_key(oak) == key);
    oak.set_growth(0.1);
    _expect("a young oak is drawn as a sapling", String(world.renderer._layer_key(oak)).begins_with("sapling_broad"));
    oak.set_growth(0.5);
    _expect("a half-grown one is the oak model again", String(world.renderer._layer_key(oak)).begins_with("oak:"));
    var dead:ResourceNode = world.add_node(&"dead", at + Vector2i(2, 0));
    dead.growth = 0.1;
    _expect("a dead tree is never a sapling", String(world.renderer._layer_key(dead)).begins_with("dead:"));
    var palm:ResourceNode = world.add_node(&"palm", at + Vector2i(0, 2));
    palm.set_growth(0.1);
    _expect("palms have saplings too", String(world.renderer._layer_key(palm)).begins_with("sapling_palm"));
    world.renderer._rebuild();
    var drawn:int = 0;
    for k in world.renderer._layers:
        if String(k).begins_with("oak:") or String(k).begins_with("dead:") or String(k).begins_with("sapling"):
            drawn += (world.renderer._layers[k] as ChunkedLayer).total();
    _expect("the nodes are in the layers", drawn >= 3);

    # felling
    oak.set_growth(1.0);
    var before:int = world.renderer.get_child_count();
    var woodcutter_at:Vector3 = oak.cell_world(world) + Vector3(-2, 0, 0) if oak.has_method("cell_world") else Vector3(at.x - 2.0, 0.0, at.y + 0.5);
    world.renderer.fell(oak, woodcutter_at);
    var falling:FallingTree = null;
    for c in world.renderer.get_children():
        if c is FallingTree:
            falling = c;
    _expect("a felled tree gets a falling visual", falling != null and world.renderer.get_child_count() == before + 1);
    _expect("it starts upright", falling.angle_now() < 0.05);
    GameClock.set_speed(1);
    falling._process(FallingTree.FALL_SECONDS * 0.5 / World.fx_speed());
    var half:float = falling.angle_now();
    _expect("halfway through the time it has fallen a quarter of the way (%.2f)" % half, half > 0.2 and half < 0.9);
    falling._process(FallingTree.FALL_SECONDS * 0.5 / World.fx_speed());
    _expect("then it is lying flat (%.2f)" % falling.angle_now(), absf(falling.angle_now() - PI * 0.5) < 0.15);
    var tip:Vector3 = falling.transform * Vector3(0, 3.0, 0);
    _expect("and fell away from the woodcutter", tip.x > falling.position.x);
    GameClock.set_speed(0);
    var held:float = falling._t;
    falling._process(1.0);
    _expect("paused, it holds", is_equal_approx(falling._t, held));
    GameClock.set_speed(1);
    for i in 400:
        if is_instance_valid(falling) and not falling.is_queued_for_deletion():
            falling._process(0.05 / World.fx_speed());
    _expect("in the end it is gone", not is_instance_valid(falling) or falling.is_queued_for_deletion());
    var trunk_mat:ShaderMaterial = ((world.renderer._layers[&"oak:0"] as ChunkedLayer).mesh as ArrayMesh).surface_get_material(0) as ShaderMaterial;
    _expect("trunks and branches hold snow", float(trunk_mat.get_shader_parameter("snow_hold")) > 0.5);
    print("TREE MODELS %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    if ok:
        print("PASS: ", what);
    else:
        _fails += 1;
        print("FAIL: ", what);
