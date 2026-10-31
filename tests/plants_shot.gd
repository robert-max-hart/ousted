# ----------------------------------------------------------------
# Plants shot
#     An orchard with all seven fruit trees (ripe in the first rows, young below), and rows of rocks,
#     ore, berry bushes, hazel and mushrooms, in spring, summer, autumn and winter.
#     godot --path . res://tests/plants_shot.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

const CROPS:Array[StringName] = [&"apple", &"pear", &"cherry", &"peach", &"plum", &"walnut", &"pecan"];

var world:World;
var _out:String = "user://";
var _frame:int = 0;
var _o:Vector2i;
var _orchard:Field;

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
    world.seeds.unlock_all();
    _o = TestSite.near(world, Vector2i(-22, -24), Vector2i(24, 18));
    for rn in world.nodes.duplicate():
        if Rect2i(_o - Vector2i(3, 3), Vector2i(24, 18)).has_point(rn.cell):
            world.remove_node(rn);
    world.terrain.flatten_rect(Rect2i(_o - Vector2i(2, 2), Vector2i(22, 16)));
    _orchard = world.place_building(&"orchard", _o, Vector2i(7, 5), true) as Field;
    for i in _orchard.plot_count():
        var col:int = i % 7;
        var row:int = i / 7;
        _orchard.plot_crop[i] = CROPS[col];
        _orchard.plot_state[i] = Field.Plot.RIPE if row < 2 else Field.Plot.PLANTED;
        _orchard.growth[i] = 1.0 if row < 2 else [0.2, 0.5, 0.8][row - 2];
        _orchard.moisture[i] = 0.6;
    _orchard._visual_dirty = true;
    for i in 4:
        world.add_node(&"rock", _o + Vector2i(i * 3, 8));
        world.add_node(&"ore", _o + Vector2i(i * 3 + 1, 11));
    for i in 6:
        world.add_node(&"bush", _o + Vector2i(i * 2, 14));
        world.add_node(&"hazel", _o + Vector2i(i * 2 + 12, 14));
    for i in 3:
        var m:ResourceNode = world.add_node(&"mushroom", _o + Vector2i(i * 2 + 14, 8));
        m.amount = 3 if i < 2 else 0;
    for rn in world.nodes:
        if rn.kind == &"bush" or rn.kind == &"hazel":
            rn.amount = rn.max_amount;
    world.renderer.mark_dirty();
    world.camera_rig.focus_on(Vector3(_o.x + 8.0, 0, _o.y + 8.0));
    world.camera_rig._distance = 19.0;
    world.camera_rig._target_distance = 19.0;
    world.camera_rig._pitch = deg_to_rad(-38.0);
    world.tools.select(null);

func _season(season:int, day:int) -> void:
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON * season + day) * GameClock.HOURS_PER_DAY + 12.0;
    Weather._update_temperature();
    world._apply_season(GameClock.season());
    world.renderer.update_foliage();
    world.renderer.mark_dirty();
    _orchard._visual_dirty = true;

func _process(_delta:float) -> void:
    _frame += 1;
    match _frame:
        5:
            _season(0, 1);
        30:
            _shot("plants_spring");
            _season(1, 3);
        55:
            _shot("plants_summer");
            world.camera_rig.focus_on(Vector3(_o.x + 3.5, 0, _o.y + 2.5));
            world.camera_rig._distance = 7.5;
            world.camera_rig._target_distance = 7.5;
            world.camera_rig._pitch = deg_to_rad(-28.0);
        80:
            _shot("plants_orchard");
            world.camera_rig.focus_on(Vector3(_o.x + 8.0, 0, _o.y + 8.0));
            world.camera_rig._distance = 19.0;
            world.camera_rig._target_distance = 19.0;
            world.camera_rig._pitch = deg_to_rad(-38.0);
            _season(2, 5);
        105:
            _shot("plants_autumn");
            _season(3, 3);
            world.visuals.snow_cover = 0.8;
        130:
            _shot("plants_winter");
            get_tree().quit();

func _shot(n:String) -> void:
    get_viewport().get_texture().get_image().save_png(_out.path_join("%s.png" % n));
