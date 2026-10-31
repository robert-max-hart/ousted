# ----------------------------------------------------------------
# Structure models test
#     Every fence, bridge and headstone piece loads; a wooden fence round a pasture has a post at every corner
#     point (the two ends of the gate gap taller), two rails an edge and no rail across the gap; a rope fence has
#     one rail; the stone wall has gate piers too; a bridge's deck and rails grow with its length and stand along
#     its long side whichever way it is turned; a graveyard has its three headstone models.
#     godot --headless --path . --fixed-fps 60 res://tests/structure_models.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    for kind in ["wood", "field", "rope", "stone"]:
        for part in ["post", "rail", "gate"]:
            _expect("fence %s %s loads" % [kind, part], load("%sfence_%s_%s.obj" % [Fence.DIR, kind, part]) != null);
    for n in ["bridge_deck", "bridge_rail", "bridge_post", "bridge_stilt", "headstone_0", "headstone_1", "headstone_2"]:
        _expect("%s loads" % n, load("%s%s.obj" % [Fence.DIR, n]) != null);
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    await get_tree().process_frame;
    var at:Vector2i = TestSite.near(world, Vector2i(-20, -20), Vector2i(26, 14));
    var pasture:Building = world.place_building(&"pasture", at, Vector2i(5, 4), true);
    var fence:Fence = pasture._fence;
    fence.rebuild();
    var perimeter:int = 2 * (5 + 4);
    var edges:int = perimeter - 1;                           # the gate gap is one cell
    _expect("the fence has a post at every point but the gate's two, which are tall (%d and %d)" % [fence._posts.multimesh.instance_count, fence._gates.multimesh.instance_count],
        fence._gates.multimesh.instance_count == 2 and fence._posts.multimesh.instance_count + 2 == perimeter);
    _expect("two rails along each edge", fence._rails.multimesh.instance_count == edges * 2);
    var pile:Building = world.place_building(&"stockpile", at + Vector2i(8, 0), Vector2i(4, 4), true);
    pile._fence.rebuild();
    _expect("a stockpile's rope fence has one rope along each edge and no tall posts", pile._fence._rails.multimesh.instance_count == 4 * 4 - 2 and pile._fence._gates.multimesh.instance_count == 0);
    var yard:Graveyard = world.place_building(&"graveyard", at + Vector2i(14, 0), Vector2i(5, 4), true) as Graveyard;
    yard._fence.rebuild();
    _expect("a graveyard's stone wall has gate piers", yard._fence._gates.multimesh.instance_count == 2);
    _expect("and three headstone shapes", yard._stones.size() == 3 and (yard._stones[0].multimesh.mesh as Mesh).get_surface_count() == 1);
    var short_bridge:Building = world.place_building(&"bridge", at + Vector2i(0, 8), Vector2i(3, 1), true);
    var long_bridge:Building = world.place_building(&"bridge", at + Vector2i(0, 10), Vector2i(8, 1), true);
    var turned:Building = world.place_building(&"bridge", at + Vector2i(10, 8), Vector2i(1, 8), true);
    _expect("a longer bridge has a longer deck (%.1f against %.1f)" % [long_bridge._body.mesh.get_aabb().size.x, short_bridge._body.mesh.get_aabb().size.x],
        long_bridge._body.mesh.get_aabb().size.x > short_bridge._body.mesh.get_aabb().size.x * 2.0);
    _expect("a bridge dragged along z has its deck along z", turned._body.mesh.get_aabb().size.z > 7.0 and turned._body.mesh.get_aabb().size.x < 2.0);
    _expect("and rails and stilts as decor", turned._decor.size() == 1 and (turned._decor[0].mesh as Mesh).get_aabb().size.y > 1.5);
    print("STRUCTURE MODELS %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    if ok:
        print("PASS: ", what);
    else:
        _fails += 1;
        print("FAIL: ", what);
