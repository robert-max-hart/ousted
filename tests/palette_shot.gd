# ----------------------------------------------------------------
# Palette screenshots
#     The same map and view of the start town at several times of day and in
#     autumn, with the environment's grading settable from the command line to
#     compare looks: tonemap mode (0 linear, 1 reinhard, 2 filmic, 3 aces),
#     saturation and contrast (1 = unchanged). Windowed.
#     godot --path . res://tests/palette_shot.tscn -- <out_dir> <label> [tonemap] [saturation] [contrast]
# ----------------------------------------------------------------
extends Node;

# [file name part, total hours]
const SHOTS:Array = [["spring_09", 2 * 24 + 9.0], ["spring_13", 2 * 24 + 13.0], ["spring_1830", 2 * 24 + 18.5], ["night", 2 * 24 + 23.5], ["autumn_13", 19 * 24 + 13.0], ["summer_13", 11 * 24 + 13.0]];

var world:World;
var _out:String = "user://";
var _label:String = "palette";
var _frame:int = 0;
var _grade:Array = [];

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0:
        _out = args[0];
    if args.size() > 1:
        _label = args[1];
    if args.size() > 4:
        _grade = [args[2].to_int(), args[3].to_float(), args[4].to_float()];
    GameClock.reset();
    Weather.reset();
    Weather.drought_enabled = false;
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    world.world_seed = 4242;
    add_child(world);
    GameClock.set_speed(0);
    world.hud.visible = false;
    var th:Building = world.town_hall;
    var spots:Dictionary = {&"house": Vector2i(-6, 4), &"field": Vector2i(6, -4), &"granary": Vector2i(-6, -5), &"school": Vector2i(8, 6), &"blacksmith": Vector2i(-2, 8)};
    for id in spots:
        var size:Vector2i = Defs.BUILDINGS[id]["size"];
        var o:Vector2i = TestSite.spot(world, size, th.origin - TestSite.anchor(world) + spots[id]);
        if world.can_place(id, o, size) == "":
            var b:Building = world.place_building(id, o, size, id != &"field");
            if b != null and id == &"field":
                b.complete();

@warning_ignore("integer_division")
func _process(_delta:float) -> void:
    _frame += 1;
    var rig:Node = world.camera_rig;
    if _frame == 2:
        var th:Vector3 = world.town_hall.position;
        rig.focus_on(Vector3(th.x + 2.0, 0.0, th.z + 2.0));
        rig._distance = 38.0;
        rig._target_distance = 38.0;
        rig._pitch = deg_to_rad(-40.0);
        if _grade.size() == 3:
            var env:Environment = world.visuals._env;
            env.tonemap_mode = _grade[0];
            env.adjustment_enabled = true;
            env.adjustment_saturation = _grade[1];
            env.adjustment_contrast = _grade[2];
    var i:int = (_frame - 6) / 8;
    if _frame >= 6 and (_frame - 6) % 8 == 0 and i < SHOTS.size():
        GameClock.total_hours = SHOTS[i][1];
        Weather.reset();
        world.terrain.set_season(Climate.look(GameClock.season()));
        world.renderer.set_season(Climate.look(GameClock.season()));
        world.visuals.start_snow_cover();
    if _frame >= 10 and (_frame - 10) % 8 == 0 and (_frame - 10) / 8 < SHOTS.size():
        get_viewport().get_texture().get_image().save_png(_out.path_join("%s_%s.png" % [_label, SHOTS[(_frame - 10) / 8][0]]));
    if _frame > 10 + 8 * SHOTS.size():
        get_tree().quit();
