# ----------------------------------------------------------------
# FishingHut
#     A hut on stilts built partly over the water. Fishermen work from
#     it and bring fish to storage. The hut fishes the water inside its
#     radius: the larger the share of that circle that is water, the
#     faster they catch, and water that another fishing hut's circle
#     also covers is fished out between them, which cuts the catch of
#     both. Fish are unlimited: only the water around the hut counts.
#     With the Crab Pots upgrade the hut also fills pots by itself, a few
#     crabs a day (the same water rules), which a farmer collects like
#     honey from a hive (HerdTasks).
# ----------------------------------------------------------------
class_name FishingHut extends Building;

const BASE_CATCH    :float = 1.5;       # fish per work-hour when the whole circle is water and no other hut shares it (the catch grows with the square root of the water share: a river hut is not nearly useless)
const OVERLAP_COST  :float = 0.6;       # share of the catch lost when all of the hut's water is shared with other huts

const CRAB_BASE     :float = 1.4;       # crabs a day with the whole circle water and no other hut sharing it
const CRAB_COLLECT_AT:int = 3;          # crabs ready before a farmer is sent
const CRAB_CAP      :int = 30;
const CRAB_ABOVE    :float = 0.0;       # C, daily mean: the water freezes over below this and the pots lie idle

var crab_acc    :float = 0.0;
var ready_crabs :int = 0;
var claimed     :bool = false;          # a citizen is on the way to collect (not saved)
var _share_key  :String = "";           # what the cached numbers were worked out for
var _water_share:float = 0.0;
var _overlap    :float = 0.0;

func work_radius() -> float:
    return def.get("radius", 9.0);

# The cells of the hut's circle that are on the map.
func _disc() -> Array[Vector2i]:
    var out:Array[Vector2i] = [];
    var c:Vector2 = center_cell();
    var r:float = work_radius();
    for z in range(floori(c.y - r), ceili(c.y + r) + 1):
        for x in range(floori(c.x - r), ceili(c.x + r) + 1):
            var cell:Vector2i = Vector2i(x, z);
            if world.terrain.in_bounds(cell) and Vector2(cell).distance_to(c - Vector2(0.5, 0.5)) <= r:
                out.append(cell);
    return out;

# Other finished (or building) fishing huts whose circles reach this one.
func _neighbours() -> Array[FishingHut]:
    var out:Array[FishingHut] = [];
    for b in world.buildings:
        if b is FishingHut and b != self and not b.removed and Vector2(b.center_cell()).distance_to(Vector2(center_cell())) < work_radius() + (b as FishingHut).work_radius():
            out.append(b as FishingHut);
    return out;

# Works out the water share and the overlap (cached until a fishing hut appears or goes).
func _measure() -> void:
    var others:Array[FishingHut] = _neighbours();
    var key:String = "%s|%s" % [origin, ",".join(others.map(func(o:FishingHut) -> String: return str(o.origin)))];
    if key == _share_key:
        return;
    _share_key = key;
    var disc:Array[Vector2i] = _disc();
    var wet:int = 0;
    var shared:int = 0;
    for cell in disc:
        if not world.terrain.is_water(cell):
            continue;
        wet += 1;
        for o in others:
            if Vector2(cell).distance_to(Vector2(o.center_cell()) - Vector2(0.5, 0.5)) <= o.work_radius():
                shared += 1;
                break;
    _water_share = float(wet) / float(maxi(1, disc.size()));
    _overlap = float(shared) / float(maxi(1, wet));

# Share of the hut's circle that is water, 0 to 1.
func water_share() -> float:
    _measure();
    return _water_share;

# Share of the hut's water that other fishing huts' circles also cover, 0 to 1.
func overlap() -> float:
    _measure();
    return _overlap;

# Fish caught per work-hour right now.
func catch_rate() -> float:
    return BASE_CATCH * sqrt(water_share()) * (1.0 - OVERLAP_COST * overlap());

# --------------------------------
# Crab pots

func has_pots() -> bool:
    return is_complete() and has_upgrade(&"crab_pots");

# Crabs a day the pots bring in right now (0 when the water is frozen).
func crab_rate() -> float:
    if not has_pots() or Weather.mean_temperature() < CRAB_ABOVE:
        return 0.0;
    return CRAB_BASE * sqrt(water_share()) * (1.0 - OVERLAP_COST * overlap());

func on_day() -> void:
    super.on_day();
    var rate:float = crab_rate();
    if rate <= 0.0:
        return;
    crab_acc += rate;
    var n:int = floori(crab_acc);
    crab_acc -= n;
    ready_crabs = mini(CRAB_CAP, ready_crabs + n);

# {"item": crabs, "n": units ready}, or {} when there are not enough yet.
func collectable() -> Dictionary:
    if has_pots() and ready_crabs >= CRAB_COLLECT_AT:
        return {"item": &"crabs", "n": ready_crabs};
    return {};

func take_ready(_item:StringName, n:int) -> int:
    var k:int = mini(n, ready_crabs);
    ready_crabs -= k;
    return k;

# Three iron-bound pots on the end of the pier.
func on_upgrade_done(id:StringName) -> void:
    if id != &"crab_pots" or _pots_shown:
        return;
    _pots_shown = true;
    var pot:BoxMesh = BoxMesh.new();
    pot.size = Vector3(0.34, 0.26, 0.34);
    var at_z:float = -float(vsize.y) * 0.5 + 0.35;
    for k in 3:
        add_decor(pot, _flat_mat(Color(0.3, 0.3, 0.33)), Vector3((k - 1) * 0.8, DECK_HEIGHT + 0.18, at_z - (0.18 if k == 1 else 0.0)));

var _pots_shown :bool = false;

func to_dict() -> Dictionary:
    var d:Dictionary = super.to_dict();
    d["crab_acc"] = crab_acc;
    d["ready_crabs"] = ready_crabs;
    return d;

func restore_dict(d:Dictionary) -> void:
    super.restore_dict(d);
    crab_acc = d.get("crab_acc", 0.0);
    ready_crabs = d.get("ready_crabs", 0);
    if has_upgrade(&"crab_pots"):
        on_upgrade_done(&"crab_pots");

func info_text() -> String:
    if state != State.COMPLETE:
        return super.info_text();
    var s:String = "Water in the fishing circle: %d%%\n" % roundi(water_share() * 100.0);
    if overlap() > 0.005:
        s += "Shared with other fishing huts: %d%% of the water\n" % roundi(overlap() * 100.0);
    s += "Catch: about %.1f fish for each hour of work\n" % catch_rate();
    if has_pots():
        s += "Crabs ready: %d (about %.1f a day%s)\n" % [ready_crabs, crab_rate(), "" if crab_rate() > 0.0 else ": the water is frozen"];
    return s + super.info_text();

func help_text() -> String:
    return super.help_text() + "\nThe more of the circle is water, the better the catch. Water that another fishing hut's circle also covers is shared, and both huts catch less, so space huts apart along the shore.";
