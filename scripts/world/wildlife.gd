# ----------------------------------------------------------------
# Wildlife
#     The big game of the woods, kept as a hidden number per region of
#     the map (nothing is drawn). A region holds deer in proportion to
#     its mature trees and the climate (Climate.game_share); hunting
#     takes them out one at a time, and they breed back slowly, fastest
#     at about half the region's capacity. Hunting lodges whose circles
#     cover the same regions share them.
# ----------------------------------------------------------------
class_name Wildlife extends RefCounted;

const REGION          :int = 12;          # cells a side
const PER_TREE        :float = 0.1;       # deer a region holds for each mature tree
const START_SHARE     :float = 0.8;       # of the capacity, in a new world
const BREED_PER_DAY   :float = 0.12;      # logistic growth rate
const DRIFT_PER_DAY   :float = 0.01;      # of the capacity: deer wandering in from beyond the map keep a hunted-out region from staying empty
const MIN_CAPACITY    :float = 2.0;       # a circle of woods holding fewer deer than this has no game worth the trip

var world:World;
var cols:int = 1;
var cap :PackedFloat32Array = PackedFloat32Array();
var level:PackedFloat32Array = PackedFloat32Array();
var _known:bool = false;

func _init(w:World) -> void:
    world = w;
    cols = ceili(float(Terrain.SIZE) / float(REGION));
    cap.resize(cols * cols);
    level.resize(cols * cols);

func region_of(c:Vector2i) -> int:
    return clampi(c.y / REGION, 0, cols - 1) * cols + clampi(c.x / REGION, 0, cols - 1);

func region_center(r:int) -> Vector2:
    return Vector2((r % cols + 0.5) * REGION, (r / cols + 0.5) * REGION);

# Counts the mature trees again and sets each region's capacity; the first time, fills the regions to START_SHARE.
func refresh() -> void:
    cap.fill(0.0);
    var share:float = Climate.game_share() * PER_TREE;
    for rn in world.nodes:
        if rn.is_tree() and rn.is_mature() and not rn.removed:
            cap[region_of(rn.cell)] += share;
    for i in cap.size():
        if not _known:
            level[i] = cap[i] * START_SHARE;
        level[i] = minf(level[i], cap[i]);
    _known = true;

func ensure() -> void:
    if not _known:
        refresh();

func on_day() -> void:
    refresh();
    for i in cap.size():
        if cap[i] <= 0.0:
            continue;
        var l:float = level[i];
        l += BREED_PER_DAY * l * (1.0 - l / cap[i]) + DRIFT_PER_DAY * cap[i] * (1.0 - l / cap[i]);
        level[i] = clampf(l, 0.0, cap[i]);

# How much of each region a circle of woods covers, as {region: weight 0..1} (a region counts fully when its middle is
# well inside the circle and not at all when it is a half region outside).
func covered(center:Vector2, radius:float) -> Dictionary:
    var out:Dictionary = {};
    for r in cap.size():
        if cap[r] <= 0.0:
            continue;
        var w:float = clampf((radius + REGION * 0.5 - region_center(r).distance_to(center)) / REGION, 0.0, 1.0);
        if w > 0.0:
            out[r] = w;
    return out;

# {"cap": deer the circle can hold, "have": deer in it now}.
func totals(center:Vector2, radius:float) -> Dictionary:
    ensure();
    var c:float = 0.0;
    var h:float = 0.0;
    var cov:Dictionary = covered(center, radius);
    for r in cov:
        c += cap[r] * cov[r];
        h += level[r] * cov[r];
    return {"cap": c, "have": h};

# 0 to 1: how full the circle's woods are of game (0 when there are too few woods to bother).
func density(center:Vector2, radius:float) -> float:
    var t:Dictionary = totals(center, radius);
    return 0.0 if t["cap"] < MIN_CAPACITY else clampf(t["have"] / t["cap"], 0.0, 1.0);

# A word for the inspector.
func rating(center:Vector2, radius:float) -> String:
    var t:Dictionary = totals(center, radius);
    if t["cap"] < MIN_CAPACITY:
        return "None: too few woods";
    var d:float = density(center, radius);
    if d >= 0.6:
        return "Plentiful";
    if d >= 0.35:
        return "Fair";
    return "Thin" if d >= 0.15 else "Scarce";

# Takes one deer from the fullest region the circle covers; false when there is none worth taking.
func take(center:Vector2, radius:float) -> bool:
    ensure();
    var best:int = -1;
    var most:float = 0.9;
    var cov:Dictionary = covered(center, radius);
    for r in cov:
        if level[r] * cov[r] > most:
            most = level[r] * cov[r];
            best = r;
    if best < 0:
        return false;
    level[best] = maxf(0.0, level[best] - 1.0);
    return true;

func to_array() -> Array:
    return Array(level);

func restore(a:Array) -> void:
    if a.size() != level.size():
        return;           # (an older save or another map size: start again)
    for i in a.size():
        level[i] = float(a[i]);
    _known = false;
    var saved:PackedFloat32Array = level.duplicate();
    refresh();
    for i in saved.size():
        level[i] = minf(saved[i], cap[i]);
