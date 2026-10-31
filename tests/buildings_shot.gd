# ----------------------------------------------------------------
# Buildings shot
#     The buildings that have models, finished and in a row (a house with its windows lit), a second row
#     turned a quarter, and a house half built; from the front, from the side and at dusk.
#     godot --path . res://tests/buildings_shot.tscn -- <out_dir> [building ids to show]
# ----------------------------------------------------------------
extends Node;

const IDS:Array[StringName] = [&"town_hall", &"granary", &"well", &"house", &"shack", &"forager", &"woodcutter", &"blacksmith", &"school", &"tailor", &"still", &"pottery", &"apiary"];

var world:World;
var _out:String = "user://";
var _frame:int = 0;
var _o:Vector2i;
var _ids:Array[StringName] = IDS.duplicate();

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Weather.drought_enabled = false;
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0:
        _out = args[0];
    if args.size() > 1:
        _ids = [];
        for a in args.slice(1):
            _ids.append(StringName(a));
    Defs.difficulty = &"easy";
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON * 1 + 3) * GameClock.HOURS_PER_DAY + 12.0;
    Weather._update_temperature();
    _o = TestSite.near(world, Vector2i(-24, -24), Vector2i(36, 18));
    for rn in world.nodes.duplicate():
        if Rect2i(_o - Vector2i(3, 3), Vector2i(36, 18)).has_point(rn.cell):
            world.remove_node(rn);
    world.terrain.flatten_rect(Rect2i(_o - Vector2i(2, 2), Vector2i(34, 16)));
    var x:int = 0;
    for id in _ids:
        var s:Vector2i = Defs.BUILDINGS[id]["size"];
        var b:Building = world.place_building(id, _o + Vector2i(x, 0), s, true);
        if b != null:
            b.windows_lit_always = id == &"house";
            b.update_windows();
        x += s.x + 2;
    x = 0;
    for id in _ids:
        var s:Vector2i = Defs.BUILDINGS[id]["size"];
        var turned:Vector2i = Vector2i(s.y, s.x);
        world.place_building(id, _o + Vector2i(x, 8), turned, true, false, 1);
        x += turned.x + 2;
    var site:Building = world.place_building(&"house", _o + Vector2i(x + 1, 0), Vector2i(3, 3));
    if site != null:
        site.work_done = site.work_required() * 0.55;
        site._update_visual();
    world.renderer.mark_dirty();
    world.camera_rig.focus_on(Vector3(_o.x + 14.0, 0, _o.y + 5.0));
    world.camera_rig._distance = 30.0;
    world.camera_rig._target_distance = 30.0;
    world.camera_rig._pitch = deg_to_rad(-34.0);
    world.tools.select(null);

func _process(_delta:float) -> void:
    _frame += 1;
    match _frame:
        40:
            _shot("buildings_front");
            world.camera_rig._yaw += deg_to_rad(55.0);
        70:
            _shot("buildings_side");
            world.camera_rig._yaw -= deg_to_rad(55.0);
            world.camera_rig.focus_on(Vector3(_o.x + 4.0, 0, _o.y + 2.5) if _ids.size() > 1 else Vector3(_o.x + 1.0, 1.5, _o.y + 1.2));
            world.camera_rig._distance = 11.0 if _ids.size() > 1 else 5.5;
            world.camera_rig._target_distance = world.camera_rig._distance;
            world.camera_rig._pitch = deg_to_rad(-26.0);
        100:
            _shot("buildings_close");
            GameClock.total_hours = (GameClock.DAYS_PER_SEASON * 1 + 3) * GameClock.HOURS_PER_DAY + 19.5;
        140:
            _shot("buildings_dusk");
            get_tree().quit();

func _shot(n:String) -> void:
    get_viewport().get_texture().get_image().save_png(_out.path_join("%s.png" % n));
