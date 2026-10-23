# ----------------------------------------------------------------
# GameClock (autoload)
#     Tracks in-game time, the calendar and simulation speed.
#     Everything simulated should scale by game_hours()/scaled().
# ----------------------------------------------------------------
extends Node;

signal hour_changed(hour:int);
signal day_changed(day:int);
signal season_changed(season:int);
signal speed_changed(speed_index:int);

enum Season { SPRING, SUMMER, AUTUMN, WINTER };

const SEASON_NAMES      :Array[String] = ["Spring", "Summer", "Autumn", "Winter"];
const SECONDS_PER_HOUR  :float = 5.0;   # real seconds per game hour at 1x
const HOURS_PER_DAY     :int = 24;
const DAYS_PER_SEASON   :int = 8;
const DAYS_PER_YEAR     :int = DAYS_PER_SEASON * 4;
const SPEEDS            :Array[float] = [0.0, 1.0, 2.0, 5.0];
const START_HOUR        :float = 7.0;
const DAWN_HOUR         :float = 6.0;
const DUSK_HOUR         :float = 21.0;

var total_hours :float = START_HOUR;
var speed_index :int = 1;
var _last_hour  :int = int(START_HOUR);
var _resume_speed:int = 1;

func _process(delta:float) -> void:
    total_hours += game_hours(delta);
    var whole:int = int(total_hours);
    while _last_hour < whole:
        _last_hour += 1;
        _emit_hour(_last_hour);

@warning_ignore("integer_division")
func _emit_hour(abs_hour:int) -> void:
    var h:int = abs_hour % HOURS_PER_DAY;
    hour_changed.emit(h);
    if h == 0:
        var d:int = abs_hour / HOURS_PER_DAY;
        day_changed.emit(d);
        if d % DAYS_PER_SEASON == 0:
            season_changed.emit(season());

# --------------------------------
# Time scaling

# Game hours elapsed for a frame of real_delta seconds.
func game_hours(real_delta:float) -> float:
    return real_delta * SPEEDS[speed_index] / SECONDS_PER_HOUR;

func speed() -> float:
    return SPEEDS[speed_index];

func set_speed(index:int) -> void:
    speed_index = clampi(index, 0, SPEEDS.size() - 1);
    if speed_index > 0:
        _resume_speed = speed_index;
    speed_changed.emit(speed_index);

func toggle_pause() -> void:
    set_speed(_resume_speed if is_paused() else 0);

func is_paused() -> bool:
    return speed_index == 0;

# --------------------------------
# Calendar

func hour() -> float:
    return fmod(total_hours, HOURS_PER_DAY);

func day_index() -> int:
    return int(total_hours / HOURS_PER_DAY);

func day_of_season() -> int:
    return day_index() % DAYS_PER_SEASON + 1;

@warning_ignore("integer_division")
func season() -> int:
    return (day_index() / DAYS_PER_SEASON) % 4;

@warning_ignore("integer_division")
func year() -> int:
    return day_index() / DAYS_PER_YEAR + 1;

# Continuous position in the year, 0.0 .. 4.0 (in seasons).
func year_fraction_seasons() -> float:
    return fmod(total_hours / (HOURS_PER_DAY * DAYS_PER_SEASON), 4.0);

func is_night() -> bool:
    var h:float = hour();
    return h < DAWN_HOUR or h >= DUSK_HOUR;

func season_name() -> String:
    return SEASON_NAMES[season()];

func time_string() -> String:
    var h:float = hour();
    return "%02d:%02d" % [int(h), int(fmod(h, 1.0) * 60.0)];

func date_string() -> String:
    return "%s %d, Year %d" % [season_name(), day_of_season(), year()];
