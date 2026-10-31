# ----------------------------------------------------------------
# Tutorial test
#     The guide is only attached when asked for, starts on its welcome step,
#     and moves on by itself as the game shows each thing done: camera
#     moved, colony founded, Town Hall selected, speed changed, trees
#     marked, a house placed and finished, a road staked, a field, an
#     overlay, a second farmer, a woodcutter, a save. Next, Skip and End
#     work.
#     godot --headless --path . --fixed-fps 60 res://tests/tutorial.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;
var _world:World;
var _t:Tutorial;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    GameRules.reset();
    # no tutorial unless asked for
    _world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(_world);
    await get_tree().process_frame;
    _expect("no tutorial in an ordinary game", _world.hud.get_node_or_null("Tutorial") == null);
    _world.queue_free();
    await get_tree().process_frame;

    Tutorial.active = true;
    _world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(_world);
    await get_tree().process_frame;
    _t = _world.hud.get_node_or_null("Tutorial") as Tutorial;
    _expect("a tutorial game gets the guide, once", _t != null and not Tutorial.active);
    if _t == null:
        _finish();
        return;
    _expect("it starts on the welcome step, which has a Next button", _t.index == 0 and _t._next.visible and not _t._skip.visible);
    _t._next.pressed.emit();
    _expect_step(&"look", "Next moves on to looking around");
    _expect("looking around is not done at once", not _t.done(&"look"));
    _world.camera_rig.position += Vector3(20, 0, 0);
    _pump();
    _expect_step(&"settle", "moving the camera finishes it");
    _pump();       # the colony is founded already in this game (no choose-your-start)
    _expect_step(&"hall", "a founded colony finishes the settle step");
    _world.tools.select(_world.town_hall);
    _pump();
    _expect_step(&"time", "selecting the Town Hall finishes it");
    _expect("speed is not done before it changes", not _t.done(&"time"));
    GameClock.set_speed(2 if GameClock.speed_index != 2 else 3);
    _pump();
    _expect_step(&"wood", "changing the speed finishes it");
    var tree:ResourceNode = _world.nodes.filter(func(n:ResourceNode) -> bool: return n.is_tree())[0];
    _world.set_designated(tree, true);
    _pump();
    _expect_step(&"house", "marking a tree finishes the wood step");
    var hs:Vector2i = Defs.BUILDINGS[&"house"]["size"];
    _world.place_building(&"house", TestSite.spot(_world, hs, Vector2i(8, 8)), hs);
    _pump();
    _expect_step(&"built", "placing a house finishes the house step");
    _expect("an unfinished house does not finish 'watch it go up'", not _t.done(&"built"));
    _world.place_building(&"house", TestSite.spot(_world, hs, Vector2i(-8, 8)), hs, true);
    _pump();
    _expect_step(&"road", "a finished house finishes it");
    _t._skip.pressed.emit();
    _expect_step(&"field", "Skip step moves on without the road");
    var fs:Vector2i = Defs.BUILDINGS[&"field"]["size"];
    _world.place_building(&"field", TestSite.spot(_world, fs, Vector2i(10, -10)), fs);
    _pump();
    _expect_step(&"overlay", "a field finishes the field step");
    _world.terrain.set_slope_view(true);
    _pump();
    _expect_step(&"jobs", "an overlay finishes that step");
    _world.jobs.targets[JobManager.Profession.FARMER] = 2;
    _pump();
    _expect_step(&"woodcutter", "a second farmer finishes the jobs step");
    var ws:Vector2i = Defs.BUILDINGS[&"woodcutter"]["size"];
    _world.place_building(&"woodcutter", TestSite.spot(_world, ws, Vector2i(-10, -8)), ws);
    _pump();
    _expect_step(&"save", "a woodcutter finishes its step");
    _expect("saving is not done before it happens", not _t.done(&"save"));
    SaveGame.write(_world, "tutorial test");
    SaveGame.delete("tutorial test");
    _pump();
    _expect_step(&"finish", "saving finishes the save step");
    _expect("the last step has a Finish button", _t._next.visible and _t._next.text == "Finish");
    _t._next.pressed.emit();
    _expect("Finish ends the tutorial", _t.finished and not is_instance_valid(_t._panel) or _t._panel.is_queued_for_deletion());
    _finish();

# One poll, then the pause after "Done!".
func _pump() -> void:
    _t._process(Tutorial.POLL + 0.01);
    _t._process(Tutorial.DONE_PAUSE + 0.01);

func _expect_step(id:StringName, what:String) -> void:
    _expect("%s (on %s)" % [what, Tutorial.STEPS[_t.index]["id"]], Tutorial.STEPS[_t.index]["id"] == id);

func _finish() -> void:
    print("TUTORIAL %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    print("%s: %s" % ["PASS" if ok else "FAIL", what]);
    if not ok:
        _fails += 1;
