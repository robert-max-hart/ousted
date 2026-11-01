# ----------------------------------------------------------------
# Ground plants shot
#     Flowers, ferns and reeds up close, found on the map by where each kind is thickest: a meadow in spring and
#     summer and autumn, a fern floor, a reedy shore, and the shore in winter.
#     godot --path . res://tests/ground_shot.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

var world:World;
var gp:GroundPlants;
var _out:String = "user://";
var _frame:int = 0;
var _spots:Dictionary = {};

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0:
        _out = args[0];
    Defs.difficulty = &"easy";
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON * 0 + 12) * GameClock.HOURS_PER_DAY + 11.0;
    Weather.drought_enabled = false;
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    for c in world.get_children():
        if c is GroundPlants:
            gp = c;

# The cell whose 7x7 neighbourhood holds most of a kind.
func _densest(kind:StringName) -> Vector2i:
    var best:Vector2i = Vector2i(Terrain.SIZE / 2, Terrain.SIZE / 2);
    var most:int = -1;
    for z in range(4, Terrain.SIZE - 4, 3):
        for x in range(4, Terrain.SIZE - 4, 3):
            var n:int = 0;
            for dz in range(-3, 4):
                for dx in range(-3, 4):
                    n += gp.count_in_cell(kind, Vector2i(x + dx, z + dz));
            if n > most:
                most = n;
                best = Vector2i(x, z);
    return best;

func _look(c:Vector2i, dist:float) -> void:
    world.camera_rig.focus_on(Vector3(c.x + 0.5, world.terrain.height_at(c.x + 0.5, c.y + 0.5), c.y + 0.5));
    world.camera_rig._distance = dist;
    world.camera_rig._target_distance = dist;
    world.camera_rig._pitch = deg_to_rad(-28.0);

func _process(_delta:float) -> void:
    _frame += 1;
    match _frame:
        60:
            for k in [&"flower_a", &"fern", &"reed"]:
                _spots[k] = _densest(k);
            _look(_spots[&"flower_a"], 8.0);
        90:
            _shot("flowers_spring");
            _look(_spots[&"fern"], 8.0);
        120:
            _shot("ferns");
            _look(_spots[&"reed"], 9.0);
        150:
            _shot("reeds");
            _look(_spots[&"flower_a"], 16.0);
        180:
            _shot("meadow_wide");
            GameClock.total_hours = (GameClock.DAYS_PER_SEASON * 1 + 12) * GameClock.HOURS_PER_DAY + 11.0;
            Weather._update_temperature();
            GameClock.season_changed.emit(GameClock.season());
            _look(_spots[&"flower_a"], 8.0);
        240:
            _shot("flowers_summer");
            GameClock.total_hours = (GameClock.DAYS_PER_SEASON * 2 + 12) * GameClock.HOURS_PER_DAY + 11.0;
            Weather._update_temperature();
            GameClock.season_changed.emit(GameClock.season());
            _look(_spots[&"fern"], 8.0);
        300:
            _shot("ferns_autumn");
            _look(_spots[&"reed"], 9.0);
        330:
            _shot("reeds_autumn");
            GameClock.total_hours = (GameClock.DAYS_PER_SEASON * 3 + 12) * GameClock.HOURS_PER_DAY + 11.0;
            Weather._update_temperature();
            GameClock.season_changed.emit(GameClock.season());
        390:
            _shot("reeds_winter");
            get_tree().quit();

func _shot(n:String) -> void:
    get_viewport().get_texture().get_image().save_png(_out.path_join("%s.png" % n));
