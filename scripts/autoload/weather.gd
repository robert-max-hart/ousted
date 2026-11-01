# ----------------------------------------------------------------
# Weather (autoload)
#     Seasonal temperature curve plus daily variation, and rain/snow.
# ----------------------------------------------------------------
extends Node;

signal weather_changed;
signal drought_changed(on:bool);       # a dry spell began or ended (the world tells the player)
signal snap_changed(dir:int, on:bool);   # a heat wave (dir 1) or a cold snap (dir -1) began or ended
signal storm_changed(on:bool);         # a thunderstorm began or ended
signal lightning(strength:float);      # a flash (0 to 1: how bright); the sky and the sound follow

# The temperatures, rain and drought chances of the year come from the map's climate (Climate).
const RAIN_COOLING      :float = 2.0;
const DROUGHT_DAYS      :Vector2i = Vector2i(5, 11);                 # how long one lasts
const DROUGHT_REST       :int = 10;                                   # days after one ends before another can start
const DROUGHT_WARMING   :float = 3.0;                                # C hotter than the season while it lasts
const DROUGHT_DRYING    :float = 2.5;                                # how much faster soil and ground dry
const RAMP_IN_HOURS     :float = 1.5;                         # game hours for rain/snow to build to full
const RAMP_OUT_HOURS    :float = 2.5;                         # ... and to clear away again
const STORM_MIN_TEMP    :float = 14.0;                        # C (dry): spells that start at least this warm may be thunderstorms
const STORM_CHANCE      :float = 0.3;                         # of such a spell, in a temperate climate (Climate "storm" scales it)
const STORM_END_PER_HOUR:float = 0.28;                        # a storm passes while the rain goes on
const STORM_SHELTER     :float = 0.5;                         # storm_level from which citizens go home
const FLASH_EVERY       :Vector2 = Vector2(5.0, 16.0);        # seconds (at the game's speed) between flashes at full storm
const HEAT_CHANCE       :Array[float] = [0.01, 0.035, 0.012, 0.0];      # a day starts a heat wave, by season (Climate "heat" and the rule scale it)
const COLD_CHANCE       :Array[float] = [0.015, 0.0, 0.02, 0.035];      # ... and a cold snap
const SNAP_DAYS         :Vector2i = Vector2i(3, 6);                   # how long one lasts
const SNAP_REST         :int = 6;                                     # days after one before another can start
const HEAT_DELTA        :float = 7.0;                                 # C hotter than the season while a heat wave lasts
const COLD_DELTA        :float = -8.0;                                # ... and colder in a cold snap
const SNOW_BELOW        :float = 0.0;                         # C: all precipitation is snow
const RAIN_ABOVE        :float = 3.0;                         # C: all precipitation is rain

var temperature     :float = 10.0;
var is_raining      :bool = false;      # a precipitation spell is active (the target state)
var intensity       :float = 0.0;       # 0..1, eases toward the spell; use this for anything visible
var _dry_temperature:float = 10.0;
var _day_offset     :float = 0.0;
var storm           :bool = false;      # the current spell is a thunderstorm (the target state)
var storm_level     :float = 0.0;       # 0..1, eased toward the storm; use this for anything visible
var _next_flash     :float = 4.0;
var snap_days       :int = 0;           # days left of a heat wave or cold snap
var snap_dir        :int = 0;           # 1 a heat wave, -1 a cold snap
var snap_rest       :int = 0;
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
    _update_storm(delta);
    var target:float = 1.0 if is_raining else 0.0;
    if is_equal_approx(intensity, target):
        return;
    var hours:float = RAMP_IN_HOURS if is_raining else RAMP_OUT_HOURS;
    intensity = move_toward(intensity, target, GameClock.game_hours(delta) / hours);
    _update_temperature();

# The storm builds with the rain, and flashes come at random while it is strong. Lightning follows the game's speed (paused: none).
func _update_storm(delta:float) -> void:
    var target:float = 1.0 if storm and is_raining else 0.0;
    if not is_equal_approx(storm_level, target):
        storm_level = move_toward(storm_level, target, GameClock.game_hours(delta) / RAMP_IN_HOURS);
    if storm_level < 0.6 or GameClock.speed() <= 0.0:
        return;
    _next_flash -= delta * World.fx_speed();
    if _next_flash <= 0.0:
        _next_flash = _rng.randf_range(FLASH_EVERY.x, FLASH_EVERY.y);
        lightning.emit(_rng.randf_range(0.5, 1.0));

func _on_day(_day:int) -> void:
    _roll_day();
    _snaps_day();
    if drought_days > 0:
        drought_days -= 1;
        if drought_days == 0:
            drought_rest = DROUGHT_REST;
            drought_changed.emit(false);
    elif drought_rest > 0:
        drought_rest -= 1;
    elif drought_enabled and _rng.randf() < clampf(float(Climate.data()["drought"][GameClock.season()]) * GameRules.drought_share(), 0.0, 1.0):
        drought_days = _rng.randi_range(DROUGHT_DAYS.x, DROUGHT_DAYS.y);
        is_raining = false;
        _set_storm(false);
        drought_changed.emit(true);

# Heat waves and cold snaps: a few days a good deal hotter or colder than the season, now and then.
func _snaps_day() -> void:
    if snap_days > 0:
        snap_days -= 1;
        if snap_days == 0:
            var was:int = snap_dir;
            snap_dir = 0;
            snap_rest = SNAP_REST;
            snap_changed.emit(was, false);
        return;
    if snap_rest > 0:
        snap_rest -= 1;
        return;
    var s:int = GameClock.season();
    var heat:float = HEAT_CHANCE[s] * float(Climate.data().get("heat", 1.0)) * GameRules.heat_share();
    var cold:float = COLD_CHANCE[s] * float(Climate.data().get("cold", 1.0)) * GameRules.cold_share();
    var roll:float = _rng.randf();
    var dir:int = 1 if roll < heat else (-1 if roll < heat + cold else 0);
    if dir != 0 and drought_enabled:
        snap_dir = dir;
        snap_days = _rng.randi_range(SNAP_DAYS.x, SNAP_DAYS.y);
        snap_changed.emit(dir, true);

# How many degrees the current heat wave or cold snap adds (0 when there is none).
func snap_offset() -> float:
    if snap_days <= 0:
        return 0.0;
    return HEAT_DELTA if snap_dir > 0 else COLD_DELTA;

func _roll_day() -> void:
    _day_offset = _rng.randf_range(-4.0, 4.0);

func _on_hour(_hour:int) -> void:
    var s:int = GameClock.season();
    if is_raining:
        if drought_days > 0 or _rng.randf() < float(Climate.data()["rain_stop"]):
            is_raining = false;
            _set_storm(false);
        elif storm and _rng.randf() < STORM_END_PER_HOUR:
            _set_storm(false);
    elif drought_days == 0 and _rng.randf() < clampf(float(Climate.data()["rain"][s]) * GameRules.rain_share(), 0.0, 1.0):
        is_raining = true;
        _set_storm(_dry_temperature >= STORM_MIN_TEMP and _rng.randf() < storm_chance());
    _update_temperature();
    weather_changed.emit();

# The chance that a spell starting warm is a thunderstorm: more in the tropics, fewer in the desert and the far north.
func storm_chance() -> float:
    return clampf(STORM_CHANCE * float(Climate.data().get("storm", 1.0)) * GameRules.storm_share(), 0.0, 1.0);

func _set_storm(on:bool) -> void:
    if storm == on:
        return;
    storm = on;
    storm_changed.emit(on);

# Whether citizens are being kept indoors by the weather.
func is_storming() -> bool:
    return storm_level >= STORM_SHELTER;

# A new game starts with clear weather (or, for the title screen, a given strength of rain or snow).
func reset(precipitation:float = 0.0) -> void:
    drought_days = 0;
    drought_rest = 0;
    snap_days = 0;
    snap_dir = 0;
    snap_rest = 0;
    storm = false;
    storm_level = 0.0;
    is_raining = precipitation > 0.0;
    intensity = precipitation;
    _roll_day();
    _update_temperature();
    weather_changed.emit();

func save_state() -> Dictionary:
    return {"is_raining": is_raining, "intensity": intensity, "day_offset": _day_offset, "drought_days": drought_days, "storm": storm, "storm_level": storm_level, "snap_days": snap_days, "snap_dir": snap_dir, "snap_rest": snap_rest};

func restore_state(d:Dictionary) -> void:
    is_raining = d["is_raining"];
    intensity = d["intensity"];
    _day_offset = d["day_offset"];
    drought_days = d.get("drought_days", 0);
    snap_days = d.get("snap_days", 0);
    snap_dir = d.get("snap_dir", 0) if snap_days > 0 else 0;
    snap_rest = d.get("snap_rest", 0);
    storm = d.get("storm", false) and is_raining;
    storm_level = d.get("storm_level", 0.0) if storm else 0.0;
    _update_temperature();

# The climate's mean temperature this many hours from now (no daily swing, rain or today's random offset).
func climate_at(hours_ahead:float) -> float:
    var sf:float = fmod((GameClock.total_hours + hours_ahead) / (GameClock.HOURS_PER_DAY * GameClock.DAYS_PER_SEASON), 4.0) - 0.5;
    var i:int = floori(sf);
    var t:float = sf - i;
    return lerpf(Climate.temps()[posmod(i, 4)], Climate.temps()[posmod(i + 1, 4)], t);

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
    # the climate's temperatures sit at the middle of each season; blend between them
    var sf:float = GameClock.year_fraction_seasons() - 0.5;
    var i:int = floori(sf);
    var t:float = sf - i;
    var a:float = Climate.temps()[posmod(i, 4)];
    var b:float = Climate.temps()[posmod(i + 1, 4)];
    return lerpf(a, b, t) + _day_offset + snap_offset();

func _update_temperature() -> void:
    var h:float = GameClock.hour();
    # coldest around 04:00, warmest around 16:00
    var daily:float = -cos((h - 4.0) / 24.0 * TAU) * float(Climate.data()["swing"]);
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
    if storm_level > 0.3 and intensity > 0.05:
        return "Thunderstorm";
    if snap_days > 0 and intensity <= 0.05:
        return "Heat wave" if snap_dir > 0 else "Cold snap";
    if intensity > 0.05:
        var f:float = snow_fraction();
        if f >= 1.0:
            return "Snow";
        if f <= 0.0:
            return "Rain";
        return "Sleet";
    return "Clear";
