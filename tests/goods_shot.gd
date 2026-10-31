# ----------------------------------------------------------------
# Goods shot
#     A stockpile holding a bit of every kind of good, to look at how
#     PileGoods draws them (logs, blocks, ingots, sacks, crates, barrels,
#     bales, pots, tools), at two distances and a fuller second pile.
#     godot --path . res://tests/goods_shot.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

var world:World;
var _out:String = "user://";
var _frame:int = 0;
var _pile:Building;
var _full:Building;
var _o:Vector2i;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0:
        _out = args[0];
    Defs.difficulty = &"easy";
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON * 1 + 3) * GameClock.HOURS_PER_DAY + 11.0;
    Weather._update_temperature();
    _o = TestSite.near(world, Vector2i(-22, -24), Vector2i(34, 16));
    for rn in world.nodes.duplicate():
        if Rect2i(_o - Vector2i(3, 3), Vector2i(34, 16)).has_point(rn.cell):
            world.remove_node(rn);
    world.terrain.flatten_rect(Rect2i(_o - Vector2i(2, 2), Vector2i(32, 14)));
    _pile = world.place_building(&"stockpile", _o, Vector2i(5, 3), true);
    _full = world.place_building(&"stockpile", _o + Vector2i(8, 0), Vector2i(5, 3), true);
    var each:Array = [&"wood", &"firewood", &"stone", &"coal", &"iron", &"gold", &"wheat", &"potato", &"apples", &"fish", &"milk", &"wool", &"pottery", &"tool_iron", &"manure"];
    for i in each.size():
        _pile.stored[each[i]] = _pile.capacity() / each.size();
    for item in [&"wood", &"stone", &"wheat", &"firewood"]:
        _full.stored[item] = _full.capacity() / 4;
    world.camera_rig.focus_on(Vector3(_o.x + 2.5, 0, _o.y + 1.5));
    world.camera_rig._distance = 11.0;
    world.camera_rig._target_distance = 11.0;
    Engine.time_scale = 1.0;

func _process(_delta:float) -> void:
    _frame += 1;
    match _frame:
        50:
            _shot("goods_a");
            world.camera_rig.focus_on(Vector3(_o.x + 1.5, 0, _o.y + 1.5));
            world.camera_rig._distance = 5.5;
            world.camera_rig._target_distance = 5.5;
        90:
            _shot("goods_b");
            world.camera_rig.focus_on(Vector3(_o.x + 10.5, 0, _o.y + 1.5));
            world.camera_rig._distance = 9.0;
            world.camera_rig._target_distance = 9.0;
        130:
            _shot("goods_c");
            get_tree().quit();

func _shot(n:String) -> void:
    get_viewport().get_texture().get_image().save_png(_out.path_join("%s.png" % n));
