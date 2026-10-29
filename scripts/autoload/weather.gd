# ----------------------------------------------------------------
# Weather (autoload)
#     Seasonal temperature curve plus daily variation, and rain/snow.
# ----------------------------------------------------------------
extends Node;

signal weather_changed;
signal drought_changed(on:bool);       # a dry spell began or ended (the world tells the player)

# Mid-season mean temperatures (C): spring, summer, autumn, winter
const SEASON_TEMP       :Array[float] = [11.0, 21.0, 9.0, -5.0];
const DAILY_SWING       :float = 4.0;
const RAIN_START_CHANCE :Array[float] = [0.06, 0.03, 0.06, 0.05];   # per hour
const RAIN_STOP_CHANCE  :float = 0.12;                                # per hour
const RAIN_COOLING      :float = 2.0;
const DROUGHT_CHANCE    :Array[float] = [0.02, 0.05, 0.02, 0.0];     # per day, by season: none in winter
const DROUGHT_DAYS      :Vector2i = Vector2i(5, 11);                 # how long one lasts
const DROUGHT_REST       :int = 10;                                   # days after one ends before another can start
const DROUGHT_WARMING   :float = 3.0;                                # C hotter than the season while it lasts
const DROUGHT_DRYING    :float = 2.5;                                # how much faster soil and ground dry
const RAMP_IN_HOURS     :float = 1.5;                         # game hours for rain/snow to build to full
const RAMP_OUT_HOURS    :float = 2.5;                         # ... and to clear away again
const SNOW_BELOW        :float = 0.0;                         # C: all precipitation is snow
const RAIN_ABOVE        :float = 3.0;                         # C: all precipitation is rain

var temperature     :float = 10.0;
var is_raining      :bool = false;      # a precipitation spell is active (the target state)
var intensity       :float = 0.0;       # 0..1, eases toward the spell; use this for anything visible
var _dry_temperature:float = 10.0;
var _day_offset     :float = 0.0;
var drought_days    :int = 0;           # days left of a dry spell: no rain, hotter, everything dries faster
var drought_rest    :int = 0;           # days left before another drought may start
var drought_enabled :bool = true;       # tests that need steady weather switch it off
var _rng            :RandomNumberGenerator = RandomNumberGenerator.new();

func _ready() -> void:
    _rng.randomize();
    GameClock.hour_changed.connect(_on_hour);
    GameClock.day_changed.connect(_on_day);
    _roll_day();
    _update_temperature();

func _process(delta:float) -> void:
    var target:float = 1.0 if is_raining else 0.0;
    if is_equal_approx(intensity, target):
        return;
    var hours:float = RAMP_IN_HOURS if is_raining else RAMP_OUT_HOURS;
    intensity = move_toward(intensity, target, GameClock.game_hours(delta) / hours);
    _update_temperature();

func _on_day(_day:int) -> void:
    _roll_day();
    if drought_days > 0:
        drought_days -= 1;
        if drought_days == 0:
            drought_rest = DROUGHT_REST;
            drought_changed.emit(false);
    elif drought_rest > 0:
        drought_rest -= 1;
    elif drought_enabled and _rng.randf() < DROUGHT_CHANCE[GameClock.season()]:
        drought_days = _rng.randi_range(DROUGHT_DAYS.x, DROUGHT_DAYS.y);
        is_raining = false;
        drought_changed.emit(true);

func _roll_day() -> void:
    _day_offset = _rng.randf_range(-4.0, 4.0);

func _on_hour(_hour:int) -> void:
    var s:int = GameClock.season();
    if is_raining:
        if drought_days > 0 or _rng.randf() < RAIN_STOP_CHANCE:
            is_raining = false;
    elif drought_days == 0 and _rng.randf() < RAIN_START_CHANCE[s]:
        is_raining = true;
    _update_temperature();
    weather_changed.emit();

# A new game starts with clear weather (or, for the title screen, a given strength of rain or snow).
func reset(precipitation:float = 0.0) -> void:
    drought_days = 0;
    drought_rest = 0;
    is_raining = precipitation > 0.0;
    intensity = precipitation;
    _roll_day();
    _update_temperature();
    weather_changed.emit();

func save_state() -> Dictionary:
    return {"is_raining": is_raining, "intensity": intensity, "day_offset": _day_offset, "drought_days": drought_days};

func restore_state(d:Dictionary) -> void:
    is_raining = d["is_raining"];
    intensity = d["intensity"];
    _day_offset = d["day_offset"];
    drought_days = d.get("drought_days", 0);
    _update_temperature();

# The climate's mean temperature this many hours from now (no daily swing, rain or today's random offset).
func climate_at(hours_ahead:float) -> float:
    var sf:float = fmod((GameClock.total_hours + hours_ahead) / (GameClock.HOURS_PER_DAY * GameClock.DAYS_PER_SEASON), 4.0) - 0.5;
    var i:int = floori(sf);
    var t:float = sf - i;
    return lerpf(SEASON_TEMP[posmod(i, 4)], SEASON_TEMP[posmod(i + 1, 4)], t);

# Whether a crop can be sown now. Warm enough today is all that is asked (no ripening check): a crop that
# frost catches can still be harvested early or salvaged (Field.EARLY_SHARE, FROZEN_SHARE).
func can_sow(crop:Dictionary) -> bool:
    # warm enough now is all that is asked: a crop that frost catches can still be salvaged (Field.FROZEN_SHARE)
    return mean_temperature() >= crop["min_temp"];

# Why a crop can't be sown now: "" if it can, else a short reason.
func sow_block_reason(crop:Dictionary) -> String:
    if mean_temperature() < crop["min_temp"]:
        return "too cold to sow (needs %d C)" % crop["min_temp"];
    return "";

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
    _dry_temperature = mean_temperature() + daily;
    temperature = _dry_temperature - RAIN_COOLING * intensity + (DROUGHT_WARMING if drought_days > 0 else 0.0);

# Share of precipitation falling as snow: 1 at or below SNOW_BELOW, 0 at or above RAIN_ABOVE.
# Judged at the temperature of a full spell, so it stays steady while the spell ramps in and out.
func snow_fraction() -> float:
    var t:float = _dry_temperature - RAIN_COOLING;
    return clampf((RAIN_ABOVE - t) / (RAIN_ABOVE - SNOW_BELOW), 0.0, 1.0);

func is_snowing() -> bool:
    return intensity > 0.05 and snow_fraction() > 0.5;

# How much faster than usual the ground dries now.
func drying() -> float:
    return DROUGHT_DRYING if drought_days > 0 else 1.0;

func description() -> String:
    if drought_days > 0 and intensity <= 0.05:
        return "Drought";
    if intensity > 0.05:
        var f:float = snow_fraction();
        if f >= 1.0:
            return "Snow";
        if f <= 0.0:
            return "Rain";
        return "Sleet";
    return "Clear";
