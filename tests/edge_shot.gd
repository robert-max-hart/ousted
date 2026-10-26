# ----------------------------------------------------------------
# Map edge screenshot
#     Looks at the map edge where it is water, from a few sides.
#     godot --path . res://tests/edge_shot.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

var world:World;
var _out:String = "user://";
var _frame:int = 0;
var _spots:Array[Vector3] = [];

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0:
        _out = args[0];
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    var s:float = Terrain.SIZE;
    for i in range(4, int(s), 12):
        for e in [Vector2(i, 1), Vector2(i, s - 1), Vector2(1, i), Vector2(s - 1, i)]:
            if world.terrain.is_water(Vector2i(e)) and _spots.size() < 3:
                _spots.append(Vector3(e.x, 0, e.y));
    print("water edge spots: ", _spots);

func _process(_delta:float) -> void:
    _frame += 1;
    var i:int = _frame / 10;
    if _frame % 10 == 1 and i < _spots.size():
        world.camera_rig.focus_on(_spots[i]);
    if _frame % 10 == 8 and i < _spots.size():
        get_viewport().get_texture().get_image().save_png(_out.path_join("edge_%d.png" % i));
    if i >= maxi(_spots.size(), 1):
        get_tree().quit();
