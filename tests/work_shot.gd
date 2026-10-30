# ----------------------------------------------------------------
# Work animation screenshot
#     A house goes up beside the Town Hall; the shot is taken once a
#     builder is hammering at it (leaning in, tool swinging).
#     godot --path . res://tests/work_shot.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

var world:World;
var _out:String = "user://";
var _frame:int = 0;
var _site:Building;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0:
        _out = args[0];
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.total_hours = 3.0 * GameClock.HOURS_PER_DAY + 9.0;
    var o:Vector2i = TestSite.near(world, Vector2i(8, -3));
    for rn in world.nodes.duplicate():
        if Rect2i(o - Vector2i(3, 3), Vector2i(10, 10)).has_point(rn.cell):
            world.remove_node(rn);
    _site = world.place_building(&"house", o, Vector2i(3, 3));
    world.camera_rig.focus_on(Vector3(o.x + 1.5, 0, o.y + 1.5));
    world.camera_rig._distance = 9.0;
    world.camera_rig._target_distance = 9.0;
    world.tools.select(null);
    Engine.time_scale = 3.0;
    GameClock.set_speed(1);

func _process(_delta:float) -> void:
    _frame += 1;
    var hammering:int = 0;
    for p in world.pawns:
        if p.task != null and p.task.kind == &"build" and p.position.distance_to(_site.position) < 3.0:
            hammering += 1;
    if _frame > 120 and hammering > 0 and _frame % 7 == 0:
        get_viewport().get_texture().get_image().save_png(_out.path_join("work_%d.png" % _frame));
        if _frame > 150:
            get_tree().quit();
    elif _frame > 4000:
        get_tree().quit();
