# ----------------------------------------------------------------
# LoadingScreen test
#     A world made with no loading screen is complete as soon as it is added (the tests rely on it). With the loading
#     screen up it is built over several frames, the game clock is held meanwhile, nothing is left to fill in when the
#     screen goes, and the clock runs again afterwards. A loaded game goes the same way.
#     godot --headless --path . --fixed-fps 60 res://tests/loading_screen.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    # no screen: built at once
    var plain:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(plain);
    _expect("with no loading screen the world is whole at once", plain.camera_rig != null and plain.hud != null and not LoadingScreen.active);
    plain.queue_free();
    await get_tree().process_frame;
    # with the screen up
    GameClock.reset();
    LoadingScreen.begin(get_tree());
    _expect("begin puts the screen up and holds the clock", LoadingScreen.active and GameClock.held);
    var hours:float = GameClock.total_hours;
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    _expect("the world is not finished when it is added", world.camera_rig == null);
    var frames:int = 0;
    while LoadingScreen.active and frames < 1500:
        await get_tree().process_frame;
        frames += 1;
    print("built in %d frames" % frames);
    _expect("it finished (%d frames)" % frames, not LoadingScreen.active and frames > 6);
    _expect("the build took several frames, not one", frames > 10);
    _expect("the clock is let go and no time passed while loading", not GameClock.held and is_equal_approx(GameClock.total_hours, hours));
    _expect("the world has everything", world.camera_rig != null and world.hud != null and world.town_hall != null and world.pawns.size() > 0);
    var grass:GrassDetail = null;
    var plants:GroundPlants = null;
    for c in world.get_children():
        if c is GrassDetail:
            grass = c;
        if c is GroundPlants:
            plants = c;
    _expect("nothing is left to fill in", grass._dirty.is_empty() and plants._dirty.is_empty() and world.terrain._dirty.is_empty());
    _expect("the quick pace was put back", grass.rebuilds_per_frame == GrassDetail.REBUILDS_PER_FRAME and world.terrain.chunks_per_frame == 0);
    await get_tree().create_timer(0.8).timeout;
    _expect("the screen is gone (freed after its fade)", not is_instance_valid(get_tree().root.get_node_or_null("LoadingScreen")));
    # a saved game
    var err:String = SaveGame.write(world, "loading_test");
    _expect("saved", err == "");
    var slot_err:String = "";
    var data:Dictionary = SaveGame.read("loading_test", []);
    _expect("and read back", not data.is_empty());
    world.queue_free();
    await get_tree().process_frame;
    GameClock.restore_state(data["clock"]);
    Weather.restore_state(data["weather"]);
    World.pending_load = data;
    LoadingScreen.begin(get_tree());
    var loaded:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(loaded);
    frames = 0;
    while LoadingScreen.active and frames < 1500:
        await get_tree().process_frame;
        frames += 1;
    _expect("a loaded game finishes and has its citizens (%d frames)" % frames, not LoadingScreen.active and loaded.pawns.size() > 0 and loaded.hud != null);
    SaveGame.delete("loading_test");
    print("LOADING SCREEN %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    if ok:
        print("PASS: ", what);
    else:
        print("FAIL: ", what);
        _fails += 1;
