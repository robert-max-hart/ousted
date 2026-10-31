# ----------------------------------------------------------------
# Citizen shot
#     Two rows of citizens frozen in poses, to look at the models and
#     the animation: standing, walking, carrying, an elder, a child, and
#     one at each kind of work (chop, hammer, pick, dig, rustle, anvil).
#     godot --path . res://tests/citizen_shot.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

var world:World;
var _out:String = "user://";
var _frame:int = 0;
var _o:Vector2i;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0:
        _out = args[0];
    Defs.difficulty = &"easy";
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON * 1 + 3) * GameClock.HOURS_PER_DAY + 11.0;
    Weather._update_temperature();
    _o = TestSite.near(world, Vector2i(-22, -24), Vector2i(20, 12));
    for rn in world.nodes.duplicate():
        if Rect2i(_o - Vector2i(3, 3), Vector2i(20, 12)).has_point(rn.cell):
            world.remove_node(rn);
    world.terrain.flatten_rect(Rect2i(_o - Vector2i(2, 2), Vector2i(18, 10)));
    world.camera_rig.focus_on(Vector3(_o.x + 6.0, 0, _o.y + 2.0));
    world.camera_rig._distance = 9.0;
    world.camera_rig._target_distance = 9.0;
    world.camera_rig._pitch = deg_to_rad(-24.0);          # a low angle, to see the poses from the side
    world.camera_rig._yaw = deg_to_rad(0.0);
    world.tools.select(null);

func _poses() -> Array:
    return [
        [PawnRig.Mode.IDLE, &"", false, 28.0],
        [PawnRig.Mode.WALK, &"", false, 28.0],
        [PawnRig.Mode.WALK, &"", true, 28.0],
        [PawnRig.Mode.IDLE, &"", false, 70.0],
        [PawnRig.Mode.IDLE, &"", false, 11.0],
        [PawnRig.Mode.IDLE, &"", false, 3.0],
        [PawnRig.Mode.WORK, &"chop", false, 30.0],
        [PawnRig.Mode.WORK, &"hammer", false, 30.0],
        [PawnRig.Mode.WORK, &"pick", false, 30.0],
        [PawnRig.Mode.WORK, &"dig", false, 30.0],
        [PawnRig.Mode.WORK, &"rustle", false, 30.0],
        [PawnRig.Mode.SLEEP, &"", false, 30.0],
    ];

func _process(_delta:float) -> void:
    _frame += 1;
    if _frame == 5:
        _arrange(0.0);
    match _frame:
        30:
            _shot("citizens_a");
            _arrange(0.4);
        50:
            _shot("citizens_b");
            _arrange(1.3);
        70:
            _shot("citizens_c");
            world.camera_rig.focus_on(Vector3(_o.x + 3.0, 0, _o.y + 2.0));
            world.camera_rig._distance = 6.0;
            world.camera_rig._target_distance = 6.0;
        90:
            _shot("citizens_close");
            get_tree().quit();

# Puts a citizen in each pose, in two rows, at animation time t (the work swing is at a different point of its cycle for each t).
func _arrange(t:float) -> void:
    var poses:Array = _poses();
    for i in poses.size():
        if i >= world.pawns.size():
            break;
        var p:Pawn = world.pawns[i];
        var d:Array = poses[i];
        p.age = d[3];
        p.carry_amount = 6 if d[2] else 0;
        p.carry_item = &"wood" if d[2] else &"";
        p._update_carry_visual();
        p._rig.set_stage(p.age, p.is_baby(), p.is_adult(), p.age >= 60.0);
        var col:int = i % 6;
        var row:int = i / 6;
        p.position = world.terrain.cell_center(_o + Vector2i(col * 2, row * 3));
        p.rotation.y = 0.0;
        p.rotation.y = PI * 0.5 if i % 2 == 0 else -PI * 0.5;          # side on, to the left or the right
        for k in 30:
            p._rig.pose(d[0], t, 1.0, d[1], d[2]);

func _shot(n:String) -> void:
    get_viewport().get_texture().get_image().save_png(_out.path_join("%s.png" % n));
