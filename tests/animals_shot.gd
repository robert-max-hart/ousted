# ----------------------------------------------------------------
# Animals shot
#     Three pastures, of chickens, sheep and cows, with the herds wandering, at a few moments; and a merchant's
#     caravan (the donkey) and a few animals being led.
#     godot --path . res://tests/animals_shot.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

var world:World;
var _out:String = "user://";
var _frame:int = 0;
var _o:Vector2i;
var _start:int = 0;
var _shots:int = 0;

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
    _o = TestSite.near(world, Vector2i(-24, -24), Vector2i(26, 10));
    for rn in world.nodes.duplicate():
        if Rect2i(_o - Vector2i(3, 3), Vector2i(26, 10)).has_point(rn.cell):
            world.remove_node(rn);
    world.terrain.flatten_rect(Rect2i(_o - Vector2i(2, 2), Vector2i(24, 8)));
    var kinds:Array[StringName] = [&"chicken", &"sheep", &"cow"];
    var counts:Array[int] = [7, 6, 4];
    for i in 3:
        var p:Pasture = world.place_building(&"pasture", _o + Vector2i(i * 7, 0), Vector2i(6, 6), true) as Pasture;
        p.set_kind(kinds[i]);
        p.animals = counts[i];
        p.young_ages.assign([[0.5, 2.0, 4.0], [1.0, 6.0], [2.0]][i]);       # the last of the herd are young: drawn small
    world.camera_rig.focus_on(Vector3(_o.x + 10.0, 0, _o.y + 3.0));
    world.camera_rig._distance = 15.0;
    world.camera_rig._target_distance = 15.0;
    world.camera_rig._pitch = deg_to_rad(-28.0);
    world.tools.select(null);

func _process(_delta:float) -> void:
    _frame += 1;
    if _frame == 20:
        GameClock.set_speed(1);          # the animals follow the game clock
        _start = Time.get_ticks_msec();
    if _frame > 20 and _shots < 5 and Time.get_ticks_msec() - _start > [500, 1800, 3500, 6000, 9000][_shots]:
        if _shots == 3:
            world.camera_rig.focus_on(Vector3(_o.x + 3.0, 0, _o.y + 3.0));
            world.camera_rig._distance = 7.0;
            world.camera_rig._target_distance = 7.0;
        if _shots == 4:
            world.camera_rig.focus_on(Vector3(_o.x + 17.0, 0, _o.y + 3.0));
        get_viewport().get_texture().get_image().save_png(_out.path_join("animals_%d.png" % _shots));
        _shots += 1;
    if _shots >= 5:
        get_tree().quit();
