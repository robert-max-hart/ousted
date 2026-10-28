# ----------------------------------------------------------------
# Building gallery screenshot
#     One of every building in two rows, for judging textures and
#     silhouettes.
#     godot --path . res://tests/gallery_shot.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

const ROWS:Array = [
    [&"house", &"town_hall", &"granary", &"school", &"stockpile"],
    [&"woodcutter", &"forager", &"blacksmith", &"mine", &"well", &"shack"],
];

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
    GameClock.total_hours = 3.0 * GameClock.HOURS_PER_DAY + 12.0;
    var o:Vector2i = world.town_hall.origin + Vector2i(8, -8);
    for rn in world.nodes.duplicate():
        if Rect2i(o - Vector2i(2, 2), Vector2i(40, 24)).has_point(rn.cell):
            world.remove_node(rn);
    for r in ROWS.size():
        var x:int = 0;
        for id in ROWS[r]:
            if id == &"town_hall":
                continue;      # the start colony already has one
            var sz:Vector2i = Defs.BUILDINGS[id]["size"];
            world.place_building(id, o + Vector2i(x, r * 8), sz, true);
            x += sz.x + 2;
    world.camera_rig.focus_on(Vector3(o.x + 14, 0, o.y + 8));
    world.camera_rig._distance = 26.0;
    world.camera_rig._target_distance = 26.0;
    world.tools.select(null);

func _process(_delta:float) -> void:
    _frame += 1;
    if _frame == 20:
        get_viewport().get_texture().get_image().save_png(_out.path_join("gallery.png"));
        get_tree().quit();
