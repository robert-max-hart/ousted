# ----------------------------------------------------------------
# Seeds
#     Which crops the colony can sow. The difficulty decides the
#     starting seeds (Defs.DIFFICULTIES); the rest are found by
#     foragers and gatherers picking wild food (a trader will be
#     another source later). A found seed stays known for good.
#     Saved as a list of crop ids; a save without one (made before
#     seeds) knows every crop.
# ----------------------------------------------------------------
class_name Seeds extends RefCounted;

const FIND_CHANCE     :float = 0.002;  # per finished foraging trip: a small bonus, the trader is meant to be the main source (see tests/seed_probe)
const IN_SEASON_WEIGHT:float = 3.0;    # a crop that can be sown right now is this much likelier to be found

var known:Dictionary = {};     # crop id -> true
var trips:int = 0;             # foraging trips finished so far (a statistic for tuning FIND_CHANCE; not saved)

func _init() -> void:
    for id in Defs.DIFFICULTIES[Defs.difficulty]["seeds"]:
        known[id] = true;

func has(crop:StringName) -> bool:
    return known.has(crop);

# The first known crop in the order of Defs.CROPS (a new field's crop).
func first_known() -> StringName:
    for id in Defs.CROPS:
        if known.has(id):
            return id;
    return &"wheat";

func locked() -> Array[StringName]:
    var out:Array[StringName] = [];
    for id in Defs.CROPS:
        if not known.has(id):
            out.append(id);
    return out;

func unlock(crop:StringName) -> void:
    known[crop] = true;

func unlock_all() -> void:
    for id in Defs.CROPS:
        known[id] = true;

func names() -> String:
    var parts:PackedStringArray = [];
    for id in Defs.CROPS:
        if known.has(id):
            parts.append(Defs.CROPS[id]["name"]);
    return ", ".join(parts);

# Called when a citizen finishes a trip picking wild food. Returns the crop found, or &"".
func on_forage(world:World, chance:float = FIND_CHANCE) -> StringName:
    trips += 1;
    var left:Array[StringName] = locked();
    if left.is_empty() or world.rng.randf() >= chance:
        return &"";
    var season:int = GameClock.season();
    var weights:Array[float] = [];
    var total:float = 0.0;
    for id in left:
        var c:Dictionary = Defs.CROPS[id];
        var w:float = c.get("find_weight", 1.0) * (IN_SEASON_WEIGHT if (c["sow"] as Array).has(season) else 1.0);
        weights.append(w);
        total += w;
    var roll:float = world.rng.randf() * total;
    var pick:StringName = left[left.size() - 1];
    for i in left.size():
        roll -= weights[i];
        if roll <= 0.0:
            pick = left[i];
            break;
    unlock(pick);
    world.notify("Foragers found %s seeds. Fields can now be sown with %s." % [Defs.CROPS[pick]["name"].to_lower(), Defs.CROPS[pick]["name"].to_lower()]);
    return pick;

func to_array() -> Array:
    return known.keys();

# null (a save from before seeds) knows every crop.
func restore(data:Variant) -> void:
    known.clear();
    if data == null:
        unlock_all();
        return;
    for id in data:
        known[StringName(id)] = true;
