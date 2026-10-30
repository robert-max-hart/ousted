# ----------------------------------------------------------------
# Merchant screenshot: the Trading Post with a merchant at it (M6).
#     godot --path . res://tests/merchant_shot.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

var world:World;
var _out:String = "user://";
var _frame:int = 0;
var _post:Building;

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
        if Rect2i(o - Vector2i(3, 3), Vector2i(16, 12)).has_point(rn.cell):
            world.remove_node(rn);
    _post = world.place_building(&"trading_post", o, Vector2i(4, 3), true);
    world.traders.start_visit();
    # put the cart a few cells short of the post instead of waiting for the walk from the edge
    var m:Merchant = world.traders.merchant;
    var route:Array[Vector2i] = m.path;
    m.position = world.terrain.cell_center(route[maxi(0, route.size() - 6)]);
    m._path_i = maxi(0, route.size() - 6);
    world.camera_rig.focus_on(Vector3(o.x + 2, 0, o.y + 2));
    world.camera_rig._distance = 11.0;
    world.camera_rig._target_distance = 11.0;
    world.tools.select(_post);
    GameClock.set_speed(1);

func _process(_delta:float) -> void:
    _frame += 1;
    if _frame >= 5 and _frame < 560 and world.traders.merchant != null:       # follow the cart close up
        var mp:Vector3 = world.traders.merchant.position;
        world.camera_rig.focus_on(Vector3(mp.x, 0, mp.z));
        world.camera_rig._distance = 7.0;
        world.camera_rig._target_distance = 7.0;
    if _frame == 60:
        get_viewport().get_texture().get_image().save_png(_out.path_join("merchant_a.png"));
    if _frame == 600:
        get_viewport().get_texture().get_image().save_png(_out.path_join("merchant_b.png"));
        get_tree().quit();
