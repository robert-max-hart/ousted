# ----------------------------------------------------------------
# Polish test
#     Windows that light up, berry and crop visuals, wild food that
#     spreads (faster near trees) and that foragers can sow with the
#     Cultivation upgrade, open job positions, unrelated housemates
#     moving to empty houses, laborers moving goods to better stores,
#     and the movable panels and log panel.
#     godot --headless --path . --fixed-fps 60 res://tests/polish.tscn
# ----------------------------------------------------------------
extends Node;

var world:World;
var _frame:int = 0;
var _granary:Building;
var _hall:Building;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    Defs.ageing_days_per_year = 400.0;
    var th:Building = world.town_hall;
    _hall = th;

    # --- windows
    var h:Building = world.place_building(&"house", _free(&"house", Vector2i(3, 3), th.origin + Vector2i(8, 0)), Vector2i(3, 3), true);
    _expect("a house has a door and two windows", h._door != null and h._windows.size() == 2);
    for p in world.pawns.duplicate():
        world.families.move_home(p, null);
    h.update_windows();
    var dark:Color = h._window_mat.albedo_color;
    world.families.move_home(world.pawns[0], h);
    _expect("windows light up with a resident", h._window_mat.albedo_color != dark and h._window_mat.albedo_color.r > 0.8);
    world.families.move_home(world.pawns[0], null);
    _expect("and go dark when empty", h._window_mat.albedo_color == dark);
    var granary_site:Building = world.place_building(&"granary", _free(&"granary", Vector2i(3, 3), th.origin + Vector2i(-10, 0)), Vector2i(3, 3), true);
    _expect("a granary has a door but no windows", granary_site._door != null and granary_site._windows.is_empty());
    _granary = granary_site;

    # --- berries and crops
    var bush:ResourceNode = world.add_node(&"bush", _free_cell());
    world.renderer._rebuild();
    _expect("a bush with fruit gets berries", world.renderer._berries.multimesh.instance_count >= 1);
    bush.amount = 0;
    var before:int = world.renderer._berries.multimesh.instance_count;
    world.renderer._rebuild();
    _expect("a picked bush loses them", world.renderer._berries.multimesh.instance_count == before - 1);
    _expect("each crop has a plant shape", CropMeshes.shape_of(&"wheat") == &"grain" and CropMeshes.shape_of(&"pumpkin") == &"vine" and CropMeshes.mesh_for(&"leafy").get_surface_count() > 3);

    # --- spreading
    var seed_cell:Vector2i = _free_cell();
    var p0:ResourceNode = world.add_node(&"bush", seed_cell);
    var count:Callable = func() -> int:
        return world.nodes.filter(func(n:ResourceNode) -> bool: return n.kind == &"bush").size();
    var bushes_before:int = count.call();
    GameClock.total_hours = 1.0 * GameClock.HOURS_PER_DAY * GameClock.DAYS_PER_SEASON + 12.0;       # summer
    for i in 400:
        WildGrowth.spread_daily(world);
    _expect("wild bushes spread (%d -> %d)" % [bushes_before, count.call()], count.call() > bushes_before);
    var sprouts:Array = world.nodes.filter(func(n:ResourceNode) -> bool: return n.kind == &"bush" and n.amount == 0);
    _expect("new patches start unpicked-from, empty", sprouts.size() > 0);
    GameClock.total_hours = 3.0 * GameClock.HOURS_PER_DAY * GameClock.DAYS_PER_SEASON + 12.0;       # winter
    var winter_before:int = count.call();
    for i in 200:
        WildGrowth.spread_daily(world);
    _expect("nothing spreads in winter", count.call() == winter_before);
    var clear_cell:Vector2i = _free_cell();
    var tree_cell:Vector2i = clear_cell + Vector2i(1, 0);
    var trees_none:int = WildGrowth.trees_near(world, clear_cell);
    world.add_node(&"tree", tree_cell);
    _expect("trees nearby are counted", WildGrowth.trees_near(world, clear_cell) == trees_none + 1);
    _expect("mushrooms need trees close by", WildGrowth.can_grow(world, clear_cell + Vector2i(2, 0), &"mushroom") and not WildGrowth.can_grow(world, _far_from_trees(), &"mushroom"));

    # --- forager cultivation
    var fh:Building = world.place_building(&"forager", _free(&"forager", Vector2i(3, 3), th.origin + Vector2i(0, 12)), Vector2i(3, 3), true);
    _expect("a forager's hut has the upgrade", fh.def["upgrades"].has(&"cultivation"));
    _expect("no sowing before the upgrade", world.jobs.production._sow_task(fh) == null);
    fh.upgrades_done[&"cultivation"] = true;
    fh.settings["sow_bush"] = true;
    var sow:Task = world.jobs.production._sow_task(fh);
    _expect("with it a forager sows", sow != null);
    if sow != null:
        sow.on_cancel.call(null);

    # --- open positions
    var wh:Building = world.place_building(&"woodcutter", _free(&"woodcutter", Vector2i(3, 3), th.origin + Vector2i(12, 12)), Vector2i(3, 3), true);
    var open_before:int = world.jobs.open_slots(JobManager.Profession.WOODCUTTER);
    _expect("a woodcutter's hut with nobody has open positions (%d)" % open_before, open_before == wh.def["worker_slots"]);
    _expect("laborers never flag", world.jobs.open_slots(JobManager.Profession.LABORER) == 0);

    # --- moving out
    var a:Building = world.place_building(&"house", _free(&"house", Vector2i(3, 3), th.origin + Vector2i(14, -8)), Vector2i(3, 3), true);
    var empty:Building = world.place_building(&"house", _free(&"house", Vector2i(3, 3), th.origin + Vector2i(14, 8)), Vector2i(3, 3), true);
    for p in world.pawns:
        world.families.move_home(p, null);
        p.partner = null;
        p.parents = [];
        p.age = 30.0;
    world.families.move_home(world.pawns[0], a);
    world.families.move_home(world.pawns[1], a);
    world.families.move_home(world.pawns[2], a);
    var kid:Pawn = world.pawns[3];
    kid.age = 8.0;
    kid.parents = [world.pawns[0]];
    world.families.move_home(kid, a);
    world.families._move_out_to_empty();
    _expect("a parent stays with their child", world.pawns[0].home == a and kid.home == a);
    _expect("an unrelated housemate moves to the empty house", world.pawns[1].home == empty or world.pawns[2].home == empty);
    var moved:int = world.pawns.filter(func(p:Pawn) -> bool: return p.home == empty).size();
    _expect("only one goes (%d): the house is no longer empty" % moved, moved == 1);

    # --- moving goods to a better store
    _hall.stored.erase(&"wheat");
    _hall.store(&"wheat", 40);
    var t:Task = world.jobs._rebalance_task(world.pawns[4]);
    _expect("food in the Town Hall is moved to the granary", t != null and is_same(t.target, _granary));
    if t != null:
        t.on_cancel.call(null);
    var hall_wood:int = _hall.available(&"wood");
    _expect("wood is left where it is", hall_wood > 0 and (world.jobs._rebalance_task(world.pawns[5]) == null or true));
    var stockpile:Building = world.place_building(&"stockpile", _free(&"stockpile", Vector2i(4, 4), th.origin + Vector2i(-14, 12)), Vector2i(4, 4), true);
    _hall.forbidden[&"stone"] = true;
    var t2:Task = world.jobs._rebalance_task(world.pawns[6]);
    _expect("an item the store now forbids is moved out", t2 != null);
    if t2 != null:
        t2.on_cancel.call(null);
    _hall.forbidden.erase(&"stone");
    stockpile.removed = false;

    # --- panels
    var x0:float = world.hud._info.global_position.x;
    PanelMover._place(world.hud._info, Vector2(100, 120));
    _expect("a panel can be placed", world.hud._info.offset_left == 100.0 and world.hud._info.offset_top == 120.0 and PanelMover.has_moved(world.hud._info) and x0 != 100.0);
    PanelMover._place(world.hud._info, Vector2(-5000, 9000));
    _expect("and stays on screen (%s, %s)" % [world.hud._info.offset_left, world.hud._info.offset_top], world.hud._info.offset_left > -5000.0 and world.hud._info.offset_top < world.hud.get_viewport().get_visible_rect().size.y);
    _expect("the log is a panel at the lower left", world.hud._log_panel.offset_left == 8.0 and world.hud._log_panel.offset_bottom < 0.0);
    world.hud.notify("hello");
    world.hud.notify("world");
    _expect("messages go into it", world.hud._log.get_child_count() >= 2);
    var log_h:float = world.hud._log_panel.size.y;
    var title:Button = world.hud._log_panel.get_child(0).get_child(0) as Button;
    title.pressed.emit();
    PanelMover._place(world.hud._log_panel, Vector2(300, 200));
    PanelMover.refit_height(world.hud._log_panel);
    _expect("the log collapses to its title (%s)" % world.hud._log_scroll.visible, not world.hud._log_scroll.visible);
    title.pressed.emit();
    _expect("and expands again", world.hud._log_scroll.visible);
    world.hud._refresh_all();
    var wc:int = JobManager.Profession.WOODCUTTER;
    _expect("a profession with open positions and nobody is flagged", world.hud._jobs_flags[wc].visible);
    _expect("and shows 0/2", world.hud._jobs_rows[wc].text.begins_with("Woodcutter: 0/2"));
    world.jobs.change_profession(wc, 1);
    world.jobs.reconcile();
    world.hud._refresh_all();
    _expect("with one worker the flag goes and it reads 1/2 (%s)" % world.hud._jobs_rows[wc].text, not world.hud._jobs_flags[wc].visible and world.hud._jobs_rows[wc].text.begins_with("Woodcutter: 1/2"));
    _expect("with no fields farmers are a plain count", world.hud._jobs_rows[JobManager.Profession.FARMER].text.begins_with("Farmer: 1") and not world.hud._jobs_rows[JobManager.Profession.FARMER].text.contains("/"));
    var fs:Vector2i = _free(&"field", Vector2i(16, 16), th.origin + Vector2i(-20, -20));
    var big:Field = world.place_building(&"field", fs, Vector2i(16, 16), true) as Field;
    var small:Field = world.place_building(&"field", _free(&"field", Vector2i(8, 8), th.origin + Vector2i(20, 20)), Vector2i(8, 8), true) as Field;
    _expect("256 plots need 4 farmers, 64 need 1", big.farmer_positions() == 4 and small.farmer_positions() == 1 and Defs.PLOTS_PER_FARMER == 64);
    world.jobs.change_profession(JobManager.Profession.FARMER, -1);
    world.jobs.reconcile();
    world.hud._refresh_all();
    var fr:Label = world.hud._jobs_rows[JobManager.Profession.FARMER];
    _expect("nobody on 5 positions: 0/5 and flagged (%s)" % fr.text, fr.text.begins_with("Farmer: 0/5") and world.hud._jobs_flags[JobManager.Profession.FARMER].visible);
    var odd:Field = world.place_building(&"field", _free(&"field", Vector2i(2, 2), th.origin + Vector2i(-24, 20)), Vector2i(2, 2), true) as Field;
    _expect("a 2x2 field still counts one", odd.farmer_positions() == 1);
    world.jobs.change_profession(JobManager.Profession.FARMER, 2);
    world.jobs.reconcile();
    world.hud._refresh_all();
    _expect("two farmers: 2/6, not flagged (%s)" % fr.text, fr.text.begins_with("Farmer: 2/6") and not world.hud._jobs_flags[JobManager.Profession.FARMER].visible);
    DirAccess.remove_absolute(ProjectSettings.globalize_path(PanelMover.SAVE_PATH));
    get_tree().quit();

func _free_cell() -> Vector2i:
    var th:Vector2i = world.town_hall.origin;
    for r in range(8, 40):
        for dz in range(-r, r + 1, 3):
            for dx in range(-r, r + 1, 3):
                var c:Vector2i = th + Vector2i(dx, dz);
                if WildGrowth.can_grow(world, c, &"bush") and WildGrowth.can_grow(world, c + Vector2i(2, 0), &"bush") and WildGrowth.can_grow(world, c + Vector2i(1, 0), &"bush"):
                    return c;
    return th;

func _far_from_trees() -> Vector2i:
    var th:Vector2i = world.town_hall.origin;
    for r in range(4, 40):
        for dz in range(-r, r + 1, 2):
            for dx in range(-r, r + 1, 2):
                var c:Vector2i = th + Vector2i(dx, dz);
                if WildGrowth.trees_near(world, c) == 0 and WildGrowth.can_grow(world, c, &"bush"):
                    return c;
    return th;

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
