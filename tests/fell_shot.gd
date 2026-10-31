# ----------------------------------------------------------------
# Felling shot
#     An oak, a pine and a palm on clear ground are felled from the left;
#     pictures at intervals show them tipping over, lying and sinking.
#     godot --path . res://tests/fell_shot.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

var world:World;
var _out:String = "user://";
var _frame:int = 0;
var _o:Vector2i;
var _start:int = 0;
var _shots:int = 0;
var _trees:Array[ResourceNode] = [];

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
    _o = TestSite.near(world, Vector2i(-22, -24), Vector2i(16, 10));
    for rn in world.nodes.duplicate():
        if Rect2i(_o - Vector2i(3, 3), Vector2i(16, 10)).has_point(rn.cell):
            world.remove_node(rn);
    world.terrain.flatten_rect(Rect2i(_o - Vector2i(2, 2), Vector2i(14, 8)));
    for i in 3:
        _trees.append(world.add_node([&"oak", &"tree", &"palm"][i], _o + Vector2i(3 + i * 4, 3)));
    world.renderer.mark_dirty();
    world.camera_rig.focus_on(Vector3(_o.x + 7.5, 0, _o.y + 3.5));
    world.camera_rig._distance = 15.0;
    world.camera_rig._target_distance = 15.0;
    world.camera_rig._pitch = deg_to_rad(-22.0);
    world.camera_rig._yaw = deg_to_rad(0.0);
    world.tools.select(null);

func _process(_delta:float) -> void:
    _frame += 1;
    if _frame == 30:
        GameClock.set_speed(1);          # the felling clock runs with the game
        for rn in _trees:
            world.renderer.fell(rn, Vector3(rn.cell.x - 3.0, 0, rn.cell.y));
            world.remove_node(rn);
        _start = Time.get_ticks_msec();
    if _frame > 30 and _shots < 5 and Time.get_ticks_msec() - _start > [0, 500, 900, 1400, 2600][_shots]:
        get_viewport().get_texture().get_image().save_png(_out.path_join("fell_%d.png" % _shots));
        _shots += 1;
    if _shots >= 5:
        get_tree().quit();
