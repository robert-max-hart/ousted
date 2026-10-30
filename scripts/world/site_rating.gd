# ----------------------------------------------------------------
# SiteRating
#     How good a place is to found the colony, as a short list of
#     facts around a spot: level ground, water, soil, trees, wild food,
#     stone and iron. Each line is rated 0 (poor), 1 (fair) or 2 (good).
#     Shown beside the cursor while the player chooses the Town Hall's
#     place (HUD), so the choice is an informed one.
# ----------------------------------------------------------------
class_name SiteRating extends RefCounted;

const LEVEL_R   :int = 10;        # cells around the spot counted for level ground and soil
const WATER_R   :int = 30;        # how far to look for water
const TREE_R    :float = 15.0;
const FOOD_R    :float = 18.0;
const STONE_R   :float = 20.0;
const ORE_R     :float = 30.0;
const NAMES     :Array[String] = ["Poor", "Fair", "Good"];
const COLORS    :Array[String] = ["#ff7a66", "#f0d060", "#7be07b"];

# Lines of [label, text, level 0..2] for a Town Hall whose middle is at c, then the overall level as the last entry
# ["Overall", text, level].
static func rate(world:World, c:Vector2i) -> Array:
    var t:Terrain = world.terrain;
    var lines:Array = [];
    # level ground and soil, over the dry cells around the spot
    var cells:int = 0;
    var flat:int = 0;
    var soil:float = 0.0;
    var dry:int = 0;
    for z in range(c.y - LEVEL_R, c.y + LEVEL_R + 1):
        for x in range(c.x - LEVEL_R, c.x + LEVEL_R + 1):
            var cell:Vector2i = Vector2i(x, z);
            if not t.in_bounds(cell) or Vector2(cell - c).length() > LEVEL_R:
                continue;
            cells += 1;
            if t.is_water(cell):
                continue;
            if t.cell_slope(cell) < 0.5:
                flat += 1;
            dry += 1;
            soil += world.soil_fertility[world.idx(cell)];
    var flat_share:float = float(flat) / float(maxi(1, cells));
    lines.append(["Level ground", "%d%% of the land around" % roundi(flat_share * 100.0), 2 if flat_share >= 0.8 else 1 if flat_share >= 0.55 else 0]);
    # the nearest water (river, lake or pond)
    var best:float = INF;
    for z in range(c.y - WATER_R, c.y + WATER_R + 1):
        for x in range(c.x - WATER_R, c.x + WATER_R + 1):
            var cell:Vector2i = Vector2i(x, z);
            if t.in_bounds(cell) and t.is_water(cell):
                best = minf(best, Vector2(cell - c).length());
    var water_level:int = 0;
    var water_text:String = "none within %d cells" % WATER_R;
    if best < INF:
        water_text = "%d cells away" % roundi(best);
        water_level = 2 if best >= 5.0 and best <= 20.0 else 1;
        if best < 5.0:
            water_text += " (right at the water: little room to build)";
    lines.append(["Water", water_text, water_level]);
    var soil_avg:float = soil / float(maxi(1, dry));
    lines.append(["Soil", "fertility %d%%" % roundi(soil_avg * 100.0), 2 if soil_avg >= 0.78 else 1 if soil_avg >= 0.6 else 0]);
    # what grows and lies around
    var trees:int = 0;
    var food:int = 0;
    var rocks:int = 0;
    var ore:int = 0;
    for rn in world.nodes:
        var d:float = Vector2(rn.cell - c).length();
        if rn.is_tree() and rn.is_mature() and d <= TREE_R:
            trees += 1;
        elif rn.is_forageable() and d <= FOOD_R:
            food += 1;
        elif rn.kind == &"rock" and d <= STONE_R:
            rocks += 1;
        elif rn.kind == &"ore" and d <= ORE_R:
            ore += 1;
    rocks = maxi(rocks, World.START_ROCKS_MIN);       # the game tops these up around the start, whatever the spot
    ore = maxi(ore, World.START_ORE_MIN);
    lines.append(["Trees", "%d near" % trees, 2 if trees >= 25 else 1 if trees >= 8 else 0]);
    lines.append(["Wild food", "%d near" % food, 2 if food >= 8 else 1 if food >= 3 else 0]);
    lines.append(["Stone", "%d loose rocks near (5 at least)" % rocks if rocks <= World.START_ROCKS_MIN else "%d loose rocks near" % rocks, 2 if rocks >= 6 else 1 if rocks >= 2 else 0]);
    lines.append(["Iron", "%d outcrops within %d cells%s" % [ore, int(ORE_R), " (2 at least)" if ore <= World.START_ORE_MIN else ""], 2 if ore >= 2 else 1 if ore >= 1 else 0]);
    var total:int = 0;
    for l in lines:
        total += l[2];
    var share:float = float(total) / float(lines.size() * 2);
    lines.append(["Overall", NAMES[2 if share >= 0.72 else 1 if share >= 0.45 else 0], 2 if share >= 0.72 else 1 if share >= 0.45 else 0]);
    return lines;

# The lines as one block of coloured text (BBCode) for a RichTextLabel.
static func bbcode(lines:Array) -> String:
    var out:PackedStringArray = [];
    for l in lines:
        var coloured:String = "[color=%s]%s[/color]" % [COLORS[l[2]], l[1]];
        if l[0] == "Overall":
            out.append("[b]Overall: %s[/b]" % coloured);
        else:
            out.append("%s: %s" % [l[0], coloured]);
    return "\n".join(out);
