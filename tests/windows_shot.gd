# ----------------------------------------------------------------
# Save, load and settings windows screenshots
#     A game with two temporary saves: the save window (after pressing
#     Save on a name that exists, so the overwrite question shows), the
#     load window, and the settings window. The temporary saves are
#     deleted at the end.
#     godot --path . res://tests/windows_shot.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

const SLOTS:Array[String] = ["Before the winter", "Second field"];
var _out:String = "user://";
var _frame:int = 0;
var _world:World;
var _panel:Control;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0:
        _out = args[0];
    Defs.difficulty = &"easy";
    _world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(_world);

func _shot(name:String) -> void:
    get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"));

func _process(_delta:float) -> void:
    _frame += 1;
    if _frame == 5:
        GameClock.set_speed(0);
        for s in SLOTS:
            SaveGame.write(_world, s);
        _world.hud.toggle_menu();
        HudBuild._open_save_panel(_world.hud, true);
        _panel = _world.hud._menu.get_children().back();
        _panel._name.text = SLOTS[0];
        _panel._on_action();       # the name exists: the overwrite question
    if _frame == 20:
        _shot("window_save");
        _panel.close();
        HudBuild._open_save_panel(_world.hud, false);
        _panel = _world.hud._menu.get_children().back();
        _panel._select(SLOTS[1]);
    if _frame == 35:
        _shot("window_load");
        _panel.close();
        _world.hud._menu.add_child(SettingsPanel.new());
    if _frame == 50:
        _shot("window_settings");
        for s in SLOTS:
            SaveGame.delete(s);
        print("WINDOWS SHOT saved");
        get_tree().quit();
