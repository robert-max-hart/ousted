# ----------------------------------------------------------------
# Heat
#     Overheating: the other half of keeping warm. In hot weather a
#     citizen's heat load (Pawn.overheat, 0 comfortable to 1 heatstroke)
#     builds outdoors, faster the hotter it is, in warm clothes, when
#     thirsty and for the very young and old, and falls in shade (indoors,
#     under a tree, by water or a well). Heat makes them thirstier, slows
#     their work, sours their mood and at the extreme hurts their health.
#     A citizen who is too hot goes to cool off (NeedsTasks.cool_task),
#     and in the worst of the midday heat everyone with a home rests
#     indoors unless the policy "Work through the heat" is on. Static
#     helpers that take the citizen, like Illness.
# ----------------------------------------------------------------
class_name Heat extends RefCounted;

const FROM            :float = 28.0;      # C: it starts to tell above this
const LOAD_PER_DEGREE :float = 0.012;     # heat load an hour per degree over FROM, outdoors in light clothes
const COOL_PER_HOUR   :float = 0.15;      # lost an hour in shade (less in extreme heat), and anywhere once it is cooler
const CLOTHES_LOAD    :float = 0.6;       # warm clothes (their warmth, 0 to 1) add this share to the load
const THIRST_LOAD     :float = 0.5;       # a thirsty citizen (empty) takes this much more
const VULNERABLE      :float = 1.5;       # babies and the old take this much more
const OLD_FROM        :float = 65.0;
const SEEK_SHADE      :float = 0.55;      # a citizen this hot goes to cool off
const CRITICAL        :float = 0.8;       # ... and drops what they are doing from here
const SHADE_UNTIL     :float = 0.2;       # ... and stays until they are this cool
const WORK_LOSS       :float = 0.5;       # work speed lost at full heat load (from 0.3 up)
const THIRST_EXTRA    :float = 1.0;       # thirst drains this much faster at full heat load
const DAMAGE_FROM     :float = 0.8;       # health suffers from here: up to 1/20 an hour at full heat load
const MOOD_LOSS       :float = 0.25;
const SIESTA_FROM     :float = 11.0;      # hours of the day when, in the worst heat, everyone with a home rests indoors
const SIESTA_TO       :float = 17.0;
const SIESTA_TEMP     :float = 38.0;
const TREE_SHADE      :int = 1;           # cells: shade from a tree reaches this far
const WATER_COOL      :int = 2;           # cells to open water, and to a well within WELL_COOL
const WELL_COOL       :int = 3;

# One hour step of a citizen's heat; returns the health damage an hour it adds.
static func tick(p:Pawn, dh:float) -> float:
    var hot:float = maxf(0.0, Weather.temperature - FROM);
    if hot > 0.0 and not cooling_spot(p):
        var load:float = hot * LOAD_PER_DEGREE * (1.0 + p.cold_resist() * CLOTHES_LOAD) * (1.0 + (1.0 - p.thirst) * THIRST_LOAD);
        if p.is_baby() or p.age >= OLD_FROM:
            load *= VULNERABLE;
        p.overheat = minf(1.0, p.overheat + load * dh);
    else:
        var rate:float = COOL_PER_HOUR * (1.0 - minf(1.0, hot / 16.0) * 0.5);          # shade helps less in a furnace
        p.overheat = maxf(0.0, p.overheat - rate * dh);
    if p.overheat > DAMAGE_FROM:
        return (p.overheat - DAMAGE_FROM) / (1.0 - DAMAGE_FROM) / 20.0;
    return 0.0;

# Whether the citizen stands somewhere they can cool: indoors, by a tree, by open water or by a well.
static func cooling_spot(p:Pawn) -> bool:
    if p.indoors:
        return true;
    var w:World = p.world;
    var c:Vector2i = p.cell();
    for dz in range(-TREE_SHADE, TREE_SHADE + 1):
        for dx in range(-TREE_SHADE, TREE_SHADE + 1):
            var n:Vector2i = c + Vector2i(dx, dz);
            if w.terrain.in_bounds(n):
                var rn:ResourceNode = w.node_at[w.idx(n)];
                if rn != null and rn.is_tree():
                    return true;
    for dz in range(-WATER_COOL, WATER_COOL + 1):
        for dx in range(-WATER_COOL, WATER_COOL + 1):
            var n:Vector2i = c + Vector2i(dx, dz);
            if w.terrain.in_bounds(n) and w.terrain.is_water(n):
                return true;
    for b in w.buildings:
        if b.def.get("water", false) and b.is_complete() and b.rect().grow(WELL_COOL).has_point(c):
            return true;
    return false;

# The work speed that is left after the heat (1 when comfortable).
static func work_factor(p:Pawn) -> float:
    return 1.0 - WORK_LOSS * clampf((p.overheat - 0.3) / 0.7, 0.0, 1.0);

# How much faster thirst drains for the heat.
static func thirst_mult(p:Pawn) -> float:
    return 1.0 + THIRST_EXTRA * p.overheat;

# The mood cost of being too hot (0 when comfortable).
static func mood_loss(p:Pawn) -> float:
    return MOOD_LOSS * clampf((p.overheat - 0.3) / 0.7, 0.0, 1.0);

# The worst of the midday heat: everyone with a home goes indoors for it, unless the rule says to work on.
static func siesta_due(p:Pawn) -> bool:
    if Weather.temperature < SIESTA_TEMP or p.world.policies.is_on(&"heat_work"):
        return false;
    var h:float = GameClock.hour();
    return h >= SIESTA_FROM and h < SIESTA_TO and p.world.shelter_for(p) != null;

# A line for the inspector: how they are in the heat.
static func describe(p:Pawn) -> String:
    if p.overheat < 0.05 and Weather.temperature < FROM:
        return "";
    return "Coolness %s\n" % p._bar(1.0 - p.overheat);
