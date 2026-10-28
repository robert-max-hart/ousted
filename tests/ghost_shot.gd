# ----------------------------------------------------------------
# Placement ghost screenshot
#     The Granary ghost placed on open ground (green), with the
#     colony's stores emptied (orange), and on water (red).
#     godot --path . res://tests/ghost_shot.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

var world:World;
var _out:String = "user://";
var _frame:int = 0;
var _spot:Vector2i;
var _water:Vector2i;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0:
        _out = args[0];
    Defs.difficulty = &"easy";
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    _spot = world.town_hall.origin + Vector2i(8, -8);
    for rn in world.nodes.duplicate():
        if Rect2i(_spot - Vector2i(3, 3), Vector2i(12, 12)).has_point(rn.cell):
            world.remove_node(rn);
    for z in Terrain.SIZE:
        for x in Terrain.SIZE:
            if _water == Vector2i.ZERO and world.terrain.is_water(Vector2i(x, z)) and world.terrain.is_water(Vector2i(x + 3, z)) and world.terrain.is_water(Vector2i(x, z + 3)):
                _water = Vector2i(x, z);
    world.camera_rig.focus_on(Vector3(_spot.x + 1.5, 0, _spot.y + 1.5));
    world.camera_rig._distance = 12.0;
    world.camera_rig._target_distance = 12.0;
    world.tools.set_mode(PlayerTools.Mode.BUILD, &"granary");
    world.tools.set_process(false);
    world.tools._hover_ok = true;
    world.tools._hover_cell = _spot;

func _process(_delta:float) -> void:
    _frame += 1;
    world.tools._hover_ok = true;
    var at:Vector2i = _spot if _frame < 240 else _water;
    world.tools._hover_cell = at;
    world.tools._hover_pt = Vector3(at.x + 1.5, 0, at.y + 1.5);
    if _frame == 100:
        world.tools._update_ghosts();
    if _frame == 120:
        _shot("ok");
        for b in world.buildings:
            b.stored.clear();
    if _frame >= 130 and _frame < 260:
        world.tools._update_ghosts();
    if _frame == 220:
        _shot("short");
    if _frame == 300:
        world.camera_rig.focus_on(Vector3(_water.x + 1.5, 0, _water.y + 1.5));
    if _frame == 330:
        _shot("bad");
        get_tree().quit();
    if _frame >= 260:
        world.tools._update_ghosts();

func _shot(n:String) -> void:
    get_viewport().get_texture().get_image().save_png(_out.path_join("ghost_%s.png" % n));
