# ----------------------------------------------------------------
# Esc menu test
#     Esc with nothing to cancel opens the menu and pauses; Esc again
#     resumes at the old speed; Esc with a tool active cancels the
#     tool instead of opening the menu.
#     godot --headless --path . --fixed-fps 60 res://tests/esc_menu.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    await get_tree().process_frame;
    GameClock.set_speed(2);
    _esc(world);
    _expect("Esc opens the menu", world.hud.menu_open());
    _expect("the game is paused", GameClock.is_paused());
    _esc(world);
    _expect("Esc closes it", not world.hud.menu_open());
    _expect("speed is restored", GameClock.speed_index == 2);
    world.tools.set_mode(PlayerTools.Mode.ROAD);
    _esc(world);
    _expect("Esc cancels a tool first", not world.hud.menu_open() and world.tools.mode == PlayerTools.Mode.SELECT);
    print("ESC MENU %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _esc(world:World) -> void:
    var e:InputEventKey = InputEventKey.new();
    e.keycode = KEY_ESCAPE;
    e.pressed = true;
    world.tools._unhandled_input(e);

func _expect(what:String, ok:bool) -> void:
    print("%s: %s" % ["PASS" if ok else "FAIL", what]);
    if not ok:
        _fails += 1;
