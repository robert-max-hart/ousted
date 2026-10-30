# ----------------------------------------------------------------
# Apiary
#     A small yard of beehives. In warm weather the bees make honey,
#     more of it the more flowering things grow nearby: berry bushes,
#     hazel groves and fruit trees in an orchard. Farmers collect the
#     honey (HerdTasks) and carry it to storage. Honey never spoils;
#     it is mostly a trade good.
# ----------------------------------------------------------------
class_name Apiary extends Building;

const ACTIVE_ABOVE :float = 10.0;      # C, daily mean: colder than this the bees stay in the hive
const BASE_RATE    :float = 0.08;      # honey a day with no blossom nearby
const BLOOM_RATE   :float = 0.05;      # more a day for each unit of bloom
const BLOOM_CAP    :float = 16.0;      # bloom beyond this adds nothing
const ORCHARD_TREES:float = 4.0;       # planted orchard trees that count as one unit of bloom
const COLLECT_AT   :int = 3;           # honey ready before a farmer is sent
const READY_CAP    :int = 30;

var honey_acc   :float = 0.0;
var ready_honey :int = 0;
var claimed     :bool = false;         # a citizen is on the way to collect (not saved)
var bloom       :float = 0.0;          # last day's count of flowering things in range (for the inspector)

func work_radius() -> float:
    return def.get("radius", 12.0);

func active() -> bool:
    return is_complete() and Weather.mean_temperature() >= ACTIVE_ABOVE;

# Units of bloom in range: a bush or a hazel grove is one each (bare bushes too, they flower), four orchard trees are one.
func count_bloom() -> float:
    var c:Vector2 = Vector2(center_cell());
    var r2:float = work_radius() * work_radius();
    var n:float = 0.0;
    for rn in world.nodes:
        if (rn.kind == &"bush" or rn.kind == &"hazel") and Vector2(rn.cell).distance_squared_to(c) <= r2:
            n += 1.0;
    for b in world.buildings:
        if b is Field and b.is_complete() and (b as Field).is_orchard() and Vector2(b.center_cell()).distance_squared_to(c) <= r2:
            var trees:int = 0;
            for i in (b as Field).plot_state.size():
                if (b as Field).plot_state[i] != Field.Plot.FALLOW and (b as Field).plot_state[i] != Field.Plot.DEAD:
                    trees += 1;
            n += trees / ORCHARD_TREES;
    return n;

func on_day() -> void:
    super.on_day();
    if not active():
        return;
    bloom = count_bloom();
    honey_acc += BASE_RATE + BLOOM_RATE * minf(bloom, BLOOM_CAP);
    var h:int = floori(honey_acc);
    honey_acc -= h;
    ready_honey = mini(READY_CAP, ready_honey + h);

# {"item": honey, "n": units ready}, or {} when there is not enough yet.
func collectable() -> Dictionary:
    if is_complete() and ready_honey >= COLLECT_AT:
        return {"item": &"honey", "n": ready_honey};
    return {};

func take_ready(_item:StringName, n:int) -> int:
    var k:int = mini(n, ready_honey);
    ready_honey -= k;
    return k;

func to_dict() -> Dictionary:
    var d:Dictionary = super.to_dict();
    d["honey_acc"] = honey_acc;
    d["ready_honey"] = ready_honey;
    return d;

func restore_dict(d:Dictionary) -> void:
    super.restore_dict(d);
    honey_acc = d.get("honey_acc", 0.0);
    ready_honey = d.get("ready_honey", 0);

func info_text() -> String:
    if state != State.COMPLETE:
        return super.info_text();
    var s:String = "Honey ready: %d\n" % ready_honey;
    if not active():
        return s + "The bees are in the hive: too cold.\n";
    return s + "Blossom in range: %.1f (about %.2f honey a day)\n" % [bloom, BASE_RATE + BLOOM_RATE * minf(bloom, BLOOM_CAP)];

func help_text() -> String:
    return super.help_text() + "\nBees only work when the daily mean is above %d C. Honey does not spoil and trades well, so a merchant will pay a good price for it." % int(ACTIVE_ABOVE);
