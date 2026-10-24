# ----------------------------------------------------------------
# Screenshot helper
#     Loads the game, lets it run, saves a few screenshots and quits.
#     godot --path . res://tests/screenshot.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

var world:World;
var _frame:int = 0;
var _out:String = "user://";
var _picks:Dictionary = {};   # building id -> a finished one to select for the inspector shots

func _ready() -> void:
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0:
        _out = args[0];
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(3);
    var th:Building = world.town_hall;
    world.place_building(&"field", th.origin + Vector2i(7, -1), Vector2i(6, 6));
    world.place_building(&"house", th.origin + Vector2i(-5, 0), Vector2i(3, 3));
    for id in [&"mine", &"blacksmith"]:
        var size:Vector2i = Defs.BUILDINGS[id]["size"];
        for dz in range(-14, 14, 2):
            var o:Vector2i = th.origin + Vector2i(-12 if id == &"mine" else -6, dz - (6 if id == &"mine" else 10));
            if world.can_place(id, o, size) == "":
                var b:Building = world.place_building(id, o, size);
                b.complete();
                _picks[id] = b;
                break;
    for x in range(-6, 12):
        world.set_road(th.origin + Vector2i(x, 5), true);

const SHOT_HOURS:Array[float] = [6.2, 12.0, 20.0, 23.5];

@warning_ignore("integer_division")
func _process(_delta:float) -> void:
    _frame += 1;
    Weather.is_raining = false;
    # let things settle, then jump the clock to each hour and capture it
    if _frame < 120:
        return;
    var i:int = (_frame - 120) / 10;
    if i >= SHOT_HOURS.size():
        get_tree().quit();
        return;
    if (_frame - 120) % 10 == 0:
        GameClock.set_speed(0);
        GameClock.total_hours = SHOT_HOURS[i];
        # noon shows the mine's inspector (upgrades), dusk the blacksmith's
        var pick:StringName = &"mine" if i == 1 else &"blacksmith" if i == 2 else &"";
        world.tools.select(_picks.get(pick, null));
        if _picks.has(pick):
            world.camera_rig.focus_on((_picks[pick] as Building).position);
            world.camera_rig._distance = 30.0;
            world.camera_rig._target_distance = 30.0;
    elif (_frame - 120) % 10 == 5:
        _shot("shot_%02d.png" % int(SHOT_HOURS[i]));

func _shot(file:String) -> void:
    var img:Image = get_viewport().get_texture().get_image();
    img.save_png(_out.path_join(file));
    print("saved %s (fps %d)" % [_out.path_join(file), Engine.get_frames_per_second()]);
