# ----------------------------------------------------------------
# Weather (autoload)
#     Seasonal temperature curve plus daily variation, and rain/snow.
# ----------------------------------------------------------------
extends Node;

signal weather_changed;

# Mid-season mean temperatures (C): spring, summer, autumn, winter
const SEASON_TEMP       :Array[float] = [11.0, 21.0, 9.0, -5.0];
const DAILY_SWING       :float = 4.0;
const RAIN_START_CHANCE :Array[float] = [0.06, 0.03, 0.06, 0.05];   # per hour
const RAIN_STOP_CHANCE  :float = 0.12;                                # per hour
const RAIN_COOLING      :float = 2.0;

var temperature     :float = 10.0;
var is_raining      :bool = false;
var _day_offset     :float = 0.0;
var _rng            :RandomNumberGenerator = RandomNumberGenerator.new();

func _ready() -> void:
    _rng.randomize();
    GameClock.hour_changed.connect(_on_hour);
    GameClock.day_changed.connect(_on_day);
    _roll_day();
    _update_temperature();

func _on_day(_day:int) -> void:
    _roll_day();

func _roll_day() -> void:
    _day_offset = _rng.randf_range(-4.0, 4.0);

func _on_hour(_hour:int) -> void:
    var s:int = GameClock.season();
    if is_raining:
        if _rng.randf() < RAIN_STOP_CHANCE:
            is_raining = false;
    elif _rng.randf() < RAIN_START_CHANCE[s]:
        is_raining = true;
    _update_temperature();
    weather_changed.emit();

# Mean temperature for the current day (no daily swing / rain).
func mean_temperature() -> float:
    # SEASON_TEMP values sit at the middle of each season; blend between them
    var sf:float = GameClock.year_fraction_seasons() - 0.5;
    var i:int = floori(sf);
    var t:float = sf - i;
    var a:float = SEASON_TEMP[posmod(i, 4)];
    var b:float = SEASON_TEMP[posmod(i + 1, 4)];
    return lerpf(a, b, t) + _day_offset;

func _update_temperature() -> void:
    var h:float = GameClock.hour();
    # coldest around 04:00, warmest around 16:00
    var daily:float = -cos((h - 4.0) / 24.0 * TAU) * DAILY_SWING;
    temperature = mean_temperature() + daily - (RAIN_COOLING if is_raining else 0.0);

func is_snowing() -> bool:
    return is_raining and temperature < 0.0;

func description() -> String:
    if is_snowing():
        return "Snow";
    if is_raining:
        return "Rain";
    return "Clear";
