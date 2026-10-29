# ----------------------------------------------------------------
# Changelist screenshot: the title screen with the changelist open.
#     godot --path . res://tests/changelist_shot.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

var _title:TitleScreen;
var _frame:int = 0;
var _out:String = "user://";

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0:
        _out = args[0];
    _title = TitleScreen.new();
    add_child(_title);

func _process(_delta:float) -> void:
    _frame += 1;
    if _frame == 20:
        _title._changes.visible = true;
    if _frame == 40:
        get_viewport().get_texture().get_image().save_png(_out.path_join("changelist.png"));
        get_tree().quit();
