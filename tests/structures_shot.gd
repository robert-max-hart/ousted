# ----------------------------------------------------------------
# Structures shot
#     A crop field, a pasture, a stockpile, a graveyard with graves and bridges (along x and along z, short
#     and long), to look at the fences, the stone wall, the headstones and the bridge pieces.
#     godot --path . res://tests/structures_shot.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

var world:World;
var _out:String = "user://";
var _frame:int = 0;
var _o:Vector2i;
var _winter:bool = false;       # a second argument `snow`: winter, with snow on the ground

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Weather.drought_enabled = false;
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0:
        _out = args[0];
    Defs.difficulty = &"easy";
    _winter = args.size() > 1 and args[1] == "snow";
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON * (3 if _winter else 1) + 3) * GameClock.HOURS_PER_DAY + 12.0;
    Weather._update_temperature();
    _o = TestSite.near(world, Vector2i(-24, -24), Vector2i(34, 20));
    for rn in world.nodes.duplicate():
        if Rect2i(_o - Vector2i(3, 3), Vector2i(34, 20)).has_point(rn.cell):
            world.remove_node(rn);
    world.terrain.flatten_rect(Rect2i(_o - Vector2i(2, 2), Vector2i(32, 18)));
    world.place_building(&"field", _o, Vector2i(6, 6), true);
    world.place_building(&"pasture", _o + Vector2i(8, 0), Vector2i(6, 5), true);
    var pile:Building = world.place_building(&"stockpile", _o + Vector2i(16, 0), Vector2i(4, 4), true);
    pile.stored[&"wood"] = 40;
    var yard:Graveyard = world.place_building(&"graveyard", _o + Vector2i(22, 0), Vector2i(6, 5), true) as Graveyard;
    for i in 9:
        yard.graves[i * 3] = {"name": "Test", "age": 40.0, "cause": "age", "buried_hour": 0.0};
    yard._visual_dirty = true;
    world.place_building(&"bridge", _o + Vector2i(0, 9), Vector2i(7, 1), true);
    world.place_building(&"bridge", _o + Vector2i(9, 8), Vector2i(1, 5), true);
    world.place_building(&"bridge", _o + Vector2i(12, 9), Vector2i(3, 1), true);
    world.place_building(&"bridge", _o + Vector2i(0, 14), Vector2i(12, 1), true);       # long enough to arch
    world.camera_rig.focus_on(Vector3(_o.x + 12.0, 0, _o.y + 5.0));
    world.camera_rig._distance = 26.0;
    world.camera_rig._target_distance = 26.0;
    world.camera_rig._pitch = deg_to_rad(-38.0);
    world.tools.select(null);

func _process(_delta:float) -> void:
    _frame += 1;
    if _winter:
        world.visuals.snow_cover = 0.75;
    if _frame > 190 and not world.pawns.is_empty():
        world.pawns[0].position = Vector3(_o.x + 11.5, world.terrain.height_at(_o.x + 11.5, _o.y + 6.3), _o.y + 6.3);       # a citizen at the pasture's gate
    match _frame:
        40:
            _shot("structures_all");
            world.camera_rig.focus_on(Vector3(_o.x + 25.0, 0, _o.y + 3.0));
            world.camera_rig._distance = 9.0;
            world.camera_rig._target_distance = 9.0;
            world.camera_rig._pitch = deg_to_rad(-30.0);
        70:
            _shot("structures_graves");
            world.camera_rig.focus_on(Vector3(_o.x + 4.0, 0, _o.y + 9.5));
            world.camera_rig._distance = 8.0;
            world.camera_rig._target_distance = 8.0;
        100:
            _shot("structures_bridge");
            world.camera_rig.focus_on(Vector3(_o.x + 7.0, 0, _o.y + 2.0));
            world.camera_rig._distance = 9.0;
            world.camera_rig._target_distance = 9.0;
        130:
            _shot("structures_fences");
            world.camera_rig.focus_on(Vector3(_o.x + 4.0, 0, _o.y + 13.0));
            world.camera_rig._distance = 8.0;
            world.camera_rig._target_distance = 8.0;
            world.camera_rig._pitch = deg_to_rad(-14.0);
            world.camera_rig._yaw = deg_to_rad(20.0);
        160:
            _shot("structures_arch");
            world.camera_rig.focus_on(Vector3(_o.x + 11.5, 0, _o.y + 5.5));
            world.camera_rig._distance = 6.0;
            world.camera_rig._target_distance = 6.0;
            world.camera_rig._pitch = deg_to_rad(-28.0);
            world.camera_rig._yaw = deg_to_rad(0.0);
        190:
            _shot("structures_gate_shut");
            GameClock.set_speed(1);
        240:
            _shot("structures_gate_open");
            get_tree().quit();

func _shot(n:String) -> void:
    get_viewport().get_texture().get_image().save_png(_out.path_join("%s.png" % n));
