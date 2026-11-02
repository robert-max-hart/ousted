# ----------------------------------------------------------------
# Herb greenhouse shot
#     The Herbalist's Hut before and after the Herb Greenhouse, from the front and from behind.
#     godot --path . res://tests/herb_greenhouse_shot.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

var world:World;
var _out:String = "user://";
var _frame:int = 0;
var _o:Vector2i;
var _hut:Herbalist;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Weather.drought_enabled = false;
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0:
        _out = args[0];
    Defs.difficulty = &"easy";
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON * 1 + 3) * GameClock.HOURS_PER_DAY + 12.0;
    Weather._update_temperature();
    _o = TestSite.near(world, Vector2i(-24, -24), Vector2i(10, 10));
    for rn in world.nodes.duplicate():
        if Rect2i(_o - Vector2i(3, 3), Vector2i(12, 12)).has_point(rn.cell):
            world.remove_node(rn);
    world.terrain.flatten_rect(Rect2i(_o - Vector2i(2, 2), Vector2i(10, 10)));
    _hut = world.place_building(&"herbalist", _o + Vector2i(1, 2), Vector2i(3, 3), true) as Herbalist;
    world.tools.select(null);
    _aim(0.0);

func _aim(yaw:float) -> void:
    world.camera_rig.focus_on(Vector3(_o.x + 2.5, 0, _o.y + 3.5));
    world.camera_rig._distance = 8.0;
    world.camera_rig._target_distance = 8.0;
    world.camera_rig._pitch = deg_to_rad(-30.0);
    world.camera_rig._yaw = yaw;

func _shot(name:String) -> void:
    get_viewport().get_texture().get_image().save_png(_out.path_join("herb_%s.png" % name));

func _process(_delta:float) -> void:
    _frame += 1;
    match _frame:
        10:
            _shot("before");
            _hut.start_upgrade(&"greenhouse");
            for item in _hut.cost():
                _hut.receive(item, _hut.cost()[item]);
            _hut.add_work(_hut.work_required());
        20:
            _shot("after_front");
            _aim(PI);
        30:
            _shot("after_back");
            get_tree().quit();
