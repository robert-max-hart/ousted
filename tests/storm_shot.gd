# ----------------------------------------------------------------
# Storm shot
#     A thunderstorm over the colony: clear noon, the storm at full, and the flash with its bolt.
#     godot --path . res://tests/storm_shot.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

var world:World;
var _out:String = "user://";
var _frame:int = 0;

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
    GameClock.hour_changed.disconnect(Weather._on_hour);
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON * 1 + 3) * GameClock.HOURS_PER_DAY + 15.0;
    Weather._update_temperature();
    world.tools.select(null);

func _process(_delta:float) -> void:
    _frame += 1;
    match _frame:
        20:
            _shot("storm_clear");
            Weather.is_raining = true;
            Weather.intensity = 1.0;
            Weather.storm = true;
            Weather.storm_level = 1.0;
            Weather._update_temperature();
            world.visuals._on_weather_changed();
            GameClock.set_speed(1);
        100:
            _shot("storm_dark");
            Weather.lightning.emit(1.0);
        103:
            _shot("storm_flash");
            get_tree().quit();

func _shot(n:String) -> void:
    get_viewport().get_texture().get_image().save_png(_out.path_join("%s.png" % n));
