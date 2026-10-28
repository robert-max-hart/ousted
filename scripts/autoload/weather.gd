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
const RAMP_IN_HOURS     :float = 1.5;                         # game hours for rain/snow to build to full
const RAMP_OUT_HOURS    :float = 2.5;                         # ... and to clear away again
const SNOW_BELOW        :float = 0.0;                         # C: all precipitation is snow
const RAIN_ABOVE        :float = 3.0;                         # C: all precipitation is rain

var temperature     :float = 10.0;
var is_raining      :bool = false;      # a precipitation spell is active (the target state)
var intensity       :float = 0.0;       # 0..1, eases toward the spell; use this for anything visible
var _dry_temperature:float = 10.0;
var _day_offset     :float = 0.0;
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

# A new game starts with clear weather (or, for the title screen, a given strength of rain or snow).
func reset(precipitation:float = 0.0) -> void:
    is_raining = precipitation > 0.0;
    intensity = precipitation;
    _roll_day();
    _update_temperature();
    weather_changed.emit();

func save_state() -> Dictionary:
    return {"is_raining": is_raining, "intensity": intensity, "day_offset": _day_offset};

func restore_state(d:Dictionary) -> void:
    is_raining = d["is_raining"];
    intensity = d["intensity"];
    _day_offset = d["day_offset"];
    _update_temperature();

# The climate's mean temperature this many hours from now (no daily swing, rain or today's random offset).
func climate_at(hours_ahead:float) -> float:
    var sf:float = fmod((GameClock.total_hours + hours_ahead) / (GameClock.HOURS_PER_DAY * GameClock.DAYS_PER_SEASON), 4.0) - 0.5;
    var i:int = floori(sf);
    var t:float = sf - i;
    return lerpf(SEASON_TEMP[posmod(i, 4)], SEASON_TEMP[posmod(i + 1, 4)], t);

const SOW_FROST_MARGIN:float = 3.0;       # the daily swing dips below the mean: keep this clear of the crop's frost limit
const SOW_WATER_FACTOR:float = 0.8;       # soil moisture slows growth a little: assume this share of full speed
const SOW_LOOKAHEAD_DAYS:int = 90;
var _sow_cache:Dictionary = {};           # crop name + day -> bool

# Whether a crop sown now would ripen before the climate freezes it: warm enough today, and following the
# climate forward day by day (growth as in Field._growth_rate), it ripens before the mean temperature comes
# within SOW_FROST_MARGIN of its frost limit. Nothing here names a season, so it holds for any climate.
func can_sow(crop:Dictionary) -> bool:
    var key:String = "%s %d" % [crop["name"], GameClock.day_index()];
    if _sow_cache.has(key):
        return _sow_cache[key];
    var ok:bool = false;
    if mean_temperature() >= crop["min_temp"]:
        var progress:float = 0.0;
        ok = true;
        for day in SOW_LOOKAHEAD_DAYS:
            var t:float = climate_at((day + 0.5) * GameClock.HOURS_PER_DAY);
            if t < crop["frost_temp"] + SOW_FROST_MARGIN:
                ok = false;
                break;
            if t >= crop["min_temp"]:
                progress += clampf((t - crop["min_temp"]) / 8.0, 0.3, 1.0) * SOW_WATER_FACTOR / crop["grow_days"];
            if progress >= 1.0:
                break;
        ok = ok and progress >= 1.0;
    if _sow_cache.size() > 200:
        _sow_cache.clear();
    _sow_cache[key] = ok;
    return ok;

# Why a crop can't be sown now: "" if it can, else a short reason.
func sow_block_reason(crop:Dictionary) -> String:
    if mean_temperature() < crop["min_temp"]:
        return "too cold to sow (needs %d C)" % crop["min_temp"];
    if not can_sow(crop):
        return "too late: frost would come before it ripens";
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
    temperature = _dry_temperature - RAIN_COOLING * intensity;

# Share of precipitation falling as snow: 1 at or below SNOW_BELOW, 0 at or above RAIN_ABOVE.
# Judged at the temperature of a full spell, so it stays steady while the spell ramps in and out.
func snow_fraction() -> float:
    var t:float = _dry_temperature - RAIN_COOLING;
    return clampf((RAIN_ABOVE - t) / (RAIN_ABOVE - SNOW_BELOW), 0.0, 1.0);

func is_snowing() -> bool:
    return intensity > 0.05 and snow_fraction() > 0.5;

func description() -> String:
    if intensity > 0.05:
        var f:float = snow_fraction();
        if f >= 1.0:
            return "Snow";
        if f <= 0.0:
            return "Rain";
        return "Sleet";
    return "Clear";
