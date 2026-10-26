# ----------------------------------------------------------------
# Detail screenshot
#     Houses with doors and lit windows, berry bushes, and a field
#     with each crop shape at three growth stages.
#     godot --path . res://tests/detail_shot.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

var world:World;
var _out:String = "user://";
var _frame:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0:
        _out = args[0];
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    GameClock.total_hours = 3.0 * GameClock.HOURS_PER_DAY + 12.0;
    var th:Building = world.town_hall;
    var o:Vector2i = th.origin + Vector2i(6, -2);
    for rn in world.nodes.duplicate():
        if Rect2i(o - Vector2i(2, 2), Vector2i(30, 16)).has_point(rn.cell):
            world.remove_node(rn);
    var lit:Building = world.place_building(&"house", o, Vector2i(3, 3), true);
    var dark:Building = world.place_building(&"house", o + Vector2i(5, 0), Vector2i(3, 3), true);
    world.place_building(&"granary", o + Vector2i(10, 0), Vector2i(3, 3), true);
    world.families.move_home(world.pawns[0], lit);
    for i in 4:
        var b:ResourceNode = world.add_node(&"bush", o + Vector2i(i * 2, 5));
        b.amount = [5, 3, 1, 0][i];
    var f:Field = world.place_building(&"field", o + Vector2i(0, 8), Vector2i(12, 4), true) as Field;
    var crops:Array[StringName] = [&"wheat", &"beans", &"lettuce", &"pumpkin"];
    for i in f.plot_count():
        var cell:Vector2i = f.plot_cell(i);
        f.plot_crop[i] = crops[(cell.x - f.origin.x) / 3];
        f.plot_state[i] = Field.Plot.PLANTED if (cell.y - f.origin.y) < 3 else Field.Plot.RIPE;
        f.growth[i] = [0.3, 0.65, 0.9][(cell.y - f.origin.y) % 3];
    f._visual_dirty = true;
    world.camera_rig.focus_on(Vector3(o.x + 6, 0, o.y + 5));
    world.camera_rig._distance = 11.0;
    world.camera_rig._target_distance = 11.0;
    world.tools.select(null);

func _process(_delta:float) -> void:
    _frame += 1;
    if _frame == 15:
        get_viewport().get_texture().get_image().save_png(_out.path_join("detail.png"));
        get_tree().quit();
