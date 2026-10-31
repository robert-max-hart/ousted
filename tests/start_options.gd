# ----------------------------------------------------------------
# Start options test
#     The three ways to start: with a Town Hall, with only a well, with
#     nothing. In every case all the starting goods are there (in the hall
#     as far as it goes, the rest in supply carts; with no hall all of it in
#     carts, however big the stock), the first building is what was asked
#     for, a Town Hall can still be built later, the choose-your-start
#     ghost matches, and the colony runs.
#     godot --headless --path . --fixed-fps 60 res://tests/start_options.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"normal";
    var total:int = 0;
    for item in World.START_STOCK:
        total += World.START_STOCK[item];
    for mode in [GameRules.Start.HALL, GameRules.Start.WELL, GameRules.Start.NOTHING]:
        for supplies in [2, 4]:          # normal, and double (more than one cart holds)
            GameRules.reset();
            GameRules.start = mode;
            GameRules.supplies = supplies;
            GameClock.reset();
            var label:String = "%s start, supplies x%.0f" % [GameRules.START_NAMES[mode], GameRules.supply_share()];
            var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
            add_child(world);
            await get_tree().process_frame;
            var want:int = 0;
            for item in World.START_STOCK:
                want += roundi(World.START_STOCK[item] * GameRules.supply_share());
            var stored:int = 0;
            for b in world.buildings:
                stored += b.used();
            _expect("%s: every starting good is there (%d of %d)" % [label, stored, want], stored == want);
            match mode:
                GameRules.Start.HALL:
                    _expect("%s: the first building is the finished Town Hall" % label, world.town_hall != null and world.start_building == world.town_hall and world.town_hall.is_complete());
                GameRules.Start.WELL:
                    _expect("%s: a finished well and no Town Hall" % label, world.town_hall == null and world.start_building.def_id == &"well" and world.start_building.is_complete());
                GameRules.Start.NOTHING:
                    _expect("%s: just a supply cart, no well or hall" % label, world.town_hall == null and world.start_building.def_id == &"cart" and world.buildings.all(func(b:Building) -> bool: return b.def_id == &"cart"));
            if mode != GameRules.Start.HALL:
                _expect("%s: everything is in carts" % label, world.buildings.all(func(b:Building) -> bool: return b.def_id == &"cart" or b == world.start_building));
                var carts:int = world.buildings.filter(func(b:Building) -> bool: return b.def_id == &"cart").size();
                if supplies == 4:
                    _expect("%s: more than one cart (%d)" % [label, carts], carts >= 2);
                var size:Vector2i = Defs.BUILDINGS[&"town_hall"]["size"];
                var spot:Vector2i = _hall_spot(world, size);
                _expect("%s: a Town Hall can still be built (%s)" % [label, spot], spot.x >= 0);
            _expect("%s: the settlers are there" % label, world.pawns.size() == GameRules.settlers);
            GameClock.set_speed(3);
            Engine.time_scale = 4.0;
            await get_tree().create_timer(2.0).timeout;
            Engine.time_scale = 1.0;
            GameClock.set_speed(0);
            _expect("%s: the colony runs for a while" % label, world.pawns.size() >= GameRules.settlers - 1);
            world.queue_free();
            await get_tree().process_frame;

    # choosing the start: the ghost is the well, and a click founds the colony with it
    GameRules.reset();
    GameRules.start = GameRules.Start.WELL;
    World.choose_start = true;
    GameClock.reset();
    var pick:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(pick);
    await get_tree().process_frame;
    _expect("choosing: the well is the ghost (%s, mode %d, id %s)" % [pick.awaiting_start, pick.tools.mode, pick.tools.build_id], pick.awaiting_start and pick.tools.mode == PlayerTools.Mode.BUILD and pick.tools.build_id == &"well");
    var origin:Vector2i = pick.suggested_start - Vector2i.ONE;
    var err:String = pick.begin_colony(origin);
    _expect("choosing: a click founds the colony (%s)" % err, err == "" and pick.start_building != null and pick.start_building.def_id == &"well" and pick.start_building.origin == origin and pick.town_hall == null);
    GameRules.reset();
    print("START OPTIONS %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

# Somewhere near the start where the game accepts a Town Hall (the ground may be steep or wet in places), or (-1, -1).
func _hall_spot(world:World, size:Vector2i) -> Vector2i:
    var home:Vector2i = TestSite.anchor(world);
    for r in range(4, 40, 2):
        for dz in range(-r, r + 1, 2):
            for dx in range(-r, r + 1, 2):
                var o:Vector2i = home + Vector2i(dx, dz);
                if world.can_place(&"town_hall", o, size) == "" and world._rect_free_of_nodes(Rect2i(o, size)):
                    return o;
    return Vector2i(-1, -1);

func _expect(what:String, ok:bool) -> void:
    print("%s: %s" % ["PASS" if ok else "FAIL", what]);
    if not ok:
        _fails += 1;
