# ----------------------------------------------------------------
# UI flow screenshot
#     With Governance built: the Policies panel open (with the shack
#     clearing rule), a house selected with its Relocate button, then
#     the real Relocate flow driven by mouse events (ghost, hint, click).
#     godot --path . res://tests/ui_flow_shot.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

var world:World;
var house:Building;
var _frame:int = 0;
var _out:String = "user://";
var _spot:Vector2 = Vector2.ZERO;

func _ready() -> void:
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0:
        _out = args[0];
    SaveGame.autosave_enabled = false;
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    GameClock.total_hours = 11.0;
    world.town_hall.upgrades_done[&"governance"] = true;
    house = world.place_building(&"house", TestSite.spot(world, Vector2i(3, 3), Vector2i(-8, 2)), Vector2i(3, 3), true);
    world.tools.select(house);
    world.camera_rig.focus_on(house.position);
    world.camera_rig._distance = 20.0;
    world.camera_rig._target_distance = 20.0;

func _process(_delta:float) -> void:
    _frame += 1;
    if _frame == 5:
        world.hud._policies_btn.button_pressed = true;
    elif _frame == 30:
        _shot("ui_01.png");
        world.hud._move_btn.pressed.emit();
        _expect("the Relocate button starts a relocation", world.tools.relocating == house and world.tools.mode == PlayerTools.Mode.BUILD);
        _spot = get_viewport().get_visible_rect().size * Vector2(0.55, 0.62);
        get_viewport().warp_mouse(_spot);
        var motion:InputEventMouseMotion = InputEventMouseMotion.new();
        motion.position = _spot;
        Input.parse_input_event(motion);
    elif _frame == 60:
        _shot("ui_02.png");
        for pressed in [true, false]:
            var click:InputEventMouseButton = InputEventMouseButton.new();
            click.button_index = MOUSE_BUTTON_LEFT;
            click.pressed = pressed;
            click.position = _spot;
            Input.parse_input_event(click);
    elif _frame == 90:
        _shot("ui_03.png");
        var site:Building = null;
        for b in world.buildings:
            if b != house and b.def_id == &"house":
                site = b;
        _expect("clicking a free spot made a relocation site", site != null and not site.is_complete() and site.relocating_from == house);
        _expect("the tool is back to select", world.tools.mode == PlayerTools.Mode.SELECT);
        get_tree().quit();

func _shot(file:String) -> void:
    get_viewport().get_texture().get_image().save_png(_out.path_join(file));
    print("saved ", file);

func _expect(what:String, ok:bool) -> void:
    print(("PASS " if ok else "FAIL ") + what);
