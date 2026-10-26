# ----------------------------------------------------------------
# Chimney smoke test
#     Two houses in the cold, one on firewood and one on coal: checks
#     the smoke runs only while burning and takes the fuel's colour,
#     and saves a screenshot.
#     godot --path . res://tests/smoke_shot.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

var world:World;
var _out:String = "user://";
var _frame:int = 0;
var _wood:Building;
var _coal:Building;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0:
        _out = args[0];
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    Weather._day_offset = 0.0;
    Weather.temperature = 2.0;
    var o:Vector2i = world.town_hall.origin;
    _wood = world.place_building(&"house", o + Vector2i(8, -2), Vector2i(3, 3), true);
    _coal = world.place_building(&"house", o + Vector2i(8, 3), Vector2i(3, 3), true);
    for b in [_wood, _coal]:
        b.settings["heating"] = true;
        b.residents.append(world.pawns[0]);
    _wood.add_fuel(&"firewood", 10);
    _coal.add_fuel(&"coal", 10);
    world.camera_rig.focus_on(_wood.position + Vector3(0, 2, 3));

func _process(_delta:float) -> void:
    _frame += 1;
    if _frame == 5:
        _wood.update_smoke();
        _coal.update_smoke();
        _expect("both houses smoke when cold", _wood._smoke.emitting and _coal._smoke.emitting);
        _expect("firewood smoke is grey", (_wood._smoke.mesh.material as StandardMaterial3D).albedo_color.r > 0.4);
        _expect("coal smoke is black", (_coal._smoke.mesh.material as StandardMaterial3D).albedo_color.r < 0.2);
    elif _frame == 150:
        get_viewport().get_texture().get_image().save_png(_out.path_join("smoke.png"));
        Weather.temperature = 20.0;
        _wood.update_smoke();
        _expect("no smoke when warm", not _wood._smoke.emitting);
        _wood.fuel = 0;
        Weather.temperature = 2.0;
        _wood.update_smoke();
        _expect("no smoke with no fuel", not _wood._smoke.emitting);
        get_tree().quit();

func _expect(what:String, ok:bool) -> void:
    print(("PASS " if ok else "FAIL ") + what);
