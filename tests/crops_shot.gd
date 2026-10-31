# ----------------------------------------------------------------
# Crops shot
#     A field with one column per crop (wheat, barley, beans, potatoes, radishes, lettuce, cabbage, pumpkins)
#     and one row per stage: seedling, young, grown, ripe, frosted, withered, pest-hit.
#     godot --path . res://tests/crops_shot.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

const CROPS:Array[StringName] = [&"wheat", &"barley", &"beans", &"potato", &"radish", &"lettuce", &"cabbage", &"pumpkin"];

var world:World;
var _out:String = "user://";
var _frame:int = 0;
var _o:Vector2i;
var _field:Field;

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
    world.seeds.unlock_all();
    _o = TestSite.near(world, Vector2i(-22, -24), Vector2i(14, 12));
    for rn in world.nodes.duplicate():
        if Rect2i(_o - Vector2i(3, 3), Vector2i(14, 12)).has_point(rn.cell):
            world.remove_node(rn);
    world.terrain.flatten_rect(Rect2i(_o - Vector2i(2, 2), Vector2i(12, 10)));
    _field = world.place_building(&"field", _o, Vector2i(8, 7), true) as Field;
    for i in _field.plot_count():
        var col:int = i % 8;
        var row:int = i / 8;
        _field.plot_crop[i] = CROPS[col];
        _field.moisture[i] = 0.6;
        match row:
            0:
                _field.plot_state[i] = Field.Plot.PLANTED; _field.growth[i] = 0.12;
            1:
                _field.plot_state[i] = Field.Plot.PLANTED; _field.growth[i] = 0.4;
            2:
                _field.plot_state[i] = Field.Plot.PLANTED; _field.growth[i] = 0.8;
            3:
                _field.plot_state[i] = Field.Plot.RIPE; _field.growth[i] = 1.0;
            4:
                _field.plot_state[i] = Field.Plot.FROZEN; _field.growth[i] = 0.8;
            5:
                _field.plot_state[i] = Field.Plot.DEAD; _field.growth[i] = 0.5;
            _:
                _field.plot_state[i] = Field.Plot.RIPE; _field.growth[i] = 1.0; _field.pests[i] = 0.6;
    _field._visual_dirty = true;
    world.camera_rig.focus_on(Vector3(_o.x + 4.0, 0, _o.y + 3.5));
    world.camera_rig._distance = 11.0;
    world.camera_rig._target_distance = 11.0;
    world.camera_rig._pitch = deg_to_rad(-48.0);
    world.tools.select(null);

func _process(_delta:float) -> void:
    _frame += 1;
    match _frame:
        30:
            _shot("crops_all");
            world.camera_rig.focus_on(Vector3(_o.x + 2.0, 0, _o.y + 4.5));
            world.camera_rig._distance = 5.0;
            world.camera_rig._target_distance = 5.0;
            world.camera_rig._pitch = deg_to_rad(-35.0);
        60:
            _shot("crops_close");
            get_tree().quit();

func _shot(n:String) -> void:
    get_viewport().get_texture().get_image().save_png(_out.path_join("%s.png" % n));
