# ----------------------------------------------------------------
# Crop picker screenshot
#     A field selected with its inspector, and the crop menu opened from
#     the "Change crop" button.
#     godot --path . res://tests/crop_menu_shot.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

var world:World;
var field:Field;
var _frame:int = 0;
var _out:String = "user://";

func _ready() -> void:
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0:
        _out = args[0];
    SaveGame.autosave_enabled = false;
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    GameClock.total_hours = 3.0 * GameClock.HOURS_PER_DAY + 11.0;
    field = world.place_building(&"field", world.town_hall.origin + Vector2i(8, 8), Vector2i(6, 6), true) as Field;
    field.set_crop(&"lettuce");
    for i in 14:
        field.plot_state[i] = Field.Plot.PLANTED;
        field.plot_crop[i] = &"lettuce";
        field.growth[i] = 0.5;
    world.tools.select(field);
    world.camera_rig.focus_on(field.position);

func _process(_delta:float) -> void:
    _frame += 1;
    if _frame == 20:
        world.hud._info_btn.pressed.emit();
    elif _frame == 50:
        _shot("crops_01.png");
        (world.hud._crop_list.get_child(3) as Button).pressed.emit();
    elif _frame == 70:
        _shot("crops_02.png");
        _expect("picking from the menu sets the crop", field.crop_id == Defs.CROPS.keys()[3]);
        get_tree().quit();

func _shot(file:String) -> void:
    get_viewport().get_texture().get_image().save_png(_out.path_join(file));
    print("saved ", file);

func _expect(what:String, ok:bool) -> void:
    print(("PASS " if ok else "FAIL ") + what);
