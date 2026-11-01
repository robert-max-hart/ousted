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
    var keep:Array = [Settings.grass, Settings.shadows, Settings.fullscreen, Settings.vsync, Settings.water, Settings.sway, Settings.ground, Settings.snow_edge, Settings.grass_sway];
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
    var wm:ShaderMaterial = world.visuals._water_mat;
    _expect("water starts at full", float(wm.get_shader_parameter("detail")) == 2.0);
    Settings.set_value("water", 0);
    _expect("simple water reaches the shader", float(wm.get_shader_parameter("detail")) == 0.0);
    Settings.set_value("sway", false);
    _expect("sway off is held", not WindSway.enabled);
    world.visuals._update_water(0.1);
    var swaying:bool = false;
    for m in WindSway._materials:
        if not m.get_meta(&"grass", false):
            swaying = swaying or float(m.get_shader_parameter("sway_on")) > 0.5;
    _expect("no tree material sways with tree sway off", not swaying and WindSway.count() > 0);
    Settings.set_value("sway", true);
    Settings.set_value("grass_sway", false);
    world.visuals._update_water(0.1);
    var trees_on:bool = false;
    var grass_on:bool = false;
    for m in WindSway._materials:
        var on:bool = float(m.get_shader_parameter("sway_on")) > 0.5;
        if m.get_meta(&"grass", false):
            grass_on = grass_on or on;
        else:
            trees_on = trees_on or on;
    _expect("grass off leaves trees swaying", trees_on and not grass_on);
    Settings.set_value("grass_sway", true);
    world.visuals._update_water(0.1);
    _expect("sway on again", float(WindSway._materials[0].get_shader_parameter("sway_on")) > 0.5);
    Settings.set_value("ground", false);
    Settings.set_value("snow_edge", false);
    var tm:ShaderMaterial = world.terrain._material;
    _expect("ground and snow switches reach the terrain", float(tm.get_shader_parameter("ground_detail")) == 0.0 and float(tm.get_shader_parameter("snow_detail")) == 0.0);
    var bank:ShaderMaterial = world.visuals.edge_clouds._bank_mat;
    _expect("wispy cloud edges are on by default", float(bank.get_shader_parameter("wispy")) == 1.0);
    Settings.set_value("wispy_clouds", false);
    _expect("the wispy cloud switch reaches the cloud bank", float(bank.get_shader_parameter("wispy")) == 0.0);
    Settings.set_value("wispy_clouds", true);
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
    Settings.set_value("water", keep[4]);
    Settings.set_value("sway", keep[5]);
    Settings.set_value("ground", keep[6]);
    Settings.set_value("snow_edge", keep[7]);
    Settings.set_value("grass_sway", keep[8]);
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
