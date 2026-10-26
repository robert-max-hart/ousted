# ----------------------------------------------------------------
# Graveyard screenshot
#     A finished graveyard with some graves and a body lying beside it,
#     then its inspector and a citizen's happiness factors.
#     godot --path . res://tests/graveyard_shot.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

var world:World;
var yard:Graveyard;
var _frame:int = 0;
var _out:String = "user://";

func _ready() -> void:
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0:
        _out = args[0];
    SaveGame.autosave_enabled = false;
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    GameClock.total_hours = 11.0;
    var th:Building = world.town_hall;
    world.place_building(&"house", th.origin + Vector2i(-5, 0), Vector2i(3, 3), true);
    yard = world.place_building(&"graveyard", th.origin + Vector2i(6, -2), Vector2i(6, 4), true) as Graveyard;
    for i in [0, 1, 2, 7, 8, 13]:
        yard.graves[i] = {"name": "Test", "age": 40, "cause": "old age", "buried_hour": 0.0};
    yard._visual_dirty = true;
    world.kill_pawn(world.pawns[5], "old age");
    world.bodies[0].position = world.terrain.cell_center(th.origin + Vector2i(4, 2));
    world.pawns[0].add_grief(0.3, 12.0, 99);
    world.tools.select(yard);
    world.camera_rig.focus_on(yard.position);
    world.camera_rig._distance = 18.0;
    world.camera_rig._target_distance = 18.0;

func _process(_delta:float) -> void:
    _frame += 1;
    if _frame == 60:
        _shot("grave_01.png");
        world.tools.select(world.pawns[0]);
    elif _frame == 80:
        _shot("grave_02.png");
        get_tree().quit();

func _shot(file:String) -> void:
    get_viewport().get_texture().get_image().save_png(_out.path_join(file));
    print("saved ", file);
