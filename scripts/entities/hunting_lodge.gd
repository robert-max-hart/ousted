# ----------------------------------------------------------------
# HuntingLodge
#     A lodge at the edge of the woods. Hunters go out among the trees,
#     bring down a deer (the game of the woods around it is limited, see
#     Wildlife), skin it and carry the meat and leather back to the
#     lodge, which is a small store for both. Skinning is quick with an
#     iron or steel tool and slow without one. With the Snares upgrade
#     the lodge also takes rabbits by itself, a few a day, which fill
#     its store without anyone's help.
# ----------------------------------------------------------------
class_name HuntingLodge extends Building;

const HUNT_BASE      :float = 0.05;      # deer per work-hour with the woods as full as a new world's
const FULL_AT        :float = 0.8;       # the density at which hunting runs at the base rate
const SNOW_SLOWS     :float = 0.5;       # share of the hunting rate lost in full snow
const SKIN_HOURS     :float = 1.5;
const SKIN_TOOL_BONUS:float = 0.25;      # the tool bonus (iron) for skinning at full speed
const SKIN_UNTOOLED  :float = 0.4;       # the speed without one
const DEER_MEAT      :int = 5;
const DEER_LEATHER   :int = 2;

const SNARE_BASE     :float = 2.0;       # rabbits a day with the circle well wooded and no other lodge sharing it
const SNARE_WOODED   :float = 0.15;      # trees per cell of the circle that count as well wooded
const SNARE_SNOW     :float = 0.7;       # snow depth above which the snares are buried
const SNARE_OVERLAP  :float = 0.5;       # share of the catch lost for each other lodge whose circle reaches this one
const RABBIT_MEAT    :int = 1;
const PELTS_PER_LEATHER:int = 3;

var snare_acc :float = 0.0;
var pelt_acc  :int = 0;
var _trees    :int = 0;                  # mature trees in the circle (counted daily and when asked first)
var _counted  :bool = false;

func work_radius() -> float:
    return def.get("radius", 16.0);

func circle_center() -> Vector2:
    return Vector2(center_cell());

# --------------------------------
# Hunting

# Deer per work-hour right now (0 when there is no game worth the trip).
func hunt_rate() -> float:
    var d:float = world.wildlife.density(circle_center(), work_radius());
    return HUNT_BASE * clampf(d / FULL_AT, 0.0, 1.0) * (1.0 - SNOW_SLOWS * Weather.snow_depth);

# How fast a hunter skins at: full with an iron or steel tool (a tool bonus of at least SKIN_TOOL_BONUS), slowly without.
static func skin_speed(tool_bonus:float) -> float:
    return 1.0 if tool_bonus >= SKIN_TOOL_BONUS - 0.001 else SKIN_UNTOOLED;

# A cell among the mature trees in the circle to go and hunt at (varies with the hunter and the hour), or (-1, -1).
func hunt_spot(salt:int) -> Vector2i:
    var spots:Array[Vector2i] = [];
    var c:Vector2 = circle_center();
    for rn in world.nodes:
        if rn.is_tree() and rn.is_mature() and not rn.removed and Vector2(rn.cell).distance_to(c) <= work_radius():
            var free:Vector2i = _free_next_to(rn.cell);
            if free.x >= 0:
                spots.append(free);
    if spots.is_empty():
        return Vector2i(-1, -1);
    return spots[absi(hash(Vector2i(salt, GameClock.total_hours as int))) % spots.size()];

func _free_next_to(cell:Vector2i) -> Vector2i:
    for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
        var n:Vector2i = cell + d;
        if world.terrain.in_bounds(n) and not world.terrain.is_water(n) and world.occupant[world.idx(n)] == null and world.node_at[world.idx(n)] == null:
            return n;
    return Vector2i(-1, -1);

# --------------------------------
# Snares

func has_snares() -> bool:
    return is_complete() and has_upgrade(&"snares");

func _neighbours() -> int:
    var n:int = 0;
    for b in world.buildings:
        if b is HuntingLodge and b != self and not b.removed and (b as HuntingLodge).has_snares() \
                and Vector2(b.center_cell()).distance_to(Vector2(center_cell())) < work_radius() + (b as HuntingLodge).work_radius():
            n += 1;
    return n;

func _count_trees() -> void:
    _trees = 0;
    var c:Vector2 = circle_center();
    for rn in world.nodes:
        if rn.is_tree() and rn.is_mature() and not rn.removed and Vector2(rn.cell).distance_to(c) <= work_radius():
            _trees += 1;
    _counted = true;

# 0 to 1: how wooded the circle is for the snares.
func wooded() -> float:
    if not _counted:
        _count_trees();
    var area:float = PI * work_radius() * work_radius();
    return clampf(float(_trees) / (area * SNARE_WOODED), 0.0, 1.0);

# Rabbits a day right now (0 when snow has buried the snares).
func snare_rate() -> float:
    if not has_snares() or Weather.snow_depth > SNARE_SNOW:
        return 0.0;
    return SNARE_BASE * sqrt(wooded()) * maxf(0.0, 1.0 - SNARE_OVERLAP * _neighbours());

func on_day() -> void:
    super.on_day();
    _count_trees();
    var rate:float = snare_rate();
    if rate <= 0.0:
        return;
    snare_acc = minf(snare_acc + rate, 8.0);          # (when the store is full the catch waits, but not for long)
    var n:int = floori(snare_acc);
    if n <= 0:
        return;
    var put:int = store(&"meat", n * RABBIT_MEAT);
    snare_acc -= float(put) / float(RABBIT_MEAT);
    pelt_acc += put / RABBIT_MEAT;
    var pelts:int = pelt_acc / PELTS_PER_LEATHER;
    if pelts > 0:
        pelt_acc -= store(&"leather", pelts) * PELTS_PER_LEATHER;

# Three small wire snares on stakes beside the lodge.
func on_upgrade_done(id:StringName) -> void:
    if id != &"snares" or _snares_shown:
        return;
    _snares_shown = true;
    var stake:CylinderMesh = CylinderMesh.new();
    stake.top_radius = 0.04;
    stake.bottom_radius = 0.05;
    stake.height = 0.5;
    for k in 3:
        add_decor(stake, _flat_mat(Color(0.5, 0.38, 0.24)), Vector3(float(vsize.x) * 0.5 - 0.35 - k * 0.3, 0.25, float(vsize.y) * 0.5 - 0.2 - (0.1 if k == 1 else 0.0)));

var _snares_shown:bool = false;

func to_dict() -> Dictionary:
    var d:Dictionary = super.to_dict();
    d["snare_acc"] = snare_acc;
    d["pelt_acc"] = pelt_acc;
    return d;

func restore_dict(d:Dictionary) -> void:
    super.restore_dict(d);
    snare_acc = d.get("snare_acc", 0.0);
    pelt_acc = d.get("pelt_acc", 0);
    if has_upgrade(&"snares"):
        on_upgrade_done(&"snares");

func info_text() -> String:
    if state != State.COMPLETE:
        return super.info_text();
    var s:String = "Game in the woods: %s\n" % world.wildlife.rating(circle_center(), work_radius());
    s += "Hunting: about %.1f deer for each 10 hours of work (%d meat and %d leather each)\n" % [hunt_rate() * 10.0, DEER_MEAT, DEER_LEATHER];
    if has_snares():
        s += "Snares: about %.1f rabbits a day%s\n" % [snare_rate(), "" if snare_rate() > 0.0 else " (buried in snow)"];
    return s + super.info_text();

func help_text() -> String:
    return super.help_text() + "\nThe game is limited: each deer taken is gone until the woods breed more, so hunt where the woods are thick and keep lodges apart. A hunter without an iron or steel tool skins slowly.";
