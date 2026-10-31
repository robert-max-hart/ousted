# ----------------------------------------------------------------
# Tree shot
#     A row of each kind of tree (pine, oak, birch, palm, dead; a few of each, so the
#     variants show), a row of one oak at each stage of growing up, in summer, in
#     autumn, and in a snowy winter.
#     godot --path . res://tests/tree_shot.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

const KINDS:Array[StringName] = [&"tree", &"oak", &"birch", &"palm", &"dead"];
const STAGES:Array[float] = [0.08, 0.2, 0.3, 0.45, 0.65, 0.85, 1.0];

var world:World;
var _out:String = "user://";
var _frame:int = 0;
var _o:Vector2i;

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
    _o = TestSite.near(world, Vector2i(-22, -24), Vector2i(26, 22));
    for rn in world.nodes.duplicate():
        if Rect2i(_o - Vector2i(3, 3), Vector2i(26, 22)).has_point(rn.cell):
            world.remove_node(rn);
    world.terrain.flatten_rect(Rect2i(_o - Vector2i(2, 2), Vector2i(24, 20)));
    for row in KINDS.size():
        for i in 9:
            world.add_node(KINDS[row], _o + Vector2i(i * 2 + row % 2, row * 3));
    for i in STAGES.size():
        var rn:ResourceNode = world.add_node(&"oak" if i % 2 == 0 else &"palm", _o + Vector2i(i * 2, 16));
        rn.set_growth(STAGES[i]);
    world.renderer.mark_dirty();
    world.camera_rig.focus_on(Vector3(_o.x + 9.0, 0, _o.y + 8.0));
    world.camera_rig._distance = 26.0;
    world.camera_rig._target_distance = 26.0;
    world.camera_rig._pitch = deg_to_rad(-32.0);
    world.tools.select(null);

func _set_time(season:int, day:int) -> void:
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON * season + day) * GameClock.HOURS_PER_DAY + 12.0;
    Weather._update_temperature();
    world._apply_season(GameClock.season());
    world.renderer.update_foliage();

func _process(_delta:float) -> void:
    _frame += 1;
    match _frame:
        5:
            _set_time(1, 3);
        40:
            _shot("trees_summer");
            _set_time(2, 4);
        80:
            _shot("trees_autumn");
            _set_time(3, 3);
            world.visuals.snow_cover = 1.0;
        120:
            _shot("trees_winter");
            world.camera_rig._distance = 11.0;
            world.camera_rig._target_distance = 11.0;
            world.camera_rig.focus_on(Vector3(_o.x + 5.0, 0, _o.y + 16.0));
            world.visuals.snow_cover = 0.0;
            _set_time(1, 3);
        160:
            _shot("trees_growing");
            get_tree().quit();

func _shot(n:String) -> void:
    get_viewport().get_texture().get_image().save_png(_out.path_join("%s.png" % n));
