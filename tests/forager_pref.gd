# ----------------------------------------------------------------
# Forager preference and toolbar grouping test
#     The Forager's Hut "Pick first" choice (nearest, what the colony
#     has least of, or one food), and the build toolbar's categories.
#     godot --headless --path . --fixed-fps 60 res://tests/forager_pref.tscn
# ----------------------------------------------------------------
extends Node;

var world:World;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    var th:Building = world.town_hall;
    var spot:Vector2i = _free(&"forager", Vector2i(3, 3), th.origin + Vector2i(0, 10));
    var hut:Building = world.place_building(&"forager", spot, Vector2i(3, 3), true);
    for rn in world.nodes.duplicate():
        if hut.center_cell().distance_to(Vector2(rn.cell)) < 20.0:
            world.remove_node(rn);
    hut.settings["cap_food"] = 100000;       # the start stock is above the default cap
    var c:Vector2i = Vector2i(hut.center_cell());
    var cells:Array[Vector2i] = [];
    for k in 3:
        for z in range(-8, 9):
            var cc:Vector2i = c + Vector2i(3 + k * 3, z);
            if WildGrowth.can_grow(world, cc, &"bush") and cells.size() == k:
                cells.append(cc);
    var kinds:Array[StringName] = [&"bush", &"mushroom", &"hazel"];       # nearest to farthest
    for k in 3:
        var rn:ResourceNode = world.add_node(kinds[k], cells[k]);
        rn.amount = rn.max_amount;
    var pawn:Pawn = world.pawns[0];
    pawn.position = Vector3(c.x + 0.5, 0.0, c.y + 0.5);
    th.stored.erase(&"berries");
    th.stored.erase(&"mushrooms");
    th.stored.erase(&"hazelnuts");

    var first:Callable = func(pref:int) -> StringName:
        hut.settings["forage_pref"] = pref;
        var t:Task = world.jobs.production.forager_task(pawn);
        var kind:StringName = (t.target as ResourceNode).kind if t != null else &"";
        if t != null:
            t.on_cancel.call(pawn) if t.on_cancel.is_valid() else null;
            (t.target as ResourceNode).reserved_by = null;
        return kind;
    _expect("Nearest picks the nearest (berries)", first.call(0) == &"bush");
    _expect("Mushrooms first picks mushrooms", first.call(3) == &"mushroom");
    _expect("Hazelnuts first picks hazelnuts", first.call(4) == &"hazel");
    th.store(&"berries", 30);
    th.store(&"mushrooms", 10);
    _expect("Least of: hazelnuts (none stocked)", first.call(1) == &"hazel");
    th.store(&"hazelnuts", 20);
    _expect("Least of: mushrooms (10 against 20 and 30)", first.call(1) == &"mushroom");
    hut.settings["forage_mushroom"] = false;
    _expect("a switched-off food is never picked", first.call(3) != &"mushroom");
    hut.settings["forage_mushroom"] = true;
    for rn in world.nodes.duplicate():
        if rn.kind == &"hazel":
            world.remove_node(rn);
    _expect("a favoured food with none to pick falls back to the rest", first.call(4) != &"");

    # toolbar categories
    var hud:HUD = world.hud;
    var listed:Array = [];
    for cat in Defs.BUILD_CATEGORIES:
        listed.append_array(cat[1]);
    var menu:Array = Defs.BUILD_MENU.duplicate();
    listed.sort();
    menu.sort();
    _expect("every building is in exactly one category", listed == menu);
    _expect("no category is open at the start", hud._open_cat == -1 and not hud._build_row.visible);
    hud._cat_btns[1].pressed.emit();
    _expect("a category opens its buildings", hud._open_cat == 1 and hud._build_row.visible and (hud._tool_btns["granary"] as Button).visible and not (hud._tool_btns["house"] as Button).visible);
    hud._cat_btns[1].pressed.emit();
    _expect("pressing it again closes it", hud._open_cat == -1);
    world.tools.set_mode(PlayerTools.Mode.BUILD, &"mine");
    _expect("picking a building any other way opens its category", hud._open_cat == 3 and (hud._tool_btns["mine"] as Button).visible);
    hud._cat_btns[4].pressed.emit();
    _expect("the Town Hall button hides while one stands", not (hud._tool_btns["town_hall"] as Button).visible);
    get_tree().quit();

func _free(id:StringName, size:Vector2i, near:Vector2i) -> Vector2i:
    for r in range(0, 30):
        for dz in range(-r, r + 1, 2):
            for dx in range(-r, r + 1, 2):
                var o:Vector2i = near + Vector2i(dx, dz);
                if world.can_place(id, o, size) == "" and world.terrain.cell_slope(o) < 0.6 and world._rect_free_of_nodes(Rect2i(o, size)):
                    return o;
    return near;

func _expect(what:String, ok:bool) -> void:
    print(("PASS " if ok else "FAIL ") + what);
