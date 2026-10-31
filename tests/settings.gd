# ----------------------------------------------------------------
# Settings test
#     The grass setting scales the tufts and reloads them, shadows switch
#     both lights, and the choices survive a reload from the file.
#     godot --headless --path . --fixed-fps 60 res://tests/settings.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Settings.ensure_loaded();
    var keep:Array = [Settings.grass, Settings.shadows, Settings.fullscreen, Settings.vsync];
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    await get_tree().create_timer(1.0).timeout;
    var grass:GrassDetail = null;
    for c in world.get_children():
        if c is GrassDetail:
            grass = c;
    _expect("the world has grass", grass != null);
    var normal:int = _tufts(grass);
    Settings.set_value("grass", 3);
    await get_tree().create_timer(1.5).timeout;
    var dense:int = _tufts(grass);
    Settings.set_value("grass", 0);
    await get_tree().create_timer(1.5).timeout;
    var none:int = _tufts(grass);
    print("tufts: normal %d, dense %d, off %d" % [normal, dense, none]);
    _expect("normal grass has tufts", normal > 0);
    _expect("dense has more than normal", dense > normal);
    _expect("off has none", none == 0);
    Settings.set_value("shadows", false);
    _expect("shadows off reach the sun", not world.visuals._sun.shadow_enabled and not world.visuals._moon.shadow_enabled);
    Settings.set_value("shadows", true);
    _expect("shadows on again", world.visuals._sun.shadow_enabled);
    Settings.set_value("grass", 1);
    Settings.set_value("vsync", false);
    Settings._loaded = false;
    Settings.grass = 2;
    Settings.vsync = true;
    Settings.ensure_loaded();
    _expect("choices are read back from the file", Settings.grass == 1 and not Settings.vsync);
    var panel:SettingsPanel = SettingsPanel.new();
    world.hud.add_child(panel);
    panel.queue_free();
    Settings.set_value("grass", keep[0]);
    Settings.set_value("shadows", keep[1]);
    Settings.set_value("fullscreen", keep[2]);
    Settings.set_value("vsync", keep[3]);
    print("SETTINGS %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _tufts(grass:GrassDetail) -> int:
    var n:int = 0;
    for v in grass._spots.values():
        n += (v as PackedVector3Array).size();
    return n;

func _expect(what:String, ok:bool) -> void:
    print("%s: %s" % ["PASS" if ok else "FAIL", what]);
    if not ok:
        _fails += 1;
