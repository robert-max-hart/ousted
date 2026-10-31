# ----------------------------------------------------------------
# Scenarios screenshots
#     The title screen's scenario list, then the goals panel in a game.
#     godot --path . res://tests/scenarios_shot.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

var _out:String = "user://";
var _frame:int = 0;
var _title:TitleScreen;
var _world:World;

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
        _title._show_scenarios();
        _title._ui_root.get_children().back()._select(&"wetlands");
    if _frame == 25:
        get_viewport().get_texture().get_image().save_png(_out.path_join("scenario_list.png"));
        _title.queue_free();
    if _frame == 30:
        Scenarios.apply(&"coast", false);
        World.choose_start = false;
        GameClock.reset();
        _world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
        add_child(_world);
    if _frame == 60:
        GameClock.set_speed(0);
        get_viewport().get_texture().get_image().save_png(_out.path_join("scenario_goals.png"));
        print("SCENARIOS SHOT saved");
        get_tree().quit();
