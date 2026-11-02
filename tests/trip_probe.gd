# ----------------------------------------------------------------
# Trip probe (not pass/fail): how far citizens walk for each kind of
# task over a soak run (the same colony as sim_soak): meals and drinks
# and the like against hauling, and how far a meal trip is. Answers
# whether hauling goods to a central market could save any walking.
#     godot --headless --path . --fixed-fps 60 res://tests/trip_probe.tscn -- 16
# ----------------------------------------------------------------
extends Node;

const NEEDS:Array[StringName] = [&"eat", &"drink", &"warm", &"camp", &"equip", &"cool"];
const LOGISTICS:Array[StringName] = [&"haul", &"deliver", &"collect", &"fuel", &"supply", &"rebalance"];

var soak:Node;
var _last_pos:Dictionary = {};          # Pawn -> position
var _last_task:Dictionary = {};         # Pawn -> Task
var dist:Dictionary = {};               # kind -> metres walked
var starts:Dictionary = {};             # kind -> tasks begun
var meal_trip_sum:float = 0.0;          # straight-line metres from where a meal task began to the store it goes to
var meal_trips:int = 0;
var _printed_day:int = -1;

func _ready() -> void:
    soak = (load("res://tests/sim_soak.gd") as GDScript).new();
    add_child(soak);

func _process(_delta:float) -> void:
    var world:World = soak.get("world");
    if world == null:
        return;
    for p in world.pawns:
        var kind:StringName = p.task.kind if p.task != null else &"none";
        if _last_pos.has(p) and is_instance_valid(p):
            var d:float = Vector2(p.position.x, p.position.z).distance_to(Vector2(_last_pos[p].x, _last_pos[p].z));
            if d < 3.0:
                dist[kind] = dist.get(kind, 0.0) + d;
        _last_pos[p] = p.position;
        if p.task != null and not is_same(_last_task.get(p), p.task):
            starts[kind] = starts.get(kind, 0) + 1;
            if kind == &"eat" and p.task.target is Building and World.alive(p.task.target):
                meal_trip_sum += Vector2(p.position.x, p.position.z).distance_to(Vector2(p.task.target.position.x, p.task.target.position.z));
                meal_trips += 1;
        _last_task[p] = p.task;
    var day:int = GameClock.day_index();
    if day != _printed_day and day > 0 and GameClock.hour() < 1.0:
        _printed_day = day;
        _report(world, day);

func _report(world:World, day:int) -> void:
    var total:float = 0.0;
    for k in dist:
        total += dist[k];
    var need_d:float = 0.0;
    var log_d:float = 0.0;
    var need_n:int = 0;
    var log_n:int = 0;
    for k in NEEDS:
        need_d += dist.get(k, 0.0);
        need_n += starts.get(k, 0);
    for k in LOGISTICS:
        log_d += dist.get(k, 0.0);
        log_n += starts.get(k, 0);
    var rows:Array = dist.keys();
    rows.sort_custom(func(a:StringName, b:StringName) -> bool: return dist[a] > dist[b]);
    var lines:PackedStringArray = [];
    for k in rows.slice(0, 8):
        lines.append("%s %d m (%d tasks)" % [k, dist[k], starts.get(k, 0)]);
    print("TRIPS day %d, %d citizens: walked %d m in all | needs %d m (%.0f%%, %d trips) | hauling and fuel %d m (%.0f%%, %d trips) | meal trips average %.1f m straight-line (%d) | top: %s" % [day, world.pawns.size(), total, need_d, 100.0 * need_d / maxf(1.0, total), need_n, log_d, 100.0 * log_d / maxf(1.0, total), log_n, meal_trip_sum / maxf(1, meal_trips), meal_trips, ", ".join(lines)]);
