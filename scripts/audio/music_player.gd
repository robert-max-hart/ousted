# ----------------------------------------------------------------
# MusicPlayer
#     The background music: now and then (not all the time) a piece for
#     the season plays through, then there is a quiet spell of a minute
#     or two while the ambient sound carries on. The pieces are in
#     assets/audio/music (<season>_<n>.ogg, made by tools/make_music.py):
#     the first one starts a little after the game opens, each is picked
#     from the current season's and is never the one just played. It
#     plays on the Music bus, so it follows the Music volume in Settings
#     (0 mutes it, and nothing starts while it is 0). A child of World;
#     the gaps run in real time, whatever the game's speed.
# ----------------------------------------------------------------
class_name MusicPlayer extends Node;

const DIR        :String = "res://assets/audio/music/";
const SEASONS    :Array[String] = ["spring", "summer", "autumn", "winter"];
const FIRST_GAP  :Vector2 = Vector2(15.0, 40.0);        # seconds before the first piece
const GAP        :Vector2 = Vector2(70.0, 170.0);       # quiet seconds between two pieces
const FADE_IN    :float = 2.0;

var world:World;
var gap_left   :float = 0.0;
var current    :String = "";          # id of the piece playing ("spring_1"), or ""
var last       :String = "";
var _player    :AudioStreamPlayer;
var _streams   :Dictionary = {};     # id -> AudioStream
var _rng       :RandomNumberGenerator = RandomNumberGenerator.new();
var _fade      :float = 1.0;

func _init(w:World) -> void:
    world = w;

func _ready() -> void:
    _rng.randomize();
    Sfx.ensure_buses();
    Sfx.apply_volumes();
    _player = AudioStreamPlayer.new();
    _player.bus = Sfx.BUS_MUSIC;
    _player.finished.connect(_on_finished);
    add_child(_player);
    gap_left = _rng.randf_range(FIRST_GAP.x, FIRST_GAP.y);

func _process(delta:float) -> void:
    if _player.playing:
        if _fade < 1.0:
            _fade = minf(1.0, _fade + delta / FADE_IN);
            _player.volume_db = linear_to_db(maxf(_fade, 0.0001));
        return;
    if GameClock.held:
        return;
    gap_left -= delta;
    if gap_left <= 0.0:
        if Settings.volume_music > 0 and start_piece(GameClock.season()):
            return;
        gap_left = _rng.randf_range(GAP.x, GAP.y) * 0.5;      # (a muted music bus: look again soon, and start once it is on)

# The ids of a season's pieces, from the files.
func pieces_for(season:int) -> Array[String]:
    var ids:Array[String] = [];
    var n:int = 1;
    while ResourceLoader.exists("%s%s_%d.ogg" % [DIR, SEASONS[season], n]):
        ids.append("%s_%d" % [SEASONS[season], n]);
        n += 1;
    return ids;

# Starts a piece for the season (not the one played last, if there is another). Returns whether one began.
func start_piece(season:int) -> bool:
    var ids:Array[String] = pieces_for(season);
    if ids.is_empty():
        return false;
    if ids.size() > 1:
        ids.erase(last);
    var id:String = ids[_rng.randi_range(0, ids.size() - 1)];
    if not _streams.has(id):
        _streams[id] = load("%s%s.ogg" % [DIR, id]) as AudioStream;
    if _streams[id] == null:
        return false;
    Sfx.apply_volumes();          # (a stale bus level must not keep a piece silent)
    current = id;
    last = id;
    _fade = 0.0;
    _player.stream = _streams[id];
    _player.volume_db = -80.0;
    _player.play();
    return true;

func _on_finished() -> void:
    current = "";
    gap_left = _rng.randf_range(GAP.x, GAP.y);
