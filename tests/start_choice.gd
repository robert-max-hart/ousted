# ----------------------------------------------------------------
# Choosing the start
#     With World.choose_start set, a new game has no colony until the
#     player places the Town Hall: the clock is held, nothing can be
#     saved, a bad spot is refused and leaves the choice open, and a good
#     spot founds the colony there (Town Hall, goods, settlers).
#     godot --headless --path . --fixed-fps 60 res://tests/start_choice.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"normal";
    World.choose_start = true;
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    _expect("the game waits for the player", world.awaiting_start and world.town_hall == null and world.pawns.is_empty());
    _expect("the flag is used up (the next game starts as usual)", not World.choose_start);
    _expect("time is held (paused, and a speed key does nothing)", GameClock.is_paused());
    GameClock.set_speed(3);
    _expect("... even when asked", GameClock.is_paused());
    _expect("the Town Hall ghost is the tool", world.tools.mode == PlayerTools.Mode.BUILD and world.tools.build_id == &"town_hall");
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0:          # windowed: the screen the player sees before choosing (the cursor on the suggested spot)
        var screen:Vector2 = world.camera_rig.get_viewport().get_camera_3d().unproject_position(Vector3(world.suggested_start.x, 0.0, world.suggested_start.y));
        get_viewport().warp_mouse(screen);
        for i in 20:
            await get_tree().process_frame;
        get_viewport().get_texture().get_image().save_png(args[0].path_join("start_choice.png"));
    var lines:Array = SiteRating.rate(world, world.suggested_start);
    _expect("the rating has a line each for ground, water, soil, trees, food, stone, iron and an overall one (%d)" % lines.size(), lines.size() == 8 and lines[7][0] == "Overall");
    var text:String = SiteRating.bbcode(lines);
    _expect("it reads as text (%s)" % text.replace("\n", " | "), text.contains("Water:") and text.contains("Overall"));
    var wet_site:Vector2i = Vector2i(-1, -1);
    for z in range(5, Terrain.SIZE - 5):
        for x in range(5, Terrain.SIZE - 5):
            if wet_site.x < 0 and world.terrain.is_water(Vector2i(x, z)) and world.terrain.is_water(Vector2i(x + 3, z + 3)):
                wet_site = Vector2i(x, z);
    _expect("the suggested spot rates at least as well as the middle of a lake", lines[7][2] >= SiteRating.rate(world, wet_site)[7][2]);
    var wet:Vector2i = Vector2i(-1, -1);
    for z in range(5, Terrain.SIZE - 5):
        for x in range(5, Terrain.SIZE - 5):
            if wet.x < 0 and world.terrain.is_water(Vector2i(x, z)) and world.terrain.is_water(Vector2i(x + 3, z + 3)):
                wet = Vector2i(x, z);
    var err:String = world.begin_colony(wet);
    _expect("water is refused (%s) and the choice stays open" % err, err != "" and world.awaiting_start and world.pawns.is_empty());
    var origin:Vector2i = world.suggested_start - Vector2i(2, 2);
    err = world.begin_colony(origin);
    _expect("the suggested spot works (%s)" % err, err == "" and not world.awaiting_start);
    _expect("the Town Hall is there, finished", world.town_hall != null and world.town_hall.origin == origin and world.town_hall.is_complete());
    _expect("the settlers arrived and have goods", world.pawns.size() >= 6 and Stock.amount(&"wheat") > 0);
    _expect("the clock runs", not GameClock.is_paused() and not GameClock.locked);
    # a second new game without the flag founds the colony at once
    world.queue_free();
    await get_tree().process_frame;
    var again:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(again);
    _expect("without the flag the colony exists at once", not again.awaiting_start and again.town_hall != null and not again.pawns.is_empty());
    print("START CHOICE %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
