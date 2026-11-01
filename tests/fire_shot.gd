# ----------------------------------------------------------------
# Fire shot: a grove burning with charred trees, a campfire, a wooden
# house on fire and a scorched stone house, by day and at dusk.
#     godot --path . res://tests/fire_shot.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

var world:World;
var _out:String = "user://";
var _frame:int = 0;
var _o:Vector2i;
var _anchor:Vector2i;
var _wood:Building;
var _stone:Building;

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
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON + 3) * GameClock.HOURS_PER_DAY + 15.0;
    Weather.reset();
    Weather._update_temperature();
    world.wetness = 0.1;
    var o:Vector2i = TestSite.near(world, Vector2i(10, -14), Vector2i(26, 18));
    for rn in world.nodes.duplicate():
        if Rect2i(o - Vector2i(2, 2), Vector2i(30, 22)).has_point(rn.cell):
            world.remove_node(rn);
    world.terrain.flatten_rect(Rect2i(o - Vector2i(1, 1), Vector2i(28, 20)));
    for dz in 6:
        for dx in 7:
            world.add_node(&"tree" if (dx + dz) % 3 != 0 else &"oak", o + Vector2i(dx, dz));
    _o = o;
    _anchor = TestSite.anchor(world);
    world.camera_rig.focus_on(Vector3(o.x + 9.0, 0, o.y + 4.0));
    world.camera_rig._distance = 22.0;
    world.camera_rig._target_distance = 22.0;
    world.camera_rig._pitch = deg_to_rad(-38.0);
    world.tools.select(null);


# Lit after the clock has caught up with the time set above (each hour it jumps is an hour of burning).
func _light() -> void:
    var o:Vector2i = _o;
    for e in world.fires.cells.keys():
        world.fires.cells.erase(e);
    for dz in 6:
        for dx in 7:
            if world.node_at[world.idx(o + Vector2i(dx, dz))] == null:
                world.add_node(&"tree" if (dx + dz) % 3 != 0 else &"oak", o + Vector2i(dx, dz));
            world.node_at[world.idx(o + Vector2i(dx, dz))].burning = false;
    for k in [4, 10, 16, 17, 23, 24, 30]:
        world.fires.ignite(o + Vector2i(k % 7, k / 7));
    world.fires.light_campfire(o + Vector2i(9, 9));
    for k in 14:
        world.fires.scorch[o + Vector2i(8 + k % 5, 12 + k / 5)] = GameClock.total_hours - 30.0 * k;
    world.fires.changed = true;
    if _wood == null:
        _wood = world.place_building(&"house", TestSite.spot(world, Vector2i(3, 3), o - _anchor + Vector2i(11, 1)), Vector2i(3, 3), true);
        _stone = world.place_building(&"stone_house", TestSite.spot(world, Vector2i(3, 3), o - _anchor + Vector2i(16, 1)), Vector2i(3, 3), true);
        _wood.health = 0.6;
        _wood._update_visual();
        _stone.health = 0.7;
        _stone._update_visual();
    _wood.burning = false;
    world.fires.ignite(_wood.rect().position);

func _process(_delta:float) -> void:
    _frame += 1;
    match _frame:
        30:
            _light();
        45:
            _shot("fire_day");
            for e in world.fires.cells.keys():
                world.fires.cells.erase(e);
            GameClock.total_hours = (GameClock.DAYS_PER_SEASON + 3) * GameClock.HOURS_PER_DAY + 20.5;
        70:
            _light();
        85:
            _shot("fire_dusk");
            get_tree().quit();

func _shot(n:String) -> void:
    get_viewport().get_texture().get_image().save_png(_out.path_join("%s.png" % n));
