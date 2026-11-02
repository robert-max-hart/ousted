# ----------------------------------------------------------------
# Fill bars shot
#     Four stores, empty to full, each with its bar.
#     godot --path . res://tests/fill_bars_shot.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

var world:World;
var _out:String = "user://";
var _frame:int = 0;
var _o:Vector2i;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Weather.drought_enabled = false;
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0:
        _out = args[0];
    Defs.difficulty = &"easy";
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON * 1 + 3) * GameClock.HOURS_PER_DAY + 12.0;
    Weather._update_temperature();
    _o = TestSite.near(world, Vector2i(-24, -24), Vector2i(26, 10));
    for rn in world.nodes.duplicate():
        if Rect2i(_o - Vector2i(3, 3), Vector2i(26, 10)).has_point(rn.cell):
            world.remove_node(rn);
    world.terrain.flatten_rect(Rect2i(_o - Vector2i(2, 2), Vector2i(24, 8)));
    var ids:Array[StringName] = [&"stockpile", &"granary", &"root_cellar", &"stockpile"];
    var fills:Array[float] = [0.3, 0.75, 0.95, 0.0];
    for i in 4:
        var size:Vector2i = Defs.BUILDINGS[ids[i]]["size"];
        var b:Building = world.place_building(ids[i], _o + Vector2i(i * 6, 0), size, true);
        var item:StringName = &"wood" if ids[i] == &"stockpile" else &"wheat";
        b.store(item, roundi(b.capacity() * fills[i]));
    world.fill_bars.show_all = true;
    world.camera_rig.focus_on(Vector3(_o.x + 9.0, 0, _o.y + 2.0));
    world.camera_rig._distance = 18.0;
    world.camera_rig._target_distance = 18.0;
    world.camera_rig._pitch = deg_to_rad(-35.0);
    world.tools.select(null);

func _process(_delta:float) -> void:
    _frame += 1;
    if _frame == 30:
        get_viewport().get_texture().get_image().save_png(_out.path_join("fill_bars.png"));
        get_tree().quit();
