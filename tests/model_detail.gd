# ----------------------------------------------------------------
# Model detail test
#     The Reduced model setting also covers buildings, citizens, animals, fences, headstones and goods: choosing it swaps
#     the meshes already in the world for their `_low` twins (fewer triangles), things made afterwards use them too, and
#     choosing Full puts everything back.
#     godot --headless --path . --fixed-fps 60 res://tests/model_detail.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;

func _tris(mesh:Mesh) -> int:
    var n:int = 0;
    for s in mesh.get_surface_count():
        var arr:Array = mesh.surface_get_arrays(s);
        n += (arr[Mesh.ARRAY_INDEX].size() if arr[Mesh.ARRAY_INDEX] != null else arr[Mesh.ARRAY_VERTEX].size()) / 3;
    return n;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Weather.drought_enabled = false;
    Defs.difficulty = &"easy";
    Settings.ensure_loaded();
    var keep:int = Settings.model_detail;
    Settings.set_value("model_detail", 0);
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    await get_tree().process_frame;
    var at:Vector2i = TestSite.near(world, Vector2i(-20, -20), Vector2i(30, 14));
    var house:Building = world.place_building(&"house", at, Vector2i(3, 3), true);
    var pasture:Pasture = world.place_building(&"pasture", at + Vector2i(5, 0), Vector2i(5, 4), true) as Pasture;
    pasture.set_kind(&"sheep");
    pasture.animals = 3;
    pasture._process(0.1);
    var pile:Building = world.place_building(&"stockpile", at + Vector2i(12, 0), Vector2i(4, 4), true);
    pile.stored[&"wood"] = 40;
    pile.stored[&"wheat"] = 40;
    for c in pile.get_children():
        if c is PileGoods:
            c._timer = 0.0;
            c._process(0.0);
    var yard:Graveyard = world.place_building(&"graveyard", at + Vector2i(18, 0), Vector2i(5, 4), true) as Graveyard;
    var pawn:Pawn = world.pawns[0];
    var full_house:int = _tris(house._body.mesh);
    var full_head:int = _tris(pawn._rig._head.get_child(0).mesh);
    var full_rail:int = _tris(pasture._fence._rails.multimesh.mesh);
    _expect("a full-detail house starts from the full set", house._body.mesh.resource_path.contains("/buildings/"));
    _expect("and a citizen", pawn._rig._head.get_child(0).mesh.resource_path.contains("/citizens/"));
    Settings.set_value("model_detail", 1);
    _expect("Reduced: the house body is the reduced twin", house._body.mesh.resource_path.contains("/buildings_low/") and _tris(house._body.mesh) < full_house);
    _expect("the house's roof, door and chimney too", house._roof.mesh.resource_path.contains("/buildings_low/") and house._door.mesh.resource_path.contains("/buildings_low/"));
    _expect("a citizen's head (%d against %d triangles)" % [_tris(pawn._rig._head.get_child(0).mesh), full_head], pawn._rig._head.get_child(0).mesh.resource_path.contains("/citizens_low/") and _tris(pawn._rig._head.get_child(0).mesh) < full_head);
    _expect("a citizen's mouth, arms and legs", pawn._rig._mouth.mesh.resource_path.contains("/citizens_low/") and pawn._rig._arm_l.get_child(0).mesh.resource_path.contains("/citizens_low/"));
    _expect("the sheep", (pasture._layers[&"body"] as MultiMeshInstance3D).multimesh.mesh.resource_path.contains("/animals_low/"));
    _expect("the fence rails", pasture._fence._rails.multimesh.mesh.resource_path.contains("/structures_low/") and _tris(pasture._fence._rails.multimesh.mesh) <= full_rail);
    _expect("the headstones", yard._stones[0].multimesh.mesh.resource_path.contains("/structures_low/"));
    var goods_forms:int = 0;
    for c in pile.get_children():
        if c is PileGoods:
            for f in c._forms:
                goods_forms += 1 if (c._forms[f] as MultiMeshInstance3D).multimesh.mesh.resource_path.contains("/goods_low/") else 0;
    _expect("the goods in a stockpile (%d forms)" % goods_forms, goods_forms >= 2);
    var carried:Pawn = world.pawns[1];
    carried.carry_item = &"wood";
    carried.carry_amount = 3;
    carried._update_carry_visual();
    _expect("and what a citizen carries", carried._rig._carry.mesh.resource_path.contains("/goods_low/"));
    # new things use the reduced set
    var house2:Building = world.place_building(&"house", at + Vector2i(0, 6), Vector2i(3, 3), true);
    _expect("a house built now is reduced", house2._body.mesh.resource_path.contains("/buildings_low/"));
    var rig:PawnRig = PawnRig.new();
    add_child(rig);
    var rng:RandomNumberGenerator = RandomNumberGenerator.new();
    rng.seed = 5;
    rig.build(true, rng);
    _expect("and so is a body made now", rig._head.get_child(0).mesh.resource_path.contains("/citizens_low/"));
    rig.queue_free();
    # and back
    Settings.set_value("model_detail", 0);
    _expect("Full again: the house", house._body.mesh.resource_path.contains("/buildings/") and _tris(house._body.mesh) == full_house);
    _expect("the citizen", pawn._rig._head.get_child(0).mesh.resource_path.contains("/citizens/") and _tris(pawn._rig._head.get_child(0).mesh) == full_head);
    _expect("the sheep and the fence", (pasture._layers[&"body"] as MultiMeshInstance3D).multimesh.mesh.resource_path.contains("/animals/") and pasture._fence._rails.multimesh.mesh.resource_path.contains("/structures/"));
    _expect("the second house too", house2._body.mesh.resource_path.contains("/buildings/"));
    Settings.set_value("model_detail", keep);
    print("MODEL DETAIL %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    if ok:
        print("PASS: ", what);
    else:
        print("FAIL: ", what);
        _fails += 1;
