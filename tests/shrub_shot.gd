# ----------------------------------------------------------------
# Shrub screenshot: a berry bush (fruiting), a hazel grove and a
# mushroom patch side by side, to compare their shapes.
#     godot --path . res://tests/shrub_shot.tscn -- <out_dir>
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
    Defs.difficulty = &"easy";
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    var o:Vector2i = TestSite.near(world, Vector2i(8, -10));
    for rn in world.nodes.duplicate():
        if Rect2i(o - Vector2i(3, 3), Vector2i(16, 10)).has_point(rn.cell):
            world.remove_node(rn);
    world.terrain.flatten_rect(Rect2i(o - Vector2i(2, 2), Vector2i(14, 8)));
    for i in 3:
        for kind in [&"bush", &"hazel", &"mushroom"]:
            var rn:ResourceNode = world.add_node(kind, o + Vector2i(i * 4 + [&"bush", &"hazel", &"mushroom"].find(kind), [&"bush", &"hazel", &"mushroom"].find(kind) * 2));
            rn.amount = rn.max_amount;
    world.camera_rig.focus_on(Vector3(o.x + 5, 0, o.y + 2));
    world.camera_rig._distance = 9.0;
    world.camera_rig._target_distance = 9.0;

func _process(_delta:float) -> void:
    _frame += 1;
    if _frame == 40:
        get_viewport().get_texture().get_image().save_png(_out.path_join("shrubs.png"));
        get_tree().quit();
