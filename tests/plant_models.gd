# ----------------------------------------------------------------
# Plant models test
#     Every rock, ore, shrub, mushroom and orchard model file loads; nodes of those kinds are drawn in a
#     layer chosen by kind and cell (stable); an orchard draws a trunk and crown per plot, fruit only on
#     ripe plots, blossom in early spring, a bare tree in winter; berries show on bushes with fruit.
#     godot --headless --path . --fixed-fps 60 res://tests/plant_models.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Weather.drought_enabled = false;
    for kind in ResourceRenderer.PLANT_VARIANTS:
        for v in ResourceRenderer.PLANT_VARIANTS[kind]:
            var names:Array = ["%s_%d" % [kind, v]];
            if kind == &"ore":
                names = ["ore_%d_body" % v, "ore_%d_rust" % v, "ore_%d_glint" % v];
            elif kind == &"bush":
                names = ["bush_%d_leaves" % v, "bush_%d_twigs" % v, "bush_%d_berries" % v];
            elif kind == &"hazel":
                names = ["hazel_%d_leaves" % v, "hazel_%d_stems" % v];
            for n in names:
                _expect("%s loads" % n, ResourceRenderer._plant(n) != null);
    for n in ["mushroom_ripe", "mushroom_picked"]:
        _expect("%s loads" % n, ResourceRenderer._plant(n) != null);
    for crop in CropMeshes.LEAF_TONE:
        for part in CropMeshes.ORCHARD_PARTS:
            _expect("%s %s loads" % [crop, part], CropMeshes.orchard_mesh(crop, part) != null);

    Defs.difficulty = &"easy";
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    world.seeds.unlock_all();
    await get_tree().process_frame;
    var at:Vector2i = TestSite.near(world, Vector2i(-14, -14), Vector2i(14, 12));
    for rn in world.nodes.duplicate():
        if Rect2i(at - Vector2i(2, 2), Vector2i(14, 12)).has_point(rn.cell):
            world.remove_node(rn);
    var rock:ResourceNode = world.add_node(&"rock", at);
    var key:StringName = world.renderer._layer_key(rock);
    _expect("a rock is drawn in a rock layer, always the same", String(key).begins_with("rock:") and world.renderer._layer_key(rock) == key);
    var bush:ResourceNode = world.add_node(&"bush", at + Vector2i(3, 0));
    bush.amount = 5;
    world.renderer._rebuild();
    _expect("a bush with fruit has berries", world.renderer.berry_count() >= 1);
    var with_berries:int = world.renderer.berry_count();
    bush.amount = 0;
    world.renderer._rebuild();
    _expect("a picked one has none", world.renderer.berry_count() == with_berries - 1);

    var orchard:Field = world.place_building(&"orchard", at + Vector2i(0, 4), Vector2i(4, 4), true) as Field;
    for i in orchard.plot_count():
        orchard.plot_crop[i] = &"apple";
        orchard.plot_state[i] = Field.Plot.RIPE if i < 8 else Field.Plot.PLANTED;
        orchard.growth[i] = 1.0 if i < 8 else 0.5;
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON * 1 + 3) * GameClock.HOURS_PER_DAY + 12.0;        # summer
    orchard._rebuild_crops();
    var layers:Dictionary = orchard._tree_layers[&"apple"];
    _expect("every plot has a trunk and a crown", (layers[&"trunk"] as MultiMeshInstance3D).multimesh.instance_count == 16 and (layers[&"crown"] as MultiMeshInstance3D).multimesh.instance_count == 16);
    _expect("only the ripe ones have fruit", (layers[&"fruit"] as MultiMeshInstance3D).multimesh.instance_count == 8);
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON * 0 + 1) * GameClock.HOURS_PER_DAY + 12.0;        # early spring
    _expect("apple trees blossom in early spring", CropMeshes.leaf_colour(&"apple").r > 0.9 and CropMeshes.leaf_colour(&"apple").g > 0.8);
    _expect("walnuts do not", CropMeshes.leaf_colour(&"walnut").r < 0.6);
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON * 3 + 3) * GameClock.HOURS_PER_DAY + 12.0;        # winter
    orchard._rebuild_crops();
    _expect("in winter the crowns are bare (only trunks)", (layers[&"crown"] as MultiMeshInstance3D).multimesh.instance_count == 0 and (layers[&"trunk"] as MultiMeshInstance3D).multimesh.instance_count == 16);
    Climate.current = Climate.Id.TROPICAL;
    _expect("without a winter the crowns stay", CropMeshes.leaf_colour(&"apple").a > 0.0);
    Climate.current = Climate.Id.TEMPERATE;
    print("PLANT MODELS %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    if ok:
        print("PASS: ", what);
    else:
        _fails += 1;
        print("FAIL: ", what);
