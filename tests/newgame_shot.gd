# ----------------------------------------------------------------
# New Game panel screenshot
#     Opens the New Game panel with the Arctic climate (its warning) and
#     the custom rules unfolded, and saves a picture.
#     godot --path . res://tests/newgame_shot.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

var _out:String = "user://";
var _frame:int = 0;
var _title:TitleScreen;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0:
        _out = args[0];
    _title = TitleScreen.new();
    add_child(_title);

func _process(_delta:float) -> void:
    _frame += 1;
    if _frame == 10:
        _title._show_new_game();
        _title._climate_pick.select(_title._climate_pick.get_item_index(Climate.Id.ARCTIC));
        _title._show_climate_text();
        _title._rules_box.visible = true;
    if _frame == 20:
        get_viewport().get_texture().get_image().save_png(_out.path_join("new_game.png"));
        print("NEW GAME SHOT saved");
        get_tree().quit();
