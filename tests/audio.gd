# ----------------------------------------------------------------
# Audio test
#     Every sound id the game uses has a file, the buses exist and follow
#     the volume settings, the ambient loops follow the weather and the
#     time of day, and a citizen's strike picks the sound of their work.
#     godot --headless --path . --fixed-fps 60 res://tests/audio.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Weather.drought_enabled = false;
    Settings.ensure_loaded();
    var keep:Array = [Settings.volume_master, Settings.volume_sfx, Settings.volume_ambient];
    for id in [&"chop", &"hammer", &"pick", &"dig", &"rustle", &"anvil", &"click", &"place", &"error", &"demolish", &"done", &"birth", &"death", &"merchant", &"season", &"treefall"]:
        _expect("a sound file for %s" % id, Sfx.has(id));
    for id in [&"wind", &"rain", &"water", &"birds", &"crickets"]:
        _expect("an ambient loop for %s" % id, ResourceLoader.exists("res://assets/audio/ambient/%s.wav" % id));
    Settings.set_value("volume_master", 50);
    Settings.set_value("volume_sfx", 0);
    var sfx_bus:int = AudioServer.get_bus_index(Sfx.BUS_SFX);
    _expect("the Sfx bus exists", sfx_bus != -1);
    _expect("master volume reaches the Master bus", absf(AudioServer.get_bus_volume_db(0) - linear_to_db(0.5)) < 0.01);
    _expect("volume 0 mutes a bus", AudioServer.is_bus_mute(sfx_bus));
    _expect("a muted effects volume plays nothing", not Sfx.ui(&"click"));
    Settings.set_value("volume_sfx", 80);
    _expect("and not muted again", not AudioServer.is_bus_mute(sfx_bus));

    Defs.difficulty = &"easy";
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    await get_tree().process_frame;
    var amb:AmbientAudio = world.get_node("Ambient") as AmbientAudio;
    _expect("the world has ambient audio", amb != null);
    # clear noon in summer: birds, no crickets, no rain
    Weather.intensity = 0.0;
    Weather.temperature = 20.0;
    Weather._dry_temperature = 20.0;
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON * 1 + 3) * GameClock.HOURS_PER_DAY + 12.0;
    amb._update_targets();
    _expect("birds sing by day in summer", amb.targets[&"birds"] > 0.5 and amb.targets[&"crickets"] == 0.0 and amb.targets[&"rain"] == 0.0);
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON * 1 + 3) * GameClock.HOURS_PER_DAY + 23.0;
    amb._update_targets();
    _expect("crickets at night, no birds", amb.targets[&"crickets"] > 0.5 and amb.targets[&"birds"] == 0.0);
    Weather.intensity = 1.0;
    Weather.temperature = 14.0;
    Weather._dry_temperature = 16.0;
    Weather.is_raining = true;
    amb._update_targets();
    _expect("rain is heard, and the birds and crickets stop", amb.targets[&"rain"] > 0.9 and amb.targets[&"birds"] == 0.0 and amb.targets[&"crickets"] == 0.0);
    _expect("the wind rises in rain", amb.targets[&"wind"] > 0.5);
    for i in 200:
        amb._process(0.1);
    _expect("the rain loop fades up to its level", amb.levels[&"rain"] > 0.9 and (amb._players[&"rain"] as AudioStreamPlayer).playing);
    _expect("a silent loop is stopped", not (amb._players[&"birds"] as AudioStreamPlayer).playing);

    # what a citizen's swing sounds like
    var p:Pawn = world.pawns[0];
    var t:Task = Task.new(&"work", "testing");
    p.task = t;
    for pair in [[JobManager.Profession.BUILDER, &"hammer"], [JobManager.Profession.FARMER, &"dig"], [JobManager.Profession.MINER, &"pick"], [JobManager.Profession.BLACKSMITH, &"anvil"]]:
        t.job = pair[0];
        _expect("a %s strike sounds like %s" % [JobManager.PROFESSION_NAMES[pair[0]], pair[1]], p._work_sound() == pair[1]);
    t.job = JobManager.Profession.LABORER;
    for rn in world.nodes:
        if rn.is_tree():
            t.target = rn;
            _expect("a laborer at a tree chops", p._work_sound() == &"chop");
            break;
    for rn in world.nodes:
        if not rn.is_tree() and not rn.is_forageable():
            t.target = rn;
            _expect("and at a rock picks", p._work_sound() == &"pick");
            break;
    p.task = null;

    Settings.set_value("volume_master", keep[0]);
    Settings.set_value("volume_sfx", keep[1]);
    Settings.set_value("volume_ambient", keep[2]);
    print("AUDIO %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    if ok:
        print("PASS: ", what);
    else:
        _fails += 1;
        print("FAIL: ", what);
