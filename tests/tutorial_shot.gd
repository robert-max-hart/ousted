# ----------------------------------------------------------------
# Tutorial screenshot
#     The guide panel on the "choose where to settle" step of a tutorial
#     game (two pictures: the welcome step, then that one).
#     godot --path . res://tests/tutorial_shot.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

var _out:String = "user://";
var _frame:int = 0;
var _world:World;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0:
        _out = args[0];
    Defs.difficulty = &"easy";
    GameRules.reset();
    Tutorial.active = true;
    World.choose_start = true;
    _world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(_world);

func _process(_delta:float) -> void:
    _frame += 1;
    if _frame == 15:
        get_viewport().get_texture().get_image().save_png(_out.path_join("tutorial_welcome.png"));
        (_world.hud.get_node("Tutorial") as Tutorial)._go(2);
    if _frame == 30:
        get_viewport().get_texture().get_image().save_png(_out.path_join("tutorial_settle.png"));
        print("TUTORIAL SHOT saved");
        get_tree().quit();
