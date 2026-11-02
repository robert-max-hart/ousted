# ----------------------------------------------------------------
# Pawn
#     A citizen. Tracks needs, walks the nav grid and runs Tasks handed
#     out by the JobManager.
# ----------------------------------------------------------------
class_name Pawn extends Node3D;

const WALK_SPEED        :float = 3.0;      # metres per real second at 1x
const WADE_SPEED_MULT   :float = 0.5;       # in shallow water
const ROAD_SPEED_MULT   :float = 1.5;       # on a path (earth)
const BRICK_SPEED_MULT  :float = 2.0;       # on a brick road: twice the path's gain over open ground
const SNOW_SPEED_MULT   :float = 0.6;       # on open ground under full snow cover (the speed falls away as the snow deepens)
const SNOW_ROAD_MULT    :float = 0.9;       # on a road or bridge, which feet keep trodden, under full snow cover
const COLD_DAMAGE_BELOW:float = 0.2;      # warmth under this starts hurting health, more the lower it gets
const CARRY_CAP         :int = 6;
const HUNGER_HOURS      :float = 30.0;     # full -> empty
const THIRST_HOURS      :float = 20.0;
const ENERGY_HOURS      :float = 20.0;
const SLEEP_RESTORE     :float = 1.0 / 7.0;
const FAIL_COOLDOWN     :float = 6.0;      # hours before retrying a failed target
const NON_WORK_KINDS    :Array[StringName] = [&"sleep", &"eat", &"drink", &"warm", &"idle"];   # tools don't speed these up or wear
const NON_LABOR_KINDS   :Array[StringName] = [&"sleep", &"eat", &"drink", &"warm", &"idle", &"stay_home", &"school", &"care", &"bury", &"heal", &"tavern", &"chapel", &"bath", &"flee", &"fire", &"camp", &"cool"];
const FIRE_KINDS        :Array[StringName] = [&"flee", &"fire"];
const NIGHT_EXEMPT      :Array[StringName] = [&"sleep", &"eat", &"drink", &"warm", &"deliver", &"haul", &"flee", &"fire", &"cool"];

const MALE_NAMES        :Array[String] = ["Aldric", "Bram", "Cedric", "Dunstan", "Edwin", "Godric", "Hal", "Osric", "Rowan", "Wystan", "Alden", "Tobin"];
const FEMALE_NAMES      :Array[String] = ["Aelwen", "Bryony", "Cerys", "Edith", "Elfreda", "Hilda", "Isolde", "Maud", "Rowena", "Wren", "Tamsin", "Agnes"];

var look_seed   :int = 0;       # seeds the cosmetic randomness (shirt, skin) so a loaded citizen looks the same
var first_name  :String;
var is_male     :bool;
var general_xp  :float = 0.0;     # general experience from school, as a work speed bonus (0.1 = 10% faster)
var job_xp      :Dictionary = {};   # profession -> experience in that job, as a work speed bonus for that job only
var age         :float;         # in citizen years (see Defs.ageing_days_per_year)
var profession  :int = JobManager.Profession.LABORER;
var home        :Building = null;
var partner     :Pawn = null;
var parents     :Array[Pawn] = [];     # living parents (a parent who dies is removed), empty for the first settlers
var carer       :Pawn = null;          # who is on the way to feed this baby
var due_hour    :float = -1.0;         # game hour a baby is due (this citizen is carrying one), or -1
var pair_ready_hour:float = 0.0;       # not before this hour can this citizen pair again (after losing a partner)
var conceive_ready_hour:float = 0.0;   # nor conceive again before this
var mood        :float = Defs.MOOD_BASE;   # happiness: follows the target from happiness_factors() slowly
var grief       :Array[Dictionary] = [];   # {amount, start, until, body}: fades linearly from start to until
var homeless_hours:float = 0.0;            # with no home at all (a shack is a home here)
var treat_item  :StringName = &"";         # the treat whose boost is running (named in the mood list)
var treat_mood  :float = 0.0;              # that boost
var treat_until :float = 0.0;              # game hour it wears off
var treat_ready :float = 0.0;              # game hour from which they may want another
var tavern_day  :int = -1;                 # the day they last went to the tavern
var tavern_until:float = 0.0;              # game hour the lift from the evening out wears off
var chapel_day  :int = -1;                 # the service day they last decided about
var chapel_until:float = 0.0;              # game hour the lift from a service wears off
var bath_day    :int = -1;                 # the bath day they last decided about
var bath_until  :float = 0.0;              # game hour the "freshly bathed" mood wears off
var bath_mood   :float = 0.0;
var clean_until :float = 0.0;              # game hour the protection from illness wears off
var clean_mult  :float = 1.0;              # the share of the usual illness chances while clean
var illness     :float = 0.0;              # how sick: 0 is well, 1 is gravely ill (see Illness)
var bucket      :bool = false;             # carrying a bucket of water to a fire (not saved)
var burned_until:float = 0.0;              # game hour until which a death counts as burns (Fires)
var overheat    :float = 0.0;              # 0 comfortable to 1 heatstroke (Heat)
var immune_until:float = 0.0;              # game hour until which they cannot catch it again
var care_until  :float = 0.0;              # game hour a healer's visit runs out
var care_quality:float = 0.0;              # 1 when the healer had herbs, 0 when they only sat with them
var _unhappy_hours:float = 0.0;            # in a row, below Defs.LEAVE_BELOW

# needs, 0..1 (1 = fully satisfied)
var hunger      :float = 1.0;
var thirst      :float = 1.0;
var energy      :float = 1.0;
var warmth      :float = 1.0;
var health      :float = 1.0;
var indoors     :bool = false;
var shelter     :Building = null;   # the building we are inside
var sleeping    :bool = false;

var carry_item  :StringName = &"";
var carry_amount:int = 0;

var tool        :StringName = &"";      # equipped tool item, or &"" for none
var clothing    :StringName = &"";         # the clothes worn (an item with "clothing" in Defs.ITEMS), or none
var clothing_hours:float = 0.0;            # game hours of wear left in them
var tool_uses   :float = 0.0;           # game hours of work left in it

var task        :Task = null;
var status      :String = "Idle";
var removed     :bool = false;
var world       :World;

var _path           :Array[Vector2i] = [];
var _path_i         :int = 0;
var _failed         :Dictionary = {};       # target -> game hour it can be retried
var _need_block_until:float = -1.0;
var _rig            :PawnRig;                 # the body: limbs, tools and carried goods, posed from _animate (visual only)
var _last_phase     :float = 0.0;             # where the swing was last frame (a strike sounds when it passes the bottom)
var _ill_mark       :Sprite3D;                # a green cross over a sick citizen
var _idle_mark      :Sprite3D;                # a small icon over a citizen with nothing to do (UIIcons)
var _anim_t         :float = 0.0;
var _face_yaw       :float = 0.0;              # the way they are heading: the body turns to it over a moment, not all at once
var _work_now       :bool = false;            # what the last frame did, for the animation
var _move_now       :bool = false;
var _eat_now        :StringName = &"";        # &"eat" or &"drink" while doing that (sitting to eat, bending to drink)
var _still_t        :float = 0.0;             # seconds an idle citizen has stood still: after a while they sit down
var _stride         :float = 0.0;             # the walk cycle, in radians: it advances with the distance walked, so the feet keep up with the ground
var _last_pos       :Vector3 = Vector3.ZERO;
var _steps          :int = 0;                 # whole steps taken (a foot lands every half turn of the walk cycle), for the footsteps
var _bites          :int = 0;                 # bites taken at this meal, for the eating sounds
var _meal_kind      :StringName = &"";
const STEP_REACH    :float = 16.0;            # metres (plus the camera's height) a footstep is heard from
const STEP_DB       :float = -13.0;
const STEP_GAP_MS   :int = 140;
const SIT_AFTER     :float = 4.0;
var _inside_work    :Building = null;         # a workplace this citizen is working inside of (out of sight), see Defs "indoor_work"

func setup(w:World, cell:Vector2i, rng:RandomNumberGenerator, taken_names:Array[String] = []) -> void:
    world = w;
    is_male = rng.randf() < 0.5;
    var names:Array[String] = [];
    for n in (MALE_NAMES if is_male else FEMALE_NAMES):
        if not taken_names.has(n):
            names.append(n);
    if names.is_empty():
        names = MALE_NAMES if is_male else FEMALE_NAMES;
    first_name = names[rng.randi() % names.size()];
    age = rng.randi_range(18, 32) + rng.randf();
    position = w.terrain.cell_center(cell);
    name = "Pawn_%s" % first_name;
    look_seed = rng.randi();
    _build_look();

# Builds the body from look_seed.
func _build_look() -> void:
    var look:RandomNumberGenerator = RandomNumberGenerator.new();
    look.seed = look_seed;
    _anim_t = float(look_seed % 997) * 0.77;          # everyone starts at their own moment of the cycles, so a crowd does not move in step
    _build_visual(look);

func to_dict() -> Dictionary:
    return {
        "name": first_name, "is_male": is_male, "age": age, "profession": profession, "look_seed": look_seed,
        "hunger": hunger, "thirst": thirst, "energy": energy, "warmth": warmth, "health": health,
        "general_xp": general_xp, "job_xp": job_xp.duplicate(), "carry_item": carry_item, "carry_amount": carry_amount, "tool": tool, "tool_uses": tool_uses, "clothing": clothing, "clothing_hours": clothing_hours,
        "position": position, "home": world.buildings.find(home) if home != null else -1,
        "partner": world.pawns.find(partner) if partner != null else -1,
        "parents": parents.map(func(x:Pawn) -> int: return world.pawns.find(x)),
        "due_hour": due_hour, "pair_ready_hour": pair_ready_hour, "conceive_ready_hour": conceive_ready_hour,
        "treat_item": treat_item, "treat_mood": treat_mood, "treat_until": treat_until, "treat_ready": treat_ready,
        "tavern_day": tavern_day, "tavern_until": tavern_until, "chapel_day": chapel_day, "chapel_until": chapel_until, "bath_day": bath_day, "bath_until": bath_until, "bath_mood": bath_mood, "clean_until": clean_until, "clean_mult": clean_mult, "illness": illness, "overheat": overheat, "immune_until": immune_until, "care_until": care_until, "care_quality": care_quality,
        "mood": mood, "grief": grief.duplicate(true), "unhappy_hours": _unhappy_hours, "homeless_hours": homeless_hours,
    };

@warning_ignore("integer_division")
# Rebuilds a saved citizen. The task is not saved: it starts idle and picks something new. A citizen who was
# indoors is put on the nearest walkable cell.
func restore(w:World, d:Dictionary) -> void:
    world = w;
    first_name = d["name"];
    is_male = d["is_male"];
    age = float(d["age"]);
    profession = d["profession"];
    look_seed = d["look_seed"];
    hunger = d["hunger"];
    thirst = d["thirst"];
    energy = d["energy"];
    warmth = d["warmth"];
    health = d["health"];
    general_xp = d.get("general_xp", 0.0);
    job_xp = (d.get("job_xp", {}) as Dictionary).duplicate();
    carry_item = d["carry_item"];
    carry_amount = d["carry_amount"];
    tool = d["tool"];
    tool_uses = d["tool_uses"];
    clothing = d.get("clothing", &"");
    clothing_hours = d.get("clothing_hours", 0.0);
    due_hour = d.get("due_hour", -1.0);
    pair_ready_hour = d.get("pair_ready_hour", 0.0);
    conceive_ready_hour = d.get("conceive_ready_hour", 0.0);
    mood = d.get("mood", Defs.MOOD_BASE);
    tavern_day = d.get("tavern_day", -1);
    tavern_until = d.get("tavern_until", 0.0);
    chapel_day = d.get("chapel_day", -1);
    chapel_until = d.get("chapel_until", 0.0);
    bath_day = d.get("bath_day", -1);
    bath_until = d.get("bath_until", 0.0);
    bath_mood = d.get("bath_mood", 0.0);
    clean_until = d.get("clean_until", 0.0);
    clean_mult = d.get("clean_mult", 1.0);
    illness = d.get("illness", 0.0);
    overheat = d.get("overheat", 0.0);
    immune_until = d.get("immune_until", 0.0);
    care_until = d.get("care_until", 0.0);
    care_quality = d.get("care_quality", 0.0);
    treat_item = d.get("treat_item", &"");
    treat_mood = d.get("treat_mood", 0.0);
    treat_until = d.get("treat_until", 0.0);
    treat_ready = d.get("treat_ready", 0.0);
    for g in d.get("grief", []):
        grief.append(g);
    _unhappy_hours = d.get("unhappy_hours", 0.0);
    homeless_hours = d.get("homeless_hours", 0.0);
    name = "Pawn_%s" % first_name;
    _build_look();
    var c:Vector2i = w.nav.nearest_walkable(w.terrain.world_to_cell(d["position"]), 8);
    position = w.terrain.cell_center(c if c != NavGrid.NO_CELL else Vector2i(Terrain.SIZE / 2, Terrain.SIZE / 2));
    _update_carry_visual();

func _process(delta:float) -> void:
    _animate(delta);
    var dh:float = GameClock.game_hours(delta);
    if dh <= 0.0:
        return;
    _update_needs(dh);
    if removed:
        return;
    if health <= 0.0:
        world.kill_pawn(self, _death_cause());
        return;
    if task != null and task.interruptible and _should_interrupt():
        end_task(false);
    if task == null:
        task = world.jobs.choose_task(self);
        if task == null:
            status = "Idle";
            return;
        if indoors and task.kind != &"stay_home":
            go_outside();          # (staying home leaves the citizen inside: any other task starts from the doorstep)
    _run_task(delta * GameClock.speed(), dh);
    position.y = world.stand_y(position.x, position.z);

# --------------------------------
# Tools

func tool_bonus() -> float:
    return Defs.ITEMS[tool]["tool"]["bonus"] if tool != &"" else 0.0;

func equip(item:StringName) -> void:
    tool = item;
    tool_uses = Defs.ITEMS[item]["tool"]["uses"];

func _wear_tool(dh:float) -> void:
    if tool == &"":
        return;
    tool_uses -= dh;
    if tool_uses <= 0.0:
        world.notify("%s's %s broke." % [first_name, Defs.item_name(tool).to_lower()]);
        tool = &"";

# --------------------------------
# Clothing

# The share of the cold drain the clothes stop (0 with none).
func cold_resist() -> float:
    return Defs.ITEMS[clothing]["clothing"]["warm"] if clothing != &"" else 0.0;

# The mood the clothes give (fine clothes only).
func clothes_mood() -> float:
    return Defs.ITEMS[clothing]["clothing"].get("mood", 0.0) if clothing != &"" else 0.0;

func dress(item:StringName) -> void:
    clothing = item;
    clothing_hours = Defs.ITEMS[item]["clothing"]["days"] * GameClock.HOURS_PER_DAY;
    _rig.set_clothing(clothing);

func _wear_clothing(dh:float) -> void:
    if clothing == &"":
        return;
    clothing_hours -= dh;
    if clothing_hours <= 0.0:
        world.notify("%s's %s wore out." % [first_name, Defs.item_name(clothing).to_lower()]);
        clothing = &"";
        _rig.set_clothing(clothing);

func cell() -> Vector2i:
    return world.terrain.world_to_cell(position);

# --------------------------------
# Needs

# --------------------------------
# Life stages

func is_baby() -> bool:
    return age < Defs.BABY_UNTIL;

func is_child() -> bool:
    return not is_baby() and not is_adult();

func is_adult() -> bool:
    return age >= Defs.ADULT_AT;

func stage_name() -> String:
    return "baby" if is_baby() else "child" if not is_adult() else "elder" if age >= Defs.OLD_AGE_EFFICIENCY[0][0] else "adult";

# How fast this citizen works compared with a prime-age adult.
func work_efficiency() -> float:
    return (Defs.age_efficiency(age) if is_adult() else Defs.CHILD_EFFICIENCY) * (1.0 + general_xp) * mood_efficiency() * Illness.work_factor(self) * Heat.work_factor(self);

# Unhappy citizens work a little slower.
func mood_efficiency() -> float:
    return lerpf(Defs.MOOD_SLOW_MIN, 1.0, clampf(mood / Defs.MOOD_SLOW_BELOW, 0.0, 1.0));

# Working (not school, needs, sleep, care or waiting about); children doing this is what child labor means.
func is_laboring() -> bool:
    return task != null and not NON_LABOR_KINDS.has(task.kind);

# Studies for dh game hours.
func learn(dh:float, mult:float = 1.0) -> void:
    general_xp += Defs.general_xp_gain(general_xp, dh) * mult;

func experience(job:int) -> float:
    return job_xp.get(job, 0.0);

# Practises a job for dh game hours (real time at work, not sped up by the bonuses).
func practise(job:int, dh:float) -> void:
    job_xp[job] = experience(job) + Defs.job_xp_gain(experience(job), dh);

# Don't pick this target again for a while (as when a task on it failed).
func avoid(target:Variant, hours:float) -> void:
    _failed[target] = GameClock.total_hours + hours;

func _age_tick(dh:float) -> void:
    age += dh / (Defs.ageing_days_per_year * GameClock.HOURS_PER_DAY);
    if world.rng.randf() < Defs.old_age_death_per_hour(age) * dh:
        world.kill_pawn(self, "old age", true);

func _update_needs(dh:float) -> void:
    _age_tick(dh);
    if removed:
        return;
    var need_mult:float = Defs.BABY_NEED_MULT if is_baby() else 1.0;      # a carer feeds a baby (see Families)
    hunger = maxf(0.0, hunger - dh * need_mult / HUNGER_HOURS);
    thirst = maxf(0.0, thirst - dh * need_mult * Heat.thirst_mult(self) / THIRST_HOURS);
    if is_baby():
        energy = 1.0;
    elif sleeping:
        energy = minf(1.0, energy + dh * SLEEP_RESTORE * (1.0 if indoors else Defs.OUTDOOR_SLEEP_MULT));
    else:
        energy = maxf(0.0, energy - dh / ENERGY_HOURS);
    var temp:float = Weather.temperature;
    var chill:float = 1.0 - cold_resist();
    _wear_clothing(dh);
    var by_fire:bool = not indoors and world.fires != null and world.fires.camp_near(cell(), Fires.CAMP_WARM_RADIUS);
    if indoors and (shelter == null or not World.alive(shelter) or shelter.is_heated()):
        warmth = minf(1.0, warmth + dh * 0.25);
    elif indoors and shelter.def.get("shack", false):
        warmth = clampf(warmth + dh * (Defs.SHACK_WARMTH_RATE - maxf(0.0, 8.0 - temp) * Defs.SHACK_COLD_DRAIN * chill), 0.0, 1.0);
    elif indoors and temp < 8.0:
        # a cold house keeps the wind off, but nobody warms up in it
        warmth = maxf(0.0, warmth - dh * (8.0 - temp) * 0.004 * chill);
    elif indoors:
        warmth = minf(1.0, warmth + dh * 0.1);
    elif by_fire:
        warmth = minf(1.0, warmth + dh * 0.25);       # sitting at a campfire is as good as a heated house
    elif temp < 8.0:
        warmth = maxf(0.0, warmth - dh * (8.0 - temp) * 0.006 * chill);
    else:
        warmth = minf(1.0, warmth + dh * 0.1);
    _update_mood(dh);
    if removed:
        return;
    var damage:float = 0.0;
    if hunger <= 0.0:
        damage += 1.0 / 36.0;
    if thirst <= 0.0:
        damage += 1.0 / 18.0;
    if warmth < COLD_DAMAGE_BELOW:
        damage += (1.0 - warmth / COLD_DAMAGE_BELOW) / 24.0;
    damage += Illness.tick(self, dh);
    damage += Heat.tick(self, dh);
    if damage > 0.0:
        health = maxf(0.0, health - damage * dh);
    else:
        health = minf(1.0, health + dh / 48.0);

# An adult who has not yet decided about the tavern tonight, in its hours, with a tavern standing, empty-handed.
func tavern_due() -> bool:
    var h:float = GameClock.hour();
    if not is_adult() or tavern_day == GameClock.day_index() or illness > 0.0 or h < Defs.TAVERN_FROM or h >= Defs.TAVERN_TO or energy < 0.3:
        return false;
    for b in world.buildings:
        if b.def.get("tavern", false) and b.is_open():
            return true;
    return false;

# An adult who has not yet decided about this service day, in its morning hours, with a chapel standing.
func chapel_due() -> bool:
    var h:float = GameClock.hour();
    var day:int = GameClock.day_index();
    if not is_adult() or chapel_day == day or not Defs.is_service_day(day) or illness > 0.0 or h < Defs.CHAPEL_FROM or h >= Defs.CHAPEL_TO or energy < 0.3:
        return false;
    for b in world.buildings:
        if b.def.get("chapel", false) and b.is_open():
            return true;
    return false;

# A citizen of 5 or over, not ill, whose bath day it is, in the bath hours, with an open bathhouse that has water.
func bath_due() -> bool:
    var h:float = GameClock.hour();
    var day:int = GameClock.day_index();
    if is_baby() or bath_day == day or illness > 0.0 or h < Defs.BATH_FROM or h >= Defs.BATH_TO or energy < 0.3:
        return false;
    if (day + get_instance_id() % Defs.BATH_EVERY) % Defs.BATH_EVERY != 0:
        return false;
    for b in world.buildings:
        if b.def.get("bath", false) and b.is_open() and b.has_water():
            return true;
    return false;

# Comes out of a bath: better for it a couple of days, less likely to catch or spread a sickness for three, and with hot
# water in the cold warmed through.
func bathe(hot:bool) -> void:
    bath_until = GameClock.total_hours + Defs.BATH_MOOD_HOURS;
    bath_mood = Defs.BATH_MOOD if hot else Defs.BATH_COLD_MOOD;
    clean_until = GameClock.total_hours + Defs.BATH_CLEAN_HOURS;
    clean_mult = Defs.BATH_ILLNESS_MULT if hot else Defs.BATH_COLD_ILLNESS_MULT;
    if hot and Weather.temperature < Defs.BATH_COLD_BELOW:
        warmth = 1.0;

# The share of the usual illness chances this citizen has right now (1 when not freshly bathed).
func clean_factor() -> float:
    return clean_mult if GameClock.total_hours < clean_until else 1.0;

# A service halves the grief for any death in the last few days, once for each.
func pray() -> void:
    for g in grief:
        if g["start"] >= GameClock.total_hours - Defs.CHAPEL_GRIEF_DAYS * GameClock.HOURS_PER_DAY and not g.get("prayed", false):
            g["amount"] *= Defs.CHAPEL_GRIEF_MULT;
            g["prayed"] = true;

func _should_interrupt() -> bool:
    if world.fires != null and world.fires.wild_burning() and not FIRE_KINDS.has(task.kind) and world.fire_tasks.wants(self):
        return true;          # a fire close by: run, or go and fight it (FireTasks)
    if profession == JobManager.Profession.HEALER and task.job == JobManager.Profession.HEALER and world.jobs.health.HERB_KINDS.has(task.kind) and world.jobs.health.patient_waiting(self):
        return true;          # picking herbs: a sick citizen comes first (see HealthTasks.herb_task)
    if carry_amount == 0 and bath_due() and task.kind != &"bath":
        return true;          # bath day: whoever is about their work comes along (see NeedsTasks.bath_task)
    if carry_amount == 0 and chapel_due() and task.kind != &"chapel":
        return true;          # the bell rings on a service day (see NeedsTasks.chapel_task)
    if carry_amount == 0 and tavern_due() and task.kind != &"tavern":
        return true;          # the tavern opens: whoever is about their work comes along (once a day, see NeedsTasks.tavern_task)
    if Weather.is_storming() and not world.policies.is_on(&"storm_work") and carry_amount == 0 and not indoors and not NON_LABOR_KINDS.has(task.kind) and world.shelter_for(self) != null:
        return true;          # a thunderstorm: whoever is out at their work goes home (see JobManager.choose_task)
    if Heat.siesta_due(self) and carry_amount == 0 and not indoors and not NON_LABOR_KINDS.has(task.kind):
        return true;          # the worst of the midday heat: whoever is out at their work goes home (see JobManager.choose_task)
    if GameClock.total_hours >= _need_block_until:
        if thirst < 0.2 or warmth < 0.2 or energy < 0.08 or overheat > Heat.CRITICAL:
            return true;
        if hunger < 0.15 and Stock.best_food() != &"":
            return true;
    return GameClock.is_night() and not NIGHT_EXEMPT.has(task.kind);

# Called by the JobManager when a need couldn't be met, so we don't thrash.
func block_needs(hours:float) -> void:
    _need_block_until = GameClock.total_hours + hours;

func needs_blocked() -> bool:
    return GameClock.total_hours < _need_block_until;

func _death_cause() -> String:
    if thirst <= 0.0:
        return "thirst";
    if hunger <= 0.0:
        return "starvation";
    if warmth < COLD_DAMAGE_BELOW:
        return "exposure";
    if GameClock.total_hours < burned_until:
        return "burns";
    if overheat >= 0.85:
        return "heatstroke";
    if illness > 0.0:
        return "illness";
    return "poor health";

func happiness() -> float:
    return mood;

# --------------------------------
# Happiness

# The named reasons behind the target: [label, value] pairs added to Defs.MOOD_BASE. Babies have none.
func happiness_factors() -> Array:
    var f:Array = [];
    if is_baby():
        return f;
    for n in [["Hungry", hunger, 0.3], ["Thirsty", thirst, 0.3], ["Cold", warmth, 0.3], ["Unwell", health, 0.2], ["Tired", energy, 0.15]]:
        var short:float = clampf((0.5 - n[1]) / 0.5, 0.0, 1.0);
        if short > 0.0:
            f.append([n[0], -n[2] * short]);
    if home == null:
        f.append(["No home", -lerpf(Defs.HOMELESS_MOOD.x, Defs.HOMELESS_MOOD.y, clampf(homeless_hours / (Defs.HOMELESS_MOOD_DAYS * GameClock.HOURS_PER_DAY), 0.0, 1.0))]);
        if Weather.temperature < Defs.HEATING_BELOW:
            f.append(["Sleeping in the cold", -Defs.COLD_SLEEP_MOOD]);
    elif home.def.get("shack", false):
        f.append(["Lives in a shack", -Defs.SHACK_MOOD]);
    else:
        f.append(["Has a home", 0.1]);
        if Weather.temperature < Defs.HEATING_BELOW and World.alive(home) and not home.is_heated():
            f.append(["Cold house", -0.1]);
    var kinds:int = 0;
    for item in Defs.ITEMS:
        if Defs.is_food(item) and Stock.amount(item) > 0:
            kinds += 1;
    if illness > 0.0:
        f.append(["Ill", -0.2 * illness]);
    if Heat.mood_loss(self) > 0.0:
        f.append(["Too hot", -Heat.mood_loss(self)]);
    if clothes_mood() > 0.0:
        f.append(["Fine clothes", clothes_mood()]);
    if GameClock.total_hours < tavern_until:
        f.append(["Evening at the tavern", Defs.TAVERN_MOOD]);
    if GameClock.total_hours < bath_until:
        f.append(["Freshly bathed", bath_mood]);
    if GameClock.total_hours < chapel_until:
        f.append(["Attended service", Defs.CHAPEL_MOOD]);
    if kinds >= 2:
        f.append(["Varied diet", 0.05 if kinds == 2 else 0.1]);
    if treat_boost_now() > 0.0:
        f.append(["Enjoyed %s" % Defs.item_name(treat_item).to_lower(), treat_boost_now()]);
    var sorrow:float = grief_now();
    if sorrow > 0.0:
        f.append(["Grieving", -sorrow]);
    if world.child_labor_share > 0.0:
        f.append(["Children are working", -world.child_labor_share * (Defs.CHILD_LABOR_MOOD_CHILD if is_child() else Defs.CHILD_LABOR_MOOD_ADULT)]);
    if World.alive(home):
        for b in home.residents:
            if b.is_baby() and (b.hunger < 0.3 or b.thirst < 0.3):
                f.append(["A baby is going hungry", -0.15]);
                break;
    return f;

func target_mood() -> float:
    var t:float = Defs.MOOD_BASE;
    for f in happiness_factors():
        t += f[1];
    return clampf(t, 0.0, 1.0);

func treat_boost_now() -> float:
    return treat_mood if GameClock.total_hours < treat_until else 0.0;

# Fed up with nothing sweet: the last boost has worn off and the random pause after it has passed.
func wants_treat() -> bool:
    if is_baby():
        return false;
    if treat_ready <= 0.0:       # never had one: the first craving comes within two days, differently for each
        treat_ready = GameClock.total_hours + world.rng.randf_range(0.0, 2.0 * GameClock.HOURS_PER_DAY);
    return GameClock.total_hours >= maxf(treat_until, treat_ready);

# Eats a treat: a little food, and a mood boost for a few days. The next one is wanted after the boost, plus up to a day more.
func enjoy_treat(item:StringName, info:Dictionary) -> void:
    hunger = minf(1.0, hunger + info["nutrition"]);
    treat_item = item;
    treat_mood = info["mood"];
    treat_until = GameClock.total_hours + info["days"] * GameClock.HOURS_PER_DAY;
    treat_ready = treat_until + world.rng.randf_range(0.0, GameClock.HOURS_PER_DAY);

func grief_now() -> float:
    var total:float = 0.0;
    for g in grief:
        var span:float = g["until"] - g["start"];
        total += g["amount"] * clampf(1.0 - (GameClock.total_hours - g["start"]) / span, 0.0, 1.0);
    return total;

func add_grief(amount:float, days:float, body_id:int) -> void:
    grief.append({"amount": amount, "start": GameClock.total_hours, "until": GameClock.total_hours + days * GameClock.HOURS_PER_DAY, "body": body_id});

# A buried body softens the grief felt for it.
func soften_grief(body_id:int) -> void:
    for g in grief:
        if g["body"] == body_id:
            g["amount"] *= Defs.GRAVE_SOFTEN;

func _update_mood(dh:float) -> void:
    if is_baby():
        return;
    homeless_hours = homeless_hours + dh if home == null else 0.0;
    for i in range(grief.size() - 1, -1, -1):
        if grief[i]["until"] <= GameClock.total_hours:
            grief.remove_at(i);
    mood += (target_mood() - mood) * (1.0 - exp(-dh / Defs.MOOD_HOURS));
    if mood < Defs.LEAVE_BELOW:
        _unhappy_hours += dh;
        if _unhappy_hours >= Defs.LEAVE_AFTER_DAYS * GameClock.HOURS_PER_DAY:
            world.leave_colony(self);
    elif mood > Defs.LEAVE_RECOVER:
        _unhappy_hours = 0.0;

# --------------------------------
# Carrying

func add_carry(item:StringName, n:int) -> void:
    if carry_item != item and carry_amount > 0:
        push_warning("%s dropped %d %s to carry %s" % [first_name, carry_amount, carry_item, item]);
    if carry_item != item:
        carry_amount = 0;
    carry_item = item;
    carry_amount += n;
    _update_carry_visual();

func set_carry(item:StringName, n:int) -> void:
    carry_item = item;
    carry_amount = n;
    _update_carry_visual();

func clear_carry() -> void:
    carry_item = &"";
    carry_amount = 0;
    _update_carry_visual();

func go_inside(b:Building, sleep:bool) -> void:
    indoors = true;
    shelter = b;
    sleeping = sleep;
    visible = false;
    if b != null:
        position = world.terrain.cell_center(b.origin + b.size / 2);

func go_outside() -> void:
    if not indoors:
        return;
    indoors = false;
    shelter = null;
    sleeping = false;
    visible = true;
    # step back onto a walkable cell next to wherever we were
    var c:Vector2i = world.nav.nearest_walkable(cell(), 8);
    if c != NavGrid.NO_CELL:
        position = world.terrain.cell_center(c);

# --------------------------------
# Tasks

func has_failed(target:Variant) -> bool:
    return _failed.has(target) and _failed[target] > GameClock.total_hours;

func end_task(success:bool) -> void:
    if task == null:
        return;
    var t:Task = task;
    task = null;
    _path.clear();
    t.finish(self, success);
    _leave_workplace();

# Working at a building that is worked in (the smithy, the school): step inside while the work lasts.
func _enter_workplace() -> void:
    var b:Variant = task.workplace;
    if _inside_work != null or indoors or not (b is Building) or not World.alive(b) or not (b as Building).def.get("indoor_work", false):
        return;
    var wp:Building = b;
    if not wp.is_complete() or not wp.rect().grow(2).has_point(cell()):
        return;
    _inside_work = wp;
    visible = false;
    position = world.terrain.cell_center(wp.origin + wp.size / 2);

func _leave_workplace() -> void:
    if _inside_work == null:
        return;
    _inside_work = null;
    if indoors:
        return;
    visible = true;
    var c:Vector2i = world.nav.nearest_walkable(cell(), 8);
    if c != NavGrid.NO_CELL:
        position = world.terrain.cell_center(c);

func _fail_task() -> void:
    if task.target != null:
        _failed[task.target] = GameClock.total_hours + FAIL_COOLDOWN;
    end_task(false);

func _run_task(move_dt:float, dh:float) -> void:
    var step:Dictionary = task.current();
    if step.is_empty():
        end_task(true);
        return;
    status = step["status"];
    match step["type"]:
        Task.Step.MOVE:
            if not step.has("started"):
                step["started"] = true;
                _leave_workplace();
                if not _plan_path(step):
                    _fail_task();
                    return;
            _move_now = true;
            if _follow_path(move_dt):
                task.index += 1;
        Task.Step.WORK:
            _enter_workplace();
            var working:bool = not NON_WORK_KINDS.has(task.kind);
            _work_now = working and is_laboring() and task.kind != &"teach";
            _eat_now = task.kind if (task.kind == &"eat" or task.kind == &"drink") else &"";
            var speed:float = (1.0 + tool_bonus()) * work_efficiency() if working else 1.0;
            if working:
                _wear_tool(dh);
                if task.job >= 0:
                    speed *= 1.0 + experience(task.job);
                    practise(task.job, dh);
            if (step["tick"] as Callable).call(self, dh * speed) and task != null:       # (the work itself may have ended the task, as finishing an expansion does)
                task.index += 1;
        Task.Step.ACT:
            if (step["fn"] as Callable).call(self):
                task.index += 1;
            else:
                _fail_task();

func _plan_path(step:Dictionary) -> bool:
    var start:Vector2i = cell();
    if not world.nav.is_walkable(start):
        start = world.nav.nearest_walkable(start, 8);
        if start == NavGrid.NO_CELL:
            return false;
        position = world.terrain.cell_center(start);
    var goals:Array[Vector2i];
    if step.has("cell"):
        goals = world.access_cells_for_cell(step["cell"]);
    else:
        goals = world.access_cells(step["rect"], step["inside"]);
    goals.sort_custom(func(a:Vector2i, b:Vector2i) -> bool:
        return (a - start).length_squared() < (b - start).length_squared());
    for i in mini(goals.size(), 4):
        var path:Array[Vector2i] = world.nav.find_path(start, goals[i]);
        if not path.is_empty():
            _path = path;
            _path_i = 1;
            return true;
    return false;

# How fast a citizen walks over a cell against the open ground in clear weather: a road is quicker, shallow water slower, and snow
# slows everything dry, less on roads and bridges (see Weather.snow_depth).
func ground_speed(c:Vector2i) -> float:
    var snow:float = Weather.snow_depth;
    var o:int = world.terrain.get_overlay(c);
    if o == Terrain.Overlay.ROAD or o == Terrain.Overlay.BRICK:
        return (ROAD_SPEED_MULT if o == Terrain.Overlay.ROAD else BRICK_SPEED_MULT) * lerpf(1.0, SNOW_ROAD_MULT, snow);
    if world.terrain.is_water(c):
        return 1.0 * lerpf(1.0, SNOW_ROAD_MULT, snow) if world.is_bridge(c) else WADE_SPEED_MULT;
    return lerpf(1.0, SNOW_SPEED_MULT, snow);

# Advances along the path; returns true on arrival.
func _follow_path(move_dt:float) -> bool:
    var time:float = move_dt;
    var base:float = WALK_SPEED * (0.75 if energy < 0.15 else 1.0);
    while time > 0.0 and _path_i < _path.size():
        var c:Vector2i = _path[_path_i];
        var spd:float = base * ground_speed(c);
        var to:Vector2 = Vector2(c.x + 0.5 - position.x, c.y + 0.5 - position.z);
        var d:float = to.length();
        if d > 0.001:
            _face_yaw = atan2(to.x, to.y);
        var reach:float = spd * time;
        if d <= reach:
            position.x = c.x + 0.5;
            position.z = c.y + 0.5;
            time -= d / spd;
            _path_i += 1;
        else:
            position.x += to.x / d * reach;
            position.z += to.y / d * reach;
            time = 0.0;
    return _path_i >= _path.size();

# --------------------------------
# Info / visuals

func profession_name() -> String:
    return JobManager.PROFESSION_NAMES[profession];

func info_text() -> String:
    var s:String = "%s, %s, age %d (%s)\n" % [profession_name(), "male" if is_male else "female", int(age), stage_name()];
    s += "Doing: %s\n" % status;
    if general_xp > 0.0:
        s += "Schooling: +%d%% work speed\n" % roundi(general_xp * 100.0);
    for job in job_xp:
        if roundi(job_xp[job] * 100.0) > 0:
            s += "%s experience: +%d%%\n" % [JobManager.PROFESSION_NAMES[job], roundi(job_xp[job] * 100.0)];
    if tool != &"":
        s += "Tool: %s (%d%% left)\n" % [Defs.item_name(tool), roundi(100.0 * tool_uses / Defs.ITEMS[tool]["tool"]["uses"])];
    else:
        s += "Tool: none\n";
    if clothing != &"":
        s += "Clothes: %s (%d days left)\n" % [Defs.item_name(clothing), ceili(clothing_hours / GameClock.HOURS_PER_DAY)];
    else:
        s += "Clothes: none\n";
    if carry_amount > 0:
        s += "Carrying: %d %s\n" % [carry_amount, Defs.item_name(carry_item)];
    s += "Home: %s\n" % (home.display_name() if home != null else "none");
    if World.alive(partner):
        s += "Partner: %s%s\n" % [partner.first_name, " (expecting)" if partner.due_hour >= 0.0 else ""];
    if due_hour >= 0.0:
        s += "Expecting a baby\n";
    var kids:PackedStringArray = [];
    for k in world.pawns:
        if k.parents.has(self):
            kids.append(k.first_name);
    if not kids.is_empty():
        s += "Children: %s\n" % ", ".join(kids);
    var par:PackedStringArray = [];
    for k in parents:
        par.append(k.first_name);
    if not par.is_empty():
        s += "Parents: %s\n" % ", ".join(par);
    elif not is_adult():
        s += "Parents: none (orphan)\n";
    s += "\n";
    s += "Hunger  %s\n" % _bar(hunger);
    s += "Thirst  %s\n" % _bar(thirst);
    s += "Energy  %s\n" % _bar(energy);
    s += "Warmth  %s\n" % _bar(warmth);
    s += Heat.describe(self);
    s += "Health  %s\n" % _bar(health);
    s += Illness.describe(self);
    if not is_baby():
        s += "Happy   %s\n" % _bar(happiness());
        for f in happiness_factors():
            s += "  %s%d%% %s\n" % ["+" if f[1] >= 0.0 else "", roundi(f[1] * 100.0), f[0]];
    return s;

func _bar(v:float) -> String:
    var n:int = roundi(v * 10.0);
    return "[%s%s] %d%%" % ["#".repeat(n), "-".repeat(10 - n), roundi(v * 100.0)];

# With nothing to do at the moment (not resting, eating or on the way somewhere).
func is_idle() -> bool:
    return task != null and task.kind == &"idle" and not is_baby();

# Poses the body (see PawnRig): working swings the tool of the job, walking swings the limbs, carrying holds the goods out in front.
# Runs at the game speed (up to 3x, faster looks frantic).
func _animate(delta:float) -> void:
    var speed:float = minf(GameClock.speed(), 3.0);
    if speed <= 0.0:         # paused: freeze the pose where it is
        return;
    _anim_t += delta * speed;
    var work:bool = _work_now and speed > 0.0;
    var move:bool = _move_now and speed > 0.0;
    var eating:StringName = _eat_now;
    _work_now = false;
    _move_now = false;
    _eat_now = &"";
    _idle_mark.visible = is_idle() and illness <= 0.0;
    _ill_mark.visible = illness > 0.0 and not indoors;
    _rig.set_stage(age, is_baby(), is_adult(), age >= Defs.OLD_AGE_EFFICIENCY[0][0]);
    _rig.set_mood(0.55 if is_baby() else mood);
    _rig.set_energy(energy);
    rotation.y = lerp_angle(rotation.y, _face_yaw, 1.0 - exp(-14.0 * delta));
    var moved:float = Vector2(position.x - _last_pos.x, position.z - _last_pos.z).length();
    _last_pos = position;
    if moved < 1.5:          # (a jump, such as stepping out of a workplace, is not a stride)
        _stride += moved * PawnRig.STRIDE_PER_METRE * minf(1.0, 3.0 / maxf(1.0, GameClock.speed())) / maxf(0.5, _rig.scale.x);
        var step_now:int = int(_stride / PI);
        if step_now != _steps:
            _steps = step_now;
            _footstep();
    var carrying:bool = carry_amount > 0;
    if sleeping and not indoors:         # out in the open (homeless): lie down, with a slow breath
        _rig.pose(PawnRig.Mode.SLEEP, _anim_t, 0.2, &"", false);
    elif work:
        _still_t = 0.0;
        var phase:float = fposmod(_anim_t * PawnRig.rate_of(_work_sound()), TAU);
        if _last_phase < 1.5 * PI and phase >= 1.5 * PI:          # the tool comes down
            _strike();
        _last_phase = phase;
        _rig.pose(PawnRig.Mode.WORK, _anim_t, 0.6, _work_sound(), carrying);
    elif eating != &"" and not move:
        _still_t = 0.0;
        _meal_sounds(eating);
        _rig.pose(PawnRig.Mode.EAT if eating == &"eat" else PawnRig.Mode.DRINK, _anim_t, 0.3, &"", false);
    elif move:
        _still_t = 0.0;
        _meal_kind = &"";
        _rig.pose(PawnRig.Mode.WALK, _anim_t, 0.5, &"", carrying, _stride);
    else:
        _meal_kind = &"";
        _still_t += delta * speed;
        var rest:bool = _still_t > SIT_AFTER and is_idle() and not carrying;          # nothing to do for a while: sit down
        _rig.pose(PawnRig.Mode.SIT if rest else PawnRig.Mode.IDLE, _anim_t, 0.25, &"", carrying);

# A foot lands: the sound of the ground underfoot (a bridge or pier deck, wading through shallow water, a road, or grass), soft, and only near the camera.
func _footstep() -> void:
    if indoors or sleeping:
        return;
    Sfx.at(step_sound(), global_position, 0.1, STEP_DB, STEP_REACH, STEP_GAP_MS);

# The sound id of the ground this citizen stands on.
func step_sound() -> StringName:
    var c:Vector2i = cell();
    if world.is_bridge(c):
        return &"step_deck";
    if world.terrain.is_water(c):
        return &"step_wade";
    if Terrain.is_paved(world.terrain.get_overlay(c)):
        return &"step_road";
    return &"step_grass";

# Drinking splashes once, eating crunches a bite at a time (the hand comes up every 1.5 s or so, see PawnRig).
func _meal_sounds(kind:StringName) -> void:
    if kind != _meal_kind:
        _meal_kind = kind;
        _bites = int(_anim_t * 4.2 / TAU);
        if kind == &"drink":
            Sfx.at(&"drink", global_position, 0.08, -8.0, 24.0);
        return;
    var bite:int = int(_anim_t * 4.2 / TAU);
    if kind == &"eat" and bite != _bites:
        _bites = bite;
        Sfx.at(&"eat", global_position, 0.1, -10.0, 20.0, 400);

# The sound of one swing of the tool at what this citizen is working on (see Sfx).
func _strike() -> void:
    var id:StringName = _work_sound();
    if id == &"cast" or id == &"throw":
        id = &"splash";                      # the line and the bucket hit the water
    if id != &"" and id != &"gesture" and id != &"tend":
        Sfx.at(id, global_position);

func _work_sound() -> StringName:
    if task == null:
        return &"";
    if task.kind == &"fire":
        return &"throw";
    match task.job:
        JobManager.Profession.FISHERMAN: return &"cast";
        JobManager.Profession.TEACHER: return &"gesture";
        JobManager.Profession.HEALER: return &"tend";
        JobManager.Profession.HUNTER: return &"rustle";
        JobManager.Profession.BUILDER: return &"hammer";
        JobManager.Profession.FARMER: return &"dig";
        JobManager.Profession.MINER: return &"pick";
        JobManager.Profession.FORAGER: return &"rustle";
        JobManager.Profession.BLACKSMITH: return &"anvil";
        JobManager.Profession.ARTISAN: return &"hammer";
    var t:Variant = task.target;
    if is_instance_valid(t):
        if t is ResourceNode:
            var rn:ResourceNode = t;
            return &"chop" if rn.is_tree() else &"rustle" if rn.is_forageable() else &"pick";
        if t is Building:
            return &"hammer";
    return &"dig" if task.job == JobManager.Profession.WOODCUTTER else &"";

func _build_visual(rng:RandomNumberGenerator) -> void:
    _rig = PawnRig.new();
    add_child(_rig);
    _rig.build(is_male, rng);
    _rig.set_clothing(clothing);
    _idle_mark = Sprite3D.new();
    _idle_mark.texture = UIIcons.texture(&"idle");
    _idle_mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED;
    _idle_mark.pixel_size = 0.02;
    _idle_mark.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR;
    _idle_mark.shaded = false;
    _idle_mark.no_depth_test = true;
    _idle_mark.position = Vector3(0, 1.65, 0);
    _idle_mark.visible = false;
    add_child(_idle_mark);
    _ill_mark = Sprite3D.new();       # a green cross over the sick
    _ill_mark.texture = UIIcons.texture(&"ill");
    _ill_mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED;
    _ill_mark.pixel_size = 0.02;
    _ill_mark.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR;
    _ill_mark.shaded = false;
    _ill_mark.no_depth_test = true;
    _ill_mark.position = Vector3(0, 1.65, 0);
    _ill_mark.visible = false;
    add_child(_ill_mark);
    _rig.set_carry(carry_item, carry_amount);

func _update_carry_visual() -> void:
    _rig.set_carry(carry_item, carry_amount);
