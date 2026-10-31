# ----------------------------------------------------------------
# FishingHut
#     A hut on stilts built partly over the water. Fishermen work from
#     it and bring fish to storage. The hut fishes the water inside its
#     radius: the larger the share of that circle that is water, the
#     faster they catch, and water that another fishing hut's circle
#     also covers is fished out between them, which cuts the catch of
#     both. Fish are unlimited: only the water around the hut counts.
# ----------------------------------------------------------------
class_name FishingHut extends Building;

const BASE_CATCH    :float = 1.5;       # fish per work-hour when the whole circle is water and no other hut shares it (the catch grows with the square root of the water share: a river hut is not nearly useless)
const OVERLAP_COST  :float = 0.6;       # share of the catch lost when all of the hut's water is shared with other huts

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

func info_text() -> String:
    if state != State.COMPLETE:
        return super.info_text();
    var s:String = "Water in the fishing circle: %d%%\n" % roundi(water_share() * 100.0);
    if overlap() > 0.005:
        s += "Shared with other fishing huts: %d%% of the water\n" % roundi(overlap() * 100.0);
    s += "Catch: about %.1f fish for each hour of work\n" % catch_rate();
    return s + super.info_text();

func help_text() -> String:
    return super.help_text() + "\nThe more of the circle is water, the better the catch. Water that another fishing hut's circle also covers is shared, and both huts catch less, so space huts apart along the shore.";
