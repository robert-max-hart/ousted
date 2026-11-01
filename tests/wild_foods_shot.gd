# ----------------------------------------------------------------
# Wild foods shot: the wild foods of the other climates side by side
# (lingonberries, prickly pears, date palms, bananas, coconut palms),
# with a berry bush for scale.
#     godot --path . res://tests/wild_foods_shot.tscn -- <out_dir>
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
        if Rect2i(o - Vector2i(3, 3), Vector2i(20, 12)).has_point(rn.cell):
            world.remove_node(rn);
    world.terrain.flatten_rect(Rect2i(o - Vector2i(2, 2), Vector2i(18, 10)));
    var kinds:Array = [&"bush", &"lingon", &"cactus", &"date", &"banana", &"coconut"];
    for i in 2:
        for k in kinds.size():
            var rn:ResourceNode = world.add_node(kinds[k], o + Vector2i(k * 3 + i, i * 3));
            if rn != null:
                rn.amount = rn.max_amount;
    world.camera_rig.focus_on(Vector3(o.x + 8, 0, o.y + 2));
    world.camera_rig._distance = 12.0;
    world.camera_rig._target_distance = 12.0;
    world.camera_rig._pitch = deg_to_rad(-35.0);

func _process(_delta:float) -> void:
    _frame += 1;
    if _frame == 40:
        get_viewport().get_texture().get_image().save_png(_out.path_join("wild_foods.png"));
        get_tree().quit();
