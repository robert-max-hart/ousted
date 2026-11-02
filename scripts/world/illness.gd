# ----------------------------------------------------------------
# Illness
#     Sickness among the citizens. A case is `Pawn.illness`, a severity
#     from 0 (well) to 1 (gravely ill). Cases start by chance (more in
#     the cold, to the hungry and the homeless, and a merchant may bring
#     one in), spread between people who share a home or stand close
#     together, slow work, wear health down, and end in recovery (then a
#     spell of immunity) or death. Rest at home and a healer's visit
#     speed recovery; herbs make the visit far better. The New Game
#     "Illness" rule scales how often it starts and spreads, and the
#     quarantine policy keeps the sick at home and merchants out.
#     The per-citizen part is static (called from Pawn); the colony
#     part runs hourly and daily from World.
# ----------------------------------------------------------------
class_name Illness extends RefCounted;

const ONSET_PER_DAY     :float = 0.003;    # chance a citizen falls ill on a day by themselves (x the Illness rule)
const COLD_ONSET_MULT   :float = 2.0;      # ...when it is freezing
const HUNGRY_ONSET_MULT :float = 2.0;      # ...when they are going hungry
const HEAT_ONSET_MULT  :float = 1.5;       # a citizen worn down by heat falls ill more often
const HOMELESS_ONSET_MULT:float = 1.5;
const MERCHANT_CARRIES  :float = 0.15;     # chance a merchant who arrives brings a case in (x the rule)
const HOME_PER_HOUR     :float = 0.012;    # hourly chance per ill housemate (x severity x rule)
const NEAR_PER_HOUR     :float = 0.004;    # hourly chance per ill person close by (x severity x rule)
const NEAR_RANGE        :float = 2.5;      # metres
const IMMUNE_DAYS       :float = 24.0;
const REST_ABOVE        :float = 0.35;     # this sick and they rest at home
const RECOVER_PER_HOUR  :float = 1.0 / 130.0;
const REST_BONUS        :float = 0.3;      # recovery faster by this much when resting indoors
const CARE_HOURS        :float = 24.0;     # how long one visit's care lasts
const CARE_BASE         :float = 0.25;     # recovery bonus for a visit with no herbs...
const CARE_HERBS        :float = 1.35;     # ...and what herbs add
const DAMAGE_PER_HOUR   :float = 0.02;     # health lost an hour at full severity
const WORSEN_PER_HOUR   :float = 0.004;    # starving or frozen: the illness gets worse
const WORK_SLOWING      :float = 0.5;      # work speed lost at full severity

var world:World;

func _init(w:World) -> void:
    world = w;

# --------------------------------
# One citizen (static, called from Pawn)

static func is_ill(p:Pawn) -> bool:
    return p.illness > 0.0;

static func is_cared_for(p:Pawn) -> bool:
    return p.illness > 0.0 and GameClock.total_hours < p.care_until;

static func work_factor(p:Pawn) -> float:
    return 1.0 - WORK_SLOWING * p.illness;

# Whether the citizen should be resting at home rather than working: gravely ill, or any case under quarantine.
static func must_rest(p:Pawn) -> bool:
    if p.illness <= 0.0 or p.is_baby():
        return false;
    return p.illness >= REST_ABOVE or (p.world.policies.is_on(&"quarantine") and p.illness >= 0.05);

# Called every frame from the citizen's needs with the game hours passed. Returns the health damage per hour of the sickness.
static func tick(p:Pawn, dh:float) -> float:
    if p.illness <= 0.0:
        return 0.0;
    var cared:bool = is_cared_for(p);
    var damage:float = DAMAGE_PER_HOUR * p.illness * (1.0 - (0.5 * p.care_quality if cared else 0.0)) * (0.9 if cared and p.care_quality < 0.5 else 1.0);
    if p.hunger < 0.15 or p.warmth < 0.25:
        p.illness = minf(1.0, p.illness + WORSEN_PER_HOUR * dh);       # no food or warmth: no getting better
        return damage;
    var rate:float = RECOVER_PER_HOUR * (1.0 + (REST_BONUS if p.indoors else 0.0)) * clampf(p.health, 0.3, 1.0);
    if cared:
        rate *= 1.0 + CARE_BASE + CARE_HERBS * p.care_quality;
    if p.age >= Defs.OLD_AGE_EFFICIENCY[0][0]:
        rate *= 0.7;
    p.illness = maxf(0.0, p.illness - rate * dh);
    if p.illness < 0.02:
        _recover(p);
    return damage;

static func _recover(p:Pawn) -> void:
    p.illness = 0.0;
    p.care_until = 0.0;
    p.immune_until = GameClock.total_hours + IMMUNE_DAYS * GameClock.HOURS_PER_DAY;
    p.world.notify("%s has recovered." % p.first_name);

static func describe(p:Pawn) -> String:
    if p.illness <= 0.0:
        if GameClock.total_hours < p.immune_until:
            return "Immune for now after being ill\n";
        return "";
    var word:String = "slightly ill" if p.illness < 0.3 else "ill" if p.illness < 0.6 else "gravely ill";
    var s:String = "Sickness: %s (%d%%)\n" % [word, roundi(p.illness * 100.0)];
    if is_cared_for(p):
        s += "Tended by a healer%s\n" % [" (with herbs)" if p.care_quality >= 0.5 else " (no herbs)"];
    elif must_rest(p):
        s += "Resting at home\n";
    return s;

# --------------------------------
# The colony

func ill_count() -> int:
    var n:int = 0;
    for p in world.pawns:
        if p.illness > 0.0:
            n += 1;
    return n;

func can_catch(p:Pawn) -> bool:
    return p.illness <= 0.0 and GameClock.total_hours >= p.immune_until;

# Makes a citizen ill, at a severity that depends on age and how well they are. Returns whether it took.
func infect(p:Pawn, spread:bool = false) -> bool:
    if not can_catch(p):
        return false;
    var s:float = world.rng.randf_range(0.25, 0.6) if spread else world.rng.randf_range(0.3, 0.7);
    if p.is_baby() or not p.is_adult() or p.age >= Defs.OLD_AGE_EFFICIENCY[0][0]:
        s += 0.15;
    if p.hunger < 0.3 or p.warmth < 0.3:
        s += 0.1;
    p.illness = clampf(s, 0.2, 1.0);
    p.care_until = 0.0;
    return true;

# Hourly: the ill pass it on to those at home with them or close by.
func on_hour() -> void:
    var share:float = GameRules.illness_share();
    if share <= 0.0:
        return;
    for a in world.pawns:
        if a.illness <= 0.0:
            continue;
        for b in world.pawns:
            if b == a or not can_catch(b):
                continue;
            var chance:float = 0.0;
            if a.home != null and a.home == b.home:
                chance += HOME_PER_HOUR;
            if a.indoors == b.indoors and not a.indoors and Vector2(a.position.x - b.position.x, a.position.z - b.position.z).length() <= NEAR_RANGE:
                chance += NEAR_PER_HOUR;
            elif a.indoors and b.indoors and is_same(a.shelter, b.shelter):
                chance += NEAR_PER_HOUR;
            if chance > 0.0 and world.rng.randf() < chance * a.illness * share * a.clean_factor() * b.clean_factor():
                if infect(b, true):
                    world.notify("%s has caught the sickness." % b.first_name);

# Daily: chance cases start by themselves.
func on_day() -> void:
    var share:float = GameRules.illness_share();
    if share <= 0.0:
        return;
    var before:int = ill_count();
    for p in world.pawns:
        if not can_catch(p):
            continue;
        var chance:float = onset_chance(p);
        if world.rng.randf() < chance and infect(p):
            world.notify("%s has fallen ill." % p.first_name);
    if before == 0 and ill_count() > 0:
        world.notify("Sickness has started in the colony. Rest, food, warmth and a healer help; the Policies panel has a quarantine rule.");

# The chance that this citizen falls ill on a day, by itself: more in the cold, when hungry, worn down by heat, or with no home.
func onset_chance(p:Pawn) -> float:
    var chance:float = ONSET_PER_DAY * GameRules.illness_share();
    if Weather.temperature < 2.0:
        chance *= COLD_ONSET_MULT;
    if p.hunger < 0.3:
        chance *= HUNGRY_ONSET_MULT;
    if p.overheat >= 0.5:
        chance *= HEAT_ONSET_MULT;
    if p.home == null:
        chance *= HOMELESS_ONSET_MULT;
    return chance * p.clean_factor();

# A merchant reaches the Trading Post: they may carry a sickness in.
func on_merchant_arrival() -> void:
    var share:float = GameRules.illness_share();
    if share <= 0.0 or world.pawns.is_empty() or world.rng.randf() >= minf(1.0, MERCHANT_CARRIES * share):
        return;
    var p:Pawn = world.pawns[world.rng.randi() % world.pawns.size()];
    if infect(p):
        world.notify("%s has fallen ill after dealing with the merchant." % p.first_name);
