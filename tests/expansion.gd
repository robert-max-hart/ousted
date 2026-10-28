# ----------------------------------------------------------------
# Expansion test
#     Stockpiles, fields and graveyards grow into free ground: the
#     extra cells are held at once, the difference in cost and work
#     is paid, and when it is done the size, capacity and per-plot
#     data are right. Blocked, cancelled and saved cases too.
#     godot --headless --path . --fixed-fps 60 res://tests/expansion.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;
var world:World;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    world.seeds.unlock_all();
    var o:Vector2i = world.town_hall.origin + Vector2i(10, -14);
    for rn in world.nodes.duplicate():
        if Rect2i(o - Vector2i(4, 4), Vector2i(34, 34)).has_point(rn.cell):
            world.remove_node(rn);
    world.terrain.flatten_rect(Rect2i(o - Vector2i(2, 2), Vector2i(34, 34)));       # the map is random: make the ground level and dry
    _stockpile(o);
    _field(o + Vector2i(0, 12));
    _graveyard(o + Vector2i(14, 12));
    print("EXPANSION %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _finish(b:Building) -> void:
    for item in b.cost():
        b.delivered[item] = b.cost()[item];
    var guard:int = 0;
    while b.upgrading == Expansion.ID and guard < 1000:
        b.add_work(1.0);
        guard += 1;

func _stockpile(o:Vector2i) -> void:
    var s:Building = world.place_building(&"stockpile", o, Vector2i(4, 4), true);
    s.store(&"wood", 30);
    var cap:int = s.capacity();
    var r:Rect2i = Expansion.target_rect(s, o + Vector2i(5, 1));
    _expect("a click beside it grows it to take in the cell (%s)" % r, r == Rect2i(o, Vector2i(6, 4)));
    _expect("inside it is no expansion", Expansion.block_reason(world, s, Expansion.target_rect(s, o + Vector2i(1, 1))) != "");
    var plan:Dictionary = Expansion.plan(s, r);
    _expect("the extra area costs wood", plan["cost"].get(&"wood", 0) > 0 and plan["work"] > 0.0);
    _expect("it can start", Expansion.start(world, s, r));
    _expect("the new cells are held at once", world.occupant[world.idx(o + Vector2i(5, 1))] == s and s.is_site());
    _expect("it still holds its goods and size meanwhile", s.amount(&"wood") == 30 and s.size == Vector2i(4, 4));
    _expect("a second expansion is refused meanwhile", Expansion.block_reason(world, s, Rect2i(o, Vector2i(7, 4))) != "");
    _finish(s);
    _expect("done: it is 6x4 with more capacity (%d to %d)" % [cap, s.capacity()], s.size == Vector2i(6, 4) and s.capacity() > cap);
    _expect("goods kept, no longer a site", s.amount(&"wood") == 30 and not s.is_site() and s.is_complete());
    _expect("the pad was resized", ((s._body.mesh as BoxMesh).size.x - 5.7) < 0.01);
    # blocked by a neighbour
    var other:Building = world.place_building(&"house", o + Vector2i(8, 0), Vector2i(3, 3), true);
    _expect("a building in the way blocks it", Expansion.block_reason(world, s, Expansion.target_rect(s, o + Vector2i(9, 1))) == "Something is already built here");
    world.remove_building(other, true);
    _expect("too big is refused", Expansion.block_reason(world, s, Rect2i(o, Vector2i(PlayerTools.FIELD_MAX_SIDE + 1, 4))) != "");
    # cancel
    var wood_before:int = Stock.amount(&"wood");
    var r2:Rect2i = Expansion.target_rect(s, o + Vector2i(1, 4));
    Expansion.start(world, s, r2);
    s.delivered[&"wood"] = 2;
    s.cancel_upgrade();
    _expect("cancelled: not a site, cells free again", not s.is_site() and world.occupant[world.idx(o + Vector2i(1, 4))] == null and s.size == Vector2i(6, 4));
    _expect("the delivered wood came back", Stock.amount(&"wood") >= wood_before);
    # save while expanding
    Expansion.start(world, s, r2);
    var saved:Dictionary = world.serialize();
    var found:bool = false;
    for bd in saved["buildings"]:
        if bd["id"] == &"stockpile" and not (bd["expansion"] as Dictionary).is_empty():
            found = true;
    _expect("an expansion in progress is saved", found);
    s.cancel_upgrade();

func _field(o:Vector2i) -> void:
    var f:Field = world.place_building(&"field", o + Vector2i(2, 2), Vector2i(4, 4), true) as Field;
    f.plot_state[5] = Field.Plot.PLANTED;       # the cell at (1, 1) in the field
    f.plot_crop[5] = &"barley";
    f.growth[5] = 0.5;
    f.cuts[5] = 1;
    var cell:Vector2i = f.plot_cell(5);
    var r:Rect2i = Expansion.target_rect(f, o + Vector2i(0, 0));       # grow up and left
    _expect("a field grows up and left (%s)" % r, r == Rect2i(o, Vector2i(6, 6)));
    _expect("it can start, new ground is bare staked soil", Expansion.start(world, f, r) and world.terrain.get_overlay(o) == Terrain.Overlay.SITE);
    _expect("a field costs nothing but labor to grow", f.cost().is_empty() and f.work_required() > 0.0);
    _finish(f);
    _expect("the field is 6x6 at the new origin", f.size == Vector2i(6, 6) and f.origin == o and f.plot_count() == 36);
    var idx:int = (cell.x - f.origin.x) + (cell.y - f.origin.y) * f.size.x;
    _expect("the old plots kept their crop and growth", f.plot_state[idx] == Field.Plot.PLANTED and f.plot_crop[idx] == &"barley" and is_equal_approx(f.growth[idx], 0.5) and f.cuts[idx] == 1);
    _expect("new plots are fallow", f.plot_state[0] == Field.Plot.FALLOW and f.plot_state[35] == Field.Plot.FALLOW);
    _expect("new ground is tilled", world.terrain.get_overlay(o) == Terrain.Overlay.TILLED);
    _expect("every per-plot array has the new length", f.growth.size() == 36 and f.moisture.size() == 36 and f.reserved.size() == 36 and f.plot_crop.size() == 36);
    f.on_hour();
    f.find_work(Vector2i.ZERO);

func _graveyard(o:Vector2i) -> void:
    var g:Graveyard = world.place_building(&"graveyard", o + Vector2i(1, 1), Vector2i(3, 3), true) as Graveyard;
    g.graves[4] = {"name": "Ann", "age": 50, "cause": "age", "buried_hour": 0.0};
    var at:Vector2i = g.plot_cell(4);
    var r:Rect2i = Expansion.target_rect(g, o);
    Expansion.start(world, g, r);
    _finish(g);
    var idx:int = (at.x - g.origin.x) + (at.y - g.origin.y) * g.size.x;
    _expect("the grave stayed where it was after the graveyard grew", g.graves[idx] != null and g.graves[idx]["name"] == "Ann" and g.used_slots() == 1);
    _expect("and there are more free squares", g.free_slots() == g.plot_count() - 1);

func _expect(what:String, ok:bool) -> void:
    print(("PASS " if ok else "FAIL ") + what);
    if not ok:
        _fails += 1;
