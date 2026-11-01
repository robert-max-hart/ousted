# ----------------------------------------------------------------
# PileGoods test
#     Every item has a form whose mesh file loads (with colours), the
#     forms in the table exist, and a stockpile with goods builds one
#     multimesh per form in use, with an instance per shown unit, and
#     clears the forms it no longer needs.
#     godot --headless --path . --fixed-fps 60 res://tests/pile_goods.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    for item in Defs.ITEMS:
        var form:StringName = PileGoods.form_of(item);
        var mesh:Mesh = PileGoods.mesh_for(form);
        _expect("%s has a mesh (%s)" % [item, form], mesh != null);
        if mesh != null:
            var arr:Array = mesh.surface_get_arrays(0);
            _expect("%s mesh has vertex colours" % form, (arr[Mesh.ARRAY_COLOR] as PackedColorArray).size() > 0);
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    await get_tree().process_frame;
    var at:Vector2i = TestSite.spot(world, Vector2i(4, 4), Vector2i(-14, -14));
    var pile:Building = world.place_building(&"stockpile", at, Vector2i(4, 4), true);
    var goods:PileGoods = null;
    for c in pile.get_children():
        if c is PileGoods:
            goods = c;
    _expect("the stockpile has its goods node", goods != null);
    pile.stored[&"wood"] = 40;
    pile.stored[&"wheat"] = 40;
    goods._timer = 0.0;
    goods._process(0.0);
    var logs:int = (goods._forms[&"log"] as MultiMeshInstance3D).multimesh.instance_count;
    var sacks:int = (goods._forms[&"sack"] as MultiMeshInstance3D).multimesh.instance_count;
    print("logs %d sacks %d forms %d" % [logs, sacks, goods._forms.size()]);
    _expect("wood shows as logs and wheat as sacks", logs > 0 and sacks > 0 and goods._forms.size() == 2);
    pile.stored.erase(&"wood");
    goods._timer = 0.0;
    goods._process(0.0);
    _expect("logs vanish when the wood is gone", (goods._forms[&"log"] as MultiMeshInstance3D).multimesh.instance_count == 0);
    # loose goods on the ground are heaped from the same forms: one good per three units, at most eight
    var spot:Vector2i = TestSite.near(world, Vector2i(-6, 6), Vector2i(1, 1));
    GroundPiles.drop_pile(world, &"wood", 1, spot);
    var gp:GroundPile = GroundPiles.pile_at(world, spot);
    _expect("a ground pile of wood exists", gp != null);
    if gp != null:
        _expect("1 unit shows one log", gp._mesh.multimesh.instance_count == 1 and gp._mesh.multimesh.mesh == PileGoods.mesh_for(&"log"));
        gp.add(8);
        _expect("9 units show 3 logs", gp._mesh.multimesh.instance_count == 3);
        gp.add(100);
        _expect("a big pile shows at most 8", gp._mesh.multimesh.instance_count == GroundPile.MAX_SHOWN);
        gp.take(gp.amount - 1);
        _expect("taking it down shows fewer", gp._mesh.multimesh.instance_count == 1);
    print("PILE GOODS %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    if ok:
        print("PASS: ", what);
    else:
        _fails += 1;
        print("FAIL: ", what);
