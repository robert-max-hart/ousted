# ----------------------------------------------------------------
# Foraging screenshot
#     A Forager's Hut with mushrooms, hazel groves and berry bushes
#     around it (some marked), the hut's inspector, then a mushroom's.
#     godot --path . res://tests/forage_shot.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

var world:World;
var hut:Building;
var shroom:ResourceNode;
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
    hut = world.place_building(&"forager", TestSite.spot(world, Vector2i(3, 3), Vector2i(-4, 8)), Vector2i(3, 3), true);
    var n:int = 0;
    for dz in range(-8, 9, 2):
        for dx in range(-8, 9, 2):
            var c:Vector2i = hut.origin + Vector2i(dx, dz + 6);
            if world.can_plant_tree(c):
                var kind:StringName = [&"mushroom", &"hazel", &"bush"][n % 3];
                var rn:ResourceNode = world.add_node(kind, c);
                if n % 4 == 0:
                    world.set_designated(rn, true);
                if kind == &"mushroom" and shroom == null:
                    shroom = rn;
                n += 1;
    world.tools.select(hut);
    world.camera_rig.focus_on(hut.position + Vector3(0, 0, 5));
    world.camera_rig._distance = 18.0;
    world.camera_rig._target_distance = 18.0;

func _process(_delta:float) -> void:
    _frame += 1;
    if _frame == 40:
        _shot("forage_01.png");
        world.tools.select(shroom);
    elif _frame == 60:
        _shot("forage_02.png");
        world.hud._tool_btns[str(PlayerTools.Mode.FORAGE)].pressed.emit();
    elif _frame == 80:
        _shot("forage_03.png");
        get_tree().quit();

func _shot(file:String) -> void:
    get_viewport().get_texture().get_image().save_png(_out.path_join(file));
    print("saved ", file);
