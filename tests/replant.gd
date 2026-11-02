# ----------------------------------------------------------------
# Woodcutter replanting
#     A woodcutter used to plant only when no tree was left to fell, so
#     a forest was cut bare before a sapling went in (found in a playtest
#     save: 104 trees in the circle, a year later 2, nothing planted
#     meanwhile). Now every tree felled adds a sapling to the hut's debt
#     that is paid before the next tree is felled: felling a tree makes
#     the next task a planting, a finished planting pays one off, a cut
#     short felling or planting changes nothing, and with Plant trees off
#     no debt builds.
#     godot --headless --path . --fixed-fps 60 res://tests/replant.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    var site:Vector2i = TestSite.near(world, Vector2i(-14, 8), Vector2i(8, 8));
    var hut:Building = world.place_building(&"woodcutter", site, Vector2i(3, 3), true);
    world.place_building(&"stockpile", TestSite.near(world, Vector2i(14, 8), Vector2i(6, 6)), Vector2i(4, 4), true);          # (the Town Hall starts full: felling needs room for the logs)
    hut.settings["priority"] = 1;          # felling first, so the firewood jobs do not come between
    hut.settings["chop"] = 1;
    hut.settings["plant"] = true;
    var cells:Array[Vector2i] = [];
    for dz in range(-6, 7):
        for dx in range(-6, 7):
            var c:Vector2i = Vector2i(hut.center_cell()) + Vector2i(dx, dz);
            if absi(dx) > 2 and world.can_plant_tree(c, 0) and cells.size() < 12:
                cells.append(c);
    for c in cells:
        world.add_node(&"tree", c);          # (full grown: growth starts at 1)
    _expect("there are trees to fell (%d)" % cells.size(), cells.size() >= 8);
    var p:Pawn = world.pawns[0];
    p.profession = JobManager.Profession.WOODCUTTER;
    var prod:ProductionTasks = world.jobs.production;
    var first:Task = prod.woodcutter_task(p);
    _expect("with no debt the woodcutter fells (%s)" % [first.kind if first else "none"], first != null and first.kind == &"harvest");
    _expect("no debt yet", hut.dig_progress.get(&"replant", 0.0) == 0.0);
    first.finish(p, false);
    _expect("a felling cut short adds no debt", hut.dig_progress.get(&"replant", 0.0) == 0.0);
    var chop:Task = prod.woodcutter_task(p);
    chop.finish(p, true);
    _expect("a finished felling adds a sapling to the debt (%s)" % hut.dig_progress.get(&"replant", 0.0), hut.dig_progress.get(&"replant", 0.0) == 1.0);
    var plant:Task = prod.woodcutter_task(p);
    _expect("so the next task is a planting (%s)" % [plant.kind if plant else "none"], plant != null and plant.kind == &"plant");
    plant.finish(p, false);
    _expect("a planting cut short pays nothing off", hut.dig_progress.get(&"replant", 0.0) == 1.0 and world.planting.is_empty());
    var again:Task = prod.woodcutter_task(p);
    _expect("and it is tried again", again != null and again.kind == &"plant");
    again.finish(p, true);
    _expect("a finished planting pays it off", hut.dig_progress.get(&"replant", 0.0) == 0.0);
    var next:Task = prod.woodcutter_task(p);
    _expect("then it fells again (%s)" % [next.kind if next else "none"], next != null and next.kind == &"harvest");
    next.finish(p, false);
    hut.settings["plant"] = false;
    var quiet:Task = prod.woodcutter_task(p);
    quiet.finish(p, true);
    _expect("with Plant trees off no debt builds", hut.dig_progress.get(&"replant", 0.0) == 0.0);
    print("REPLANT %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
