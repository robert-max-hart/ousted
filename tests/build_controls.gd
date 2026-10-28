# ----------------------------------------------------------------
# Construction controls test
#     Cancel, build priority and pause, the shortage note, scalable
#     stockpiles, roads blocking buildings, sites clearing what is in
#     their way (not instantly), and the size text for dragged sites.
#     godot --headless --path . --fixed-fps 60 res://tests/build_controls.tscn
# ----------------------------------------------------------------
extends Node;

var world:World;
var _frame:int = 0;
var _site:Building;
var _bush:ResourceNode;
var _tree:ResourceNode;
var _start:float;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    var th:Building = world.town_hall;
    var o:Vector2i = th.origin;

    # --- stockpile scaling
    var spot:Vector2i = _free(&"stockpile", Vector2i(6, 8), o + Vector2i(-20, -20));
    var sp:Building = world.place_building(&"stockpile", spot, Vector2i(6, 8));
    _expect("a 6x8 stockpile costs by area (%s)" % sp.cost(), sp.cost()[&"wood"] == 12);
    _expect("and takes longer to build (%.1f h)" % sp.work_required(), is_equal_approx(sp.work_required(), 9.0));
    sp.complete();
    _expect("and holds more (%d)" % sp.capacity(), sp.capacity() == 450);
    var small:Building = world.place_building(&"stockpile", _free(&"stockpile", Vector2i(2, 2), o + Vector2i(-20, 10)), Vector2i(2, 2), true);
    _expect("a 2x2 holds less (%d)" % small.capacity(), small.capacity() == 38);

    # --- roads block buildings
    var rs:Vector2i = _free(&"house", Vector2i(3, 3), o + Vector2i(14, -20));
    var rcell:Vector2i = rs + Vector2i(1, 1);
    if world.node_at[world.idx(rcell)] != null:
        world.remove_node(world.node_at[world.idx(rcell)]);
    world.set_road(rcell, true);
    _expect("a road blocks a building", world.can_place(&"house", rs, Vector2i(3, 3)) != "");
    _expect("a road can't go under a building", not world.can_plan_road(th.origin));

    # --- shortage note, priority and pause
    var hs:Vector2i = _free(&"house", Vector2i(3, 3), o + Vector2i(-14, 14));
    _site = world.place_building(&"house", hs, Vector2i(3, 3));
    th.stored.erase(&"wood");
    _site.update_site_label();
    _expect("short of wood: a note shows (%s)" % _site.shortage_text(), _site.shortage_text() != "" and _site._site_label.visible);
    _expect("the inspector says so", _site.info_text().contains("Not enough in storage"));
    th.store(&"wood", 100);
    _site.update_site_label();
    _expect("stocked: the note goes", _site.shortage_text() == "" and not _site._site_label.visible);
    _site.set_priority(Building.PRIORITY_PAUSED);
    _expect("paused: the note says PAUSED", _site._site_label.visible and _site._site_label.text.begins_with("PAUSED"));
    _expect("paused sites are not hauled to", world.jobs._haul_task(world.pawns[0]) == null);
    for item in _site.cost():
        _site.delivered[item] = _site.cost()[item];
    var pawn:Pawn = world.pawns[0];
    for rn in world.nodes.duplicate():
        if _site.rect().has_point(rn.cell):
            world.remove_node(rn);
    _expect("paused sites are not built", world.jobs._build_task(pawn) == null);
    var far:Building = world.place_building(&"house", _free(&"house", Vector2i(3, 3), o + Vector2i(18, 18)), Vector2i(3, 3));
    for item in far.cost():
        far.delivered[item] = far.cost()[item];
    for rn in world.nodes.duplicate():
        if far.rect().has_point(rn.cell):
            world.remove_node(rn);
    _site.set_priority(Building.PRIORITY_MEDIUM);
    _site.position = pawn.position;       # the nearest, by far
    var t:Task = world.jobs._build_task(pawn);
    _expect("equal priority: the nearest site", t != null and is_same(t.target, _site));
    pawn.end_task(false);
    far.set_priority(4);
    t = world.jobs._build_task(pawn);
    _expect("critical beats near", t != null and is_same(t.target, far));
    pawn.end_task(false);
    far.set_priority(Building.PRIORITY_PAUSED);

    # --- cancel
    th.store(&"wood", 0);
    var wood_before:int = Stock.amount(&"wood");
    _site.delivered[&"wood"] = 5;
    world.tools.select(_site);
    world.hud._on_cancel_build();
    _expect("cancelling removes the site", _site.removed);
    _expect("and refunds what was delivered", Stock.amount(&"wood") >= wood_before + 5);
    _expect("and clears the selection", typeof(world.tools.selected) != TYPE_OBJECT or world.tools.selected == null);

    # --- clearing is not instant
    var cs:Vector2i = _free(&"house", Vector2i(3, 3), o + Vector2i(-6, -22));
    for rn in world.nodes.duplicate():
        if Rect2i(cs, Vector2i(3, 3)).has_point(rn.cell):
            world.remove_node(rn);
    _bush = world.add_node(&"bush", cs + Vector2i(1, 1));
    _tree = world.add_node(&"tree", cs + Vector2i(2, 0));
    _tree.set_growth(0.3);
    var cl:Building = world.place_building(&"house", cs, Vector2i(3, 3));
    _expect("a bush under a new site is still there", not _bush.removed and _bush.designated and _bush.clearing);
    _expect("so is a young tree", not _tree.removed and _tree.designated);
    _expect("the site waits for clearing", not cl.ready_for_work());
    var c2:Dictionary = world.serialize();
    _expect("clearing is saved", (c2["nodes"] as Array).any(func(a:Array) -> bool: return a.size() > 8 and a[8] == true));
    _start = GameClock.total_hours;
    GameClock.set_speed(3);
    Engine.time_scale = 4.0;

    # --- size text
    world.tools.set_mode(PlayerTools.Mode.BUILD, &"field");
    world.tools._hover_ok = true;
    world.tools._hover_cell = Vector2i(20, 20);
    _expect("the cursor is one tile: '%s'" % world.tools.size_text(), world.tools.size_text() == "1x1 tile");
    world.tools._dragging = true;
    world.tools._drag_start = Vector2i(20, 20);
    world.tools._hover_cell = Vector2i(25, 27);
    _expect("a drag: '%s'" % world.tools.size_text(), world.tools.size_text() == "6x8 tiles, 48 total");
    world.tools._dragging = false;
    world.tools._drag_start = Vector2i(20, 20);
    world.tools._hover_cell = Vector2i(20, 24);
    world.tools._dragging = true;
    _expect("a thin drag stays thin and is below the minimum: '%s'" % world.tools.size_text(), world.tools.size_text() == "1x5 tiles, 5 total" and not world.tools._field_rect_valid(world.tools._field_rect()));
    world.tools._dragging = false;
    world.tools.set_mode(PlayerTools.Mode.BUILD, &"stockpile");
    _expect("a stockpile can still be 1x1", world.tools.build_size == Vector2i.ONE);
    world.tools.set_mode(PlayerTools.Mode.SELECT);
    _expect("no text for other tools", world.tools.size_text() == "");

func _free(id:StringName, size:Vector2i, near:Vector2i) -> Vector2i:
    for r in range(0, 30):
        for dz in range(-r, r + 1, 2):
            for dx in range(-r, r + 1, 2):
                var o:Vector2i = near + Vector2i(dx, dz);
                if world.can_place(id, o, size) == "" and world.terrain.cell_slope(o) < 0.6:
                    return o;
    return near;

func _process(_delta:float) -> void:
    _frame += 1;
    if GameClock.speed() == 0.0:
        return;
    if _bush.removed and _tree.removed:
        _expect("laborers cleared both (%.1f h)" % (GameClock.total_hours - _start), true);
        get_tree().quit();
    elif GameClock.total_hours - _start > 60.0:
        _expect("laborers cleared both: bush %s (amount %d, room %s, designated %s, failed?), tree %s" % [_bush.removed, _bush.amount, Stock.has_room_for(&"berries"), _bush.designated, _tree.removed], false);
        get_tree().quit();

func _expect(what:String, ok:bool) -> void:
    print(("PASS " if ok else "FAIL ") + what);
