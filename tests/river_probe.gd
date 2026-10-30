# ----------------------------------------------------------------
# River probe
#     For a set of map seeds, prints what the river makes: points on its
#     centre line, the water cells it adds, how many cells are wadeable,
#     and whether the two banks are still joined by land or a ford.
#     (A flood fill over cells that are dry or shallow, from the land on
#     one side of the river to the other.)
#     godot --headless --path . res://tests/river_probe.tscn
# ----------------------------------------------------------------
extends Node;

func _ready() -> void:
    var seeds:Array[int] = [1, 7, 42, 99, 123, 256, 777, 1234, 4242, 31337, 98765, 555555];
    var joined:int = 0;
    for s in seeds:
        var t:Terrain = Terrain.new();
        t.generate(s);
        var water:int = 0;
        var shallow:int = 0;
        var steep_banks:int = 0;
        for z in Terrain.SIZE:
            for x in Terrain.SIZE:
                var c:Vector2i = Vector2i(x, z);
                if t.is_water(c):
                    water += 1;
                    if t.is_shallow(c):
                        shallow += 1;
                if t.river_distance(c) < 8.0 and not t.is_water(c) and t.cell_slope(c) > 1.2:
                    steep_banks += 1;
        var ok:String = "no path" if t.river_path.is_empty() else "%d points" % t.river_path.size();
        var cross:bool = _fords_wadeable(t) > 0;
        if cross:
            joined += 1;
        print("seed %6d  river %s  water cells %4d (wadeable %3d)  steep bank cells %3d  fords you can wade across: %d of %d" % [s, ok, water, shallow, steep_banks, _fords_wadeable(t), t.river_fords.size()]);
        t.free();
    print("RIVER PROBE: %d of %d maps have a ford you can walk across" % [joined, seeds.size()]);
    get_tree().quit();

# Fords where a straight line across the river (12 cells each way) never meets deep water or a cliff.
func _fords_wadeable(t:Terrain) -> int:
    var n:int = 0;
    for f in t.river_fords:
        var best_ok:bool = false;
        for k in 16:         # any direction across: the river runs along no fixed line
            var dir:Vector2 = Vector2.from_angle(k * PI / 16.0);
            var ok:bool = true;
            for step in range(-12, 13):
                var c:Vector2i = Vector2i(f + dir * step);
                if not t.in_bounds(c) or (t.is_water(c) and not t.is_shallow(c)) or t.cell_slope(c) > 2.0:
                    ok = false;
                    break;
            if ok:
                best_ok = true;
                break;
        if best_ok:
            n += 1;
    return n;

# Starts from a dry cell a few cells to one side of the middle of the river and floods over dry or wadeable cells,
# then checks for one reached on the other side.
func _banks_joined(t:Terrain) -> bool:
    if t.river_path.is_empty():
        return false;
    var mid:Vector2 = t.river_path[t.river_path.size() / 2];
    var prev:Vector2 = t.river_path[t.river_path.size() / 2 - 1];
    var dir:Vector2 = (mid - prev).normalized();
    var normal:Vector2 = Vector2(-dir.y, dir.x);
    var a:Vector2i = Vector2i(mid + normal * 14.0);
    var b:Vector2i = Vector2i(mid - normal * 14.0);
    if not t.in_bounds(a) or not t.in_bounds(b):
        return false;
    var seen:Dictionary = {a: true};
    var queue:Array[Vector2i] = [a];
    while not queue.is_empty():
        var c:Vector2i = queue.pop_back();
        if c.distance_to(b) < 6.0:
            return true;
        for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
            var n:Vector2i = c + d;
            if not t.in_bounds(n) or seen.has(n):
                continue;
            if (t.is_water(n) and not t.is_shallow(n)) or t.cell_slope(n) > 2.0:
                continue;
            seen[n] = true;
            queue.append(n);
    return false;
