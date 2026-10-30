# ----------------------------------------------------------------
# Terrain probe
#     Prints, for a handful of map seeds, how the generated terrain is
#     shaped: share under water, share of level ground (slope under
#     0.3), of gently rolling ground (0.3 to 1.0), of steep ground
#     (over 1.0, where rocks and ore appear) and the height range.
#     godot --headless --path . res://tests/terrain_probe.tscn
# ----------------------------------------------------------------
extends Node;

func _ready() -> void:
    var seeds:Array[int] = [1, 7, 42, 99, 123, 256, 777, 1234, 4242, 31337, 98765, 555555];
    var tot:Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0];
    for s in seeds:
        var t:Terrain = Terrain.new();
        t.generate(s);
        var water:int = 0;
        var level:int = 0;
        var roll:int = 0;
        var steep:int = 0;
        var land:int = 0;
        var hmax:float = -99.0;
        var hmin:float = 99.0;
        for z in Terrain.SIZE:
            for x in Terrain.SIZE:
                var c:Vector2i = Vector2i(x, z);
                var h:float = t.cell_height(c);
                hmax = maxf(hmax, h);
                hmin = minf(hmin, h);
                if h < Terrain.WATER_LEVEL + 0.4:
                    water += 1;
                    continue;
                land += 1;
                var sl:float = t.cell_slope(c);
                if sl < 0.3:
                    level += 1;
                elif sl < 1.0:
                    roll += 1;
                else:
                    steep += 1;
        var n:float = float(Terrain.SIZE * Terrain.SIZE);
        print("seed %6d  water %2d%%  of the land: level %2d%%  rolling %2d%%  steep %2d%%  (steep cells %4d, about %.1f ore)  height %.1f to %.1f" % [s, roundi(100.0 * water / n), roundi(100.0 * level / land), roundi(100.0 * roll / land), roundi(100.0 * steep / land), steep, steep * 0.0108, hmin, hmax]);
        tot[0] += 100.0 * water / n;
        tot[1] += 100.0 * level / land;
        tot[2] += 100.0 * roll / land;
        tot[3] += 100.0 * steep / land;
        tot[4] += steep * 0.0108;
        t.free();
    var k:float = float(seeds.size());
    print("AVERAGE  water %.0f%%  level %.0f%%  rolling %.0f%%  steep %.0f%%  ore about %.1f" % [tot[0] / k, tot[1] / k, tot[2] / k, tot[3] / k, tot[4] / k]);
    get_tree().quit();
