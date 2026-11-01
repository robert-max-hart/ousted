# ----------------------------------------------------------------
# Load probe
#     Times building a world and the frames after it (the grass and ground plants that fill in over the next frames),
#     to see where loading time goes. A probe, not in the suite.
#     godot --headless --path . --fixed-fps 60 res://tests/load_probe.tscn
# ----------------------------------------------------------------
extends Node;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    var t0:int = Time.get_ticks_msec();
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    var t1:int = Time.get_ticks_msec();
    print("world built in %d ms (the add_child frame)" % (t1 - t0));
    var grass:GrassDetail = null;
    var plants:GroundPlants = null;
    for c in world.get_children():
        if c is GrassDetail:
            grass = c;
        if c is GroundPlants:
            plants = c;
    var frames:int = 0;
    var worst:int = 0;
    var total:int = 0;
    while frames < 600:
        var f0:int = Time.get_ticks_msec();
        await get_tree().process_frame;
        var dt:int = Time.get_ticks_msec() - f0;
        total += dt;
        worst = maxi(worst, dt);
        frames += 1;
        if frames % 20 == 0:
            print("frame %d: grass queue %d, plants queue %d, terrain dirty %d, last frame %d ms" % [frames, grass._dirty.size(), plants._dirty.size(), world.terrain._dirty.size(), dt]);
        if grass._dirty.is_empty() and plants._dirty.is_empty() and world.terrain._dirty.is_empty():
            break;
    print("settled after %d frames, %d ms, worst frame %d ms" % [frames, total, worst]);
    get_tree().quit();
