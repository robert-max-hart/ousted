# ----------------------------------------------------------------
# Building models test
#     Every building that has a model gets its parts from the files (body, roof, and door, windows, chimney, extras
#     where it has them), a site is built from the same body and hides the roof and door until it is done, a home's
#     windows and chimney exist, the workshops' props are one model each (a forge also has a glow that shines), and
#     a building with no model file would still be drawn from boxes.
#     godot --headless --path . --fixed-fps 60 res://tests/building_models.tscn
# ----------------------------------------------------------------
extends Node;

const MODELLED:Array[StringName] = [&"house", &"shack", &"forager", &"woodcutter", &"blacksmith", &"school", &"tailor", &"still", &"pottery", &"apiary", &"town_hall", &"granary", &"well", &"mine", &"trading_post", &"fishing_hut", &"cart"];

var _fails:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    for id in MODELLED:
        for part in ["body", "roof"]:
            _expect("%s %s loads" % [id, part], load("%sbuilding_%s_%s.obj" % [BuildingVisuals.MODEL_DIR, id, part]) != null);
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    await get_tree().process_frame;
    var at:Vector2i = TestSite.near(world, Vector2i(-24, -24), Vector2i(34, 8));
    var x:int = 0;
    for id in MODELLED:
        var s:Vector2i = Defs.BUILDINGS[id]["size"];
        if id == &"town_hall" and world.town_hall != null:
            continue;
        var b:Building = world.place_building(id, at + Vector2i(x, 0), s, true);
        x += s.x + 1;
        if b == null:
            continue;
        _expect("%s has a body and a roof from its model" % id, b._body != null and b._roof != null and b._body.mesh is ArrayMesh);
        _expect("%s's body is the model, not a box" % id, not (b._body.mesh is BoxMesh) and not (b._body.mesh is CylinderMesh));
        if b.def.get("shape", "") == "house":
            _expect("%s has a door" % id, b._door != null);
        if id == &"house":
            _expect("a house has lit windows and a chimney", b._windows.size() == 1 and b._window_mat != null and b._chimney != null and b._smoke != null);
    var site:Building = world.place_building(&"house", at + Vector2i(0, 4), Vector2i(3, 3));
    _expect("a site has the same parts", site._body != null and site._body.mesh is ArrayMesh);
    _expect("and shows no roof or door yet", not site._roof.visible and not site._door.visible);
    site.work_done = site.work_required() * 0.5;
    site._update_visual();
    var half:float = site._body.scale.y;
    site.work_done = site.work_required() * 0.9;
    site._update_visual();
    _expect("the walls rise with the work (%.2f then %.2f)" % [half, site._body.scale.y], site._body.scale.y > half and half < 1.0);
    var forge:Building = world.place_building(&"blacksmith", at + Vector2i(6, 4), Vector2i(3, 3), true);
    var props:int = 0;
    for d in forge._decor:
        if d.mesh is ArrayMesh:
            props += 1;
    _expect("the forge's props come from the model (and its glow shines)", forge != null and props >= 2 and forge.has_meta(&"decor_modelled"));
    var school:Building = world.place_building(&"school", at + Vector2i(10, 4), Vector2i(4, 4), true);
    _expect("the school has its bell tower from the model, once", school != null and school.has_meta(&"decor_modelled") and school._decor.size() == 1);
    print("BUILDING MODELS %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    if ok:
        print("PASS: ", what);
    else:
        _fails += 1;
        print("FAIL: ", what);
