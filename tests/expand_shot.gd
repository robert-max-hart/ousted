# ----------------------------------------------------------------
# Expand tool screenshot
#     The Expand ghost over a field being grown to the right, and
#     the inspector's Expand button.
#     godot --path . res://tests/expand_shot.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

var world:World;
var _out:String = "user://";
var _frame:int = 0;
var _field:Field;
var _at:Vector2i;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0:
        _out = args[0];
    Defs.difficulty = &"easy";
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    var o:Vector2i = world.town_hall.origin + Vector2i(8, -12);
    for rn in world.nodes.duplicate():
        if Rect2i(o - Vector2i(3, 3), Vector2i(24, 20)).has_point(rn.cell):
            world.remove_node(rn);
    world.terrain.flatten_rect(Rect2i(o - Vector2i(2, 2), Vector2i(26, 22)));
    _field = world.place_building(&"field", o, Vector2i(5, 5), true) as Field;
    world.place_building(&"stockpile", o + Vector2i(9, 0), Vector2i(4, 4), true).store(&"wood", 60);
    _at = o + Vector2i(7, 3);
    world.camera_rig.focus_on(Vector3(o.x + 6, 0, o.y + 3));
    world.camera_rig._distance = 14.0;
    world.camera_rig._target_distance = 14.0;
    world.tools.select(_field);
    world.tools.start_expand(_field);
    world.tools.set_process(false);

func _process(_delta:float) -> void:
    _frame += 1;
    world.tools._hover_ok = true;
    world.tools._hover_cell = _at;
    world.tools._hover_pt = Vector3(_at.x + 0.5, 0, _at.y + 0.5);
    if _frame > 5:
        world.tools._update_ghosts();
    if _frame == 40:
        get_viewport().get_texture().get_image().save_png(_out.path_join("expand.png"));
        print(world.tools.size_text());
        get_tree().quit();
