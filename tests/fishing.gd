# ----------------------------------------------------------------
# Fishing huts
#     A hut goes partly over water (and only there), its catch grows with
#     the water share of its circle and shrinks when another hut's circle
#     overlaps, and a fisherman brings fish to storage.
#     godot --headless --path . --fixed-fps 60 res://tests/fishing.tscn
# ----------------------------------------------------------------
extends Node;

var world:World;
var _fails:int = 0;
var _hut:FishingHut;
var _start:float = 0.0;
var _phase:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    var spot:Array = _shore();
    _expect("found a shore (%s)" % [spot], not spot.is_empty());
    if spot.is_empty():
        _finish();
        return;
    var o:Vector2i = spot[0];
    var size:Vector2i = spot[2];
    var facing:int = spot[3];
    _expect("a fishing hut is allowed with its pier over the water", world.can_place(&"fishing_hut", o, size, false, facing) == "");
    var dry_spot:Vector2i = TestSite.near(world, Vector2i(0, 8));
    _expect("but not on dry land (%s)" % world.can_place(&"fishing_hut", dry_spot, size, false, facing), world.terrain.is_water(dry_spot) or world.can_place(&"fishing_hut", dry_spot, size, false, facing) != "");
    _expect("and a house is still refused over water", world.can_place(&"house", o, Vector2i(3, 3)) == "Can't build on water");
    _hut = world.place_building(&"fishing_hut", o, size, true, false, facing) as FishingHut;
    var spot_cell:Vector2i = _hut.work_spot();
    _expect("fishermen work at the end of the pier (%s)" % spot_cell, _hut.pier_rect().has_point(spot_cell) and world.nav.is_walkable(spot_cell) and world.terrain.is_water(spot_cell));
    var door_side:Vector2i = _hut.origin + Vector2i(size.x / 2, size.y / 2);
    _expect("the way from the hut's door to the end of the pier is walkable", world.nav.find_path(_hut.pier_rect().position, spot_cell).size() > 0 and _hut.deck_has(door_side));
    _expect("a pier cell is a deck citizens stand above the water on", world.is_bridge(spot_cell) and world.stand_y(spot_cell.x + 0.5, spot_cell.y + 0.5) > Terrain.WATER_LEVEL);
    var share:float = _hut.water_share();
    var rate:float = _hut.catch_rate();
    _expect("the circle has water (%.0f%%) and a catch (%.2f an hour)" % [share * 100.0, rate], share > 0.05 and rate > 0.0 and _hut.overlap() == 0.0);
    # a second hut next to it shares the water: both catch less
    var o2:Vector2i = spot[1];
    var second:FishingHut = world.place_building(&"fishing_hut", o2, size, true, false, facing) as FishingHut;
    _expect("a second hut with its circle over the first shares the water (%.0f%%)" % [_hut.overlap() * 100.0], _hut.overlap() > 0.2 and second.overlap() > 0.2);
    _expect("so the first hut catches less (%.2f now, %.2f before)" % [_hut.catch_rate(), rate], _hut.catch_rate() < rate);
    world.remove_building(second, false);
    _expect("and takes it back when the other is gone", absf(_hut.catch_rate() - rate) < 0.0001);
    # a fisherman fishes
    var p:Pawn = world.pawns[0];
    p.profession = JobManager.Profession.FISHERMAN;
    world.jobs.sync_targets();
    world.town_hall.take(&"wheat", world.town_hall.stored.get(&"wheat", 0));
    GameClock.set_speed(3);
    Engine.time_scale = 4.0;
    _start = GameClock.total_hours;
    _phase = 1;

func _process(_delta:float) -> void:
    if _phase != 1:
        return;
    for p in world.pawns:
        p.hunger = 1.0; p.thirst = 1.0; p.energy = 1.0; p.warmth = 1.0;
    var hours:float = GameClock.total_hours - _start;
    if Stock.amount(&"fish") >= 3:
        _expect("a fisherman brought fish to storage (%d in %.0f hours)" % [Stock.amount(&"fish"), hours], true);
        _finish();
    elif hours > 40.0:
        _expect("a fisherman brought fish within 40 hours (%d)" % Stock.amount(&"fish"), false);
        _finish();

# A spot for a fishing hut (a facing, so its pier is over the water) with a second one 5 cells along: [origin, origin2, size, facing].
func _shore() -> Array:
    for facing in 4:
        var size:Vector2i = Vector2i(3, 4) if facing % 2 == 0 else Vector2i(4, 3);
        for z in range(10, Terrain.SIZE - 14):
            for x in range(10, Terrain.SIZE - 14):
                var o:Vector2i = Vector2i(x, z);
                if Vector2(o - world.town_hall.origin).length() > 45.0 or world.can_place(&"fishing_hut", o, size, false, facing) != "":
                    continue;
                for d in [Vector2i(5, 0), Vector2i(0, 5), Vector2i(-5, 0), Vector2i(0, -5)]:
                    if world.can_place(&"fishing_hut", o + d, size, false, facing) == "" and not Rect2i(o, size).intersects(Rect2i(o + d, size)):
                        return [o, o + d, size, facing];
    return [];

func _finish() -> void:
    Engine.time_scale = 1.0;
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0 and World.alive(_hut):          # windowed: a picture of the hut with its circle
        GameClock.set_speed(0);
        world.tools.select(_hut);
        world.camera_rig.focus_on(Vector3(_hut.position.x, 0.0, _hut.position.z));
        world.camera_rig._distance = 22.0;
        world.camera_rig._target_distance = 22.0;
        for i in 12:
            await get_tree().process_frame;
        get_viewport().get_texture().get_image().save_png(args[0].path_join("fishing.png"));
    print("FISHING %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
