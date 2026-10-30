# ----------------------------------------------------------------
# UI extras screenshot
#     The Citizens panel, a Woodcutter's inspector with its worker
#     list, a site with a priority tag, idle tags over citizens, and
#     a selected tree with its mark button.
#     godot --path . res://tests/ui_extras_shot.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

var world:World;
var _out:String = "user://";
var _frame:int = 0;
var _wood:Building;
var _tree:ResourceNode;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0:
        _out = args[0];
    Defs.difficulty = &"easy";
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    var o:Vector2i = TestSite.near(world, Vector2i(8, -8));
    for rn in world.nodes.duplicate():
        if Rect2i(o - Vector2i(3, 3), Vector2i(20, 14)).has_point(rn.cell):
            world.remove_node(rn);
    _wood = world.place_building(&"woodcutter", o, Vector2i(3, 3), true);
    var site:Building = world.place_building(&"house", o + Vector2i(6, 0), Vector2i(3, 3));
    site.set_priority(Building.PRIORITY_NAMES.size() - 1);
    _tree = world.add_node(&"tree", o + Vector2i(11, 1));
    world.jobs.change_profession(JobManager.Profession.WOODCUTTER, 2);
    world.camera_rig.focus_on(Vector3(o.x + 6, 0, o.y + 3));
    world.camera_rig._distance = 16.0;
    world.camera_rig._target_distance = 16.0;
    world.hud._citizens_toggle.button_pressed = true;
    world.tools.select(_wood);
    Engine.time_scale = 4.0;
    GameClock.set_speed(1);

func _process(_delta:float) -> void:
    _frame += 1;
    if _frame == 300:
        _shot("extras_a");
        world.tools.select(_tree);
    if _frame == 330:
        _shot("extras_b");
        get_tree().quit();

func _shot(n:String) -> void:
    get_viewport().get_texture().get_image().save_png(_out.path_join("%s.png" % n));
