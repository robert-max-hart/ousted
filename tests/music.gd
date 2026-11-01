# ----------------------------------------------------------------
# Music
#     Each season has pieces; the player starts the first one after a
#     short wait, only plays for the season it is in, never repeats
#     the piece just played, rests between pieces, stays silent at
#     music volume 0, and has a slider in the settings screen.
#     godot --headless --path . --fixed-fps 60 res://tests/music.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Weather.drought_enabled = false;
    Settings.ensure_loaded();
    var keep:int = Settings.volume_music;
    Defs.difficulty = &"easy";
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    await get_tree().process_frame;
    var music:MusicPlayer = world.get_node_or_null("Music") as MusicPlayer;
    _expect("the world has a music player", music != null);
    if music == null:
        get_tree().quit(1);
        return;
    for season in 4:
        var ids:Array[String] = music.pieces_for(season);
        _expect("%s has at least two pieces (%s)" % [MusicPlayer.SEASONS[season], ids], ids.size() >= 2);
        for id in ids:
            _expect("%s loads as a stream of a useful length" % id, (load("%s%s.ogg" % [MusicPlayer.DIR, id]) as AudioStream).get_length() > 25.0);
    _expect("it waits before the first piece (%.0f s)" % music.gap_left, music.gap_left >= MusicPlayer.FIRST_GAP.x and music.gap_left <= MusicPlayer.FIRST_GAP.y and music.current == "");
    # a piece for the season, and not the same one twice running
    Settings.set_value("volume_music", 60);
    for season in 4:
        for round in 6:
            music._player.stop();
            var before:String = music.last;
            _expect("a piece starts in %s" % MusicPlayer.SEASONS[season], music.start_piece(season));
            _expect("it is a %s piece (%s)" % [MusicPlayer.SEASONS[season], music.current], music.current.begins_with(MusicPlayer.SEASONS[season]));
            if before.begins_with(MusicPlayer.SEASONS[season]):
                _expect("and not the one just played (%s then %s)" % [before, music.current], music.current != before);
    # the gap runs down and a piece starts; at the end there is a rest
    music._player.stop();
    music.current = "";
    music.gap_left = 0.5;
    Settings.set_value("volume_music", 0);
    music._process(1.0);
    _expect("nothing starts at music volume 0", not music._player.playing);
    _expect("and it looks again soon", music.gap_left > 0.0);
    Settings.set_value("volume_music", 60);
    music.gap_left = 0.5;
    GameClock.held = true;
    music._process(1.0);
    _expect("nothing starts while the loading screen holds the game", not music._player.playing);
    GameClock.held = false;
    music._process(1.0);
    _expect("a piece starts when the gap has run out (%s)" % music.current, music._player.playing and music.current != "");
    music._on_finished();
    _expect("it rests afterwards (%.0f s)" % music.gap_left, music.current == "" and music.gap_left >= MusicPlayer.GAP.x and music.gap_left <= MusicPlayer.GAP.y);
    music._player.stop();
    # the settings screen has the slider
    var panel:SettingsPanel = SettingsPanel.new();
    add_child(panel);
    var found:bool = false;
    for n in panel.find_children("*", "Label", true, false):
        found = found or (n as Label).text == "Music volume";
    _expect("the settings screen has a Music volume slider", found);
    Settings.set_value("volume_music", keep);
    print("MUSIC %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
