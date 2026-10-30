# ----------------------------------------------------------------
# M4 screenshots (steps 4 to 8) and this round's UI
#     One scene with a field (soil view, per-plot numbers, pests, a
#     scarecrow), an irrigation channel from the water, an orchard, a
#     chicken run and a cow pasture with their herds, rotated houses
#     and a staked road. Then the soil view, a drought, the crop list
#     with its soil warnings, the ? help, the Accepts filter and the
#     Citizens panel. Pictures: m4_a ... m4_h.
#     godot --path . res://tests/m4_shot.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

var world:World;
var _out:String = "user://";
var _frame:int = 0;
var _o:Vector2i;
var _field:Field;
var _orchard:Field;
var _coop:Pasture;
var _cows:Pasture;
var _store:Building;

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
    Weather._day_offset = 0.0;
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON * 1 + 3) * GameClock.HOURS_PER_DAY + 11.0;      # summer morning
    Weather._update_temperature();
    _o = world.town_hall.origin + Vector2i(-22, -24);
    for rn in world.nodes.duplicate():
        if Rect2i(_o - Vector2i(3, 3), Vector2i(48, 30)).has_point(rn.cell):
            world.remove_node(rn);
    world.terrain.flatten_rect(Rect2i(_o - Vector2i(2, 2), Vector2i(46, 28)));
    # a field, half planted, with pests, a scarecrow and uneven soil
    _field = world.place_building(&"field", _o, Vector2i(8, 8), true) as Field;
    for i in _field.plot_count():
        var c:Vector2i = _field.plot_cell(i);
        world.soil_fertility[world.terrain.index(c)] = 0.25 + 0.7 * float((c.x * 7 + c.y * 3) % 10) / 10.0;
        if i % 4 != 0:
            _field.plot_state[i] = Field.Plot.PLANTED;
            _field.plot_crop[i] = _field.crop_id;
            _field.growth[i] = 0.2 + 0.7 * float(i % 9) / 9.0;
            _field.moisture[i] = 0.6;
    for i in [10, 11, 18, 19, 20]:
        _field.pests[i] = 0.5;
    _field.upgrades_done[&"scarecrow"] = true;
    # an orchard of young and fruiting trees
    _orchard = world.place_building(&"orchard", _o + Vector2i(10, 0), Vector2i(6, 6), true) as Field;
    for i in _orchard.plot_count():
        _orchard.plot_state[i] = Field.Plot.RIPE if i % 3 == 0 else Field.Plot.PLANTED;
        _orchard.plot_crop[i] = &"apple";
        _orchard.growth[i] = 1.0 if i % 3 == 0 else 0.2 + 0.6 * float(i % 5) / 5.0;
        _orchard.moisture[i] = 0.6;
    # a channel from the nearest water, if the map has any near the field
    # animals
    _coop = world.place_building(&"pasture", _o + Vector2i(18, 0), Vector2i(5, 5), true) as Pasture;
    _cows = world.place_building(&"pasture", _o + Vector2i(26, 0), Vector2i(7, 7), true) as Pasture;
    _cows.set_kind(&"cow");
    for p in [_coop, _cows]:
        p.arrived = true;
        p.animals = p.capacity_animals() / 2;
    # rotated houses, a staked road, a stockpile for the inspector
    for i in 4:
        world.place_building(&"house", _o + Vector2i(i * 5, 12), Vector2i(3, 4) if i % 2 == 1 else Vector2i(4, 3), true, false, i);
    for x in 12:
        world.set_road(_o + Vector2i(x, 18), true);
        world.stake_road(_o + Vector2i(x, 20));
    _store = world.place_building(&"stockpile", _o + Vector2i(22, 12), Vector2i(4, 4), true);
    _store.set_forbidden(&"berries", true);
    _store.set_forbidden(&"wheat", true);
    world.camera_rig.focus_on(Vector3(_o.x + 14, 0, _o.y + 8));
    world.camera_rig._distance = 38.0;
    world.camera_rig._target_distance = 38.0;
    Engine.time_scale = 1.0;

func _process(_delta:float) -> void:
    _frame += 1;
    match _frame:
        40:
            _shot("m4_a");                      # overview
        60:
            world.camera_rig.focus_on(Vector3(_o.x + 4, 0, _o.y + 4));
            world.camera_rig._distance = 14.0;
            world.camera_rig._target_distance = 14.0;
        100:
            _shot("m4_b");                      # field close: pests, scarecrow
            world.hud._soil_toggle.button_pressed = true;
            world.tools.select(_field);
        140:
            _shot("m4_c");                      # soil view with numbers and the inspector
            world.hud._on_info_button();
        170:
            _shot("m4_d");                      # the crop list with soil warnings
            world.hud._crop_list.visible = false;
            world.hud._soil_toggle.button_pressed = false;
            world.hud._help_btn.button_pressed = true;
            world.camera_rig.focus_on(Vector3(_o.x + 22, 0, _o.y + 3));
            world.camera_rig._distance = 16.0;
            world.camera_rig._target_distance = 16.0;
            world.tools.select(_cows);
        220:
            _shot("m4_e");                      # herds, orchard, the ? text open
            world.tools.select(_store);
            world.hud._filter_flow.visible = true;
            world.hud._update_filter_head(_store);
        260:
            _shot("m4_f");                      # the Accepts filter open
            world.hud._help_btn.button_pressed = false;
            world.hud._citizens_toggle.button_pressed = true;
            world.hud._citizens._sort_by(4);       # sorted by happiness
        300:
            _shot("m4_g");                      # the Citizens panel
            Weather.drought_days = 6;
            Weather._update_temperature();
            world.camera_rig.focus_on(Vector3(_o.x + 4, 0, _o.y + 14));
            world.camera_rig._distance = 18.0;
            world.camera_rig._target_distance = 18.0;
            world.tools.select(null);
        340:
            _shot("m4_h");                      # drought in the top bar, rotated houses, staked road
            get_tree().quit();

func _shot(n:String) -> void:
    get_viewport().get_texture().get_image().save_png(_out.path_join("%s.png" % n));
