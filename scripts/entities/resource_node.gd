# ----------------------------------------------------------------
# ResourceNode
#     A harvestable thing on the map (tree, rock, ore, bush). Pure data;
#     ResourceRenderer draws all of them through MultiMeshes.
# ----------------------------------------------------------------
class_name ResourceNode extends RefCounted;

var kind        :StringName;
var def         :Dictionary;
var cell        :Vector2i;
var item        :StringName;
var amount      :int;
var max_amount  :int;
var work_per_unit:float;
var solid       :bool;
var regrows     :bool;
var designated  :bool = false;      # player marked for harvest/clearing
var reserved_by :Object = null;     # pawn currently working it
var removed     :bool = false;
var growth      :float = 1.0;       # 0..1; trees are saplings until this reaches 1
# visual variation
var offset      :Vector2;
var yaw         :float;
var scale       :float;

func _init(k:StringName, c:Vector2i, rng:RandomNumberGenerator) -> void:
    kind = k;
    def = Defs.RESOURCE_NODES[k];
    cell = c;
    item = def["item"];
    max_amount = def["amount"];
    amount = max_amount;
    work_per_unit = def["work"];
    solid = def["solid"];
    regrows = def.get("regrows", false);
    offset = Vector2(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.2, 0.2));
    yaw = rng.randf() * TAU;
    scale = rng.randf_range(0.75, 1.25);

# [kind, cell, amount, growth, designated, offset, yaw, scale]
func to_array() -> Array:
    return [kind, cell, amount, growth, designated, offset, yaw, scale];

static func from_array(a:Array, rng:RandomNumberGenerator) -> ResourceNode:
    var rn:ResourceNode = ResourceNode.new(a[0], a[1], rng);
    rn.amount = a[2];
    rn.growth = a[3];
    rn.designated = a[4];
    rn.offset = a[5];
    rn.yaw = a[6];
    rn.scale = a[7];
    return rn;

func display_name() -> String:
    return def["name"] if is_mature() else "%s sapling" % def["name"];

func is_mature() -> bool:
    return growth >= 1.0;

# Starts this node as a freshly planted sapling (it yields little until it grows up).
func make_sapling() -> void:
    growth = 0.0;
    amount = 1;

# Sets growth and the wood a tree holds to match it.
func set_growth(g:float) -> void:
    growth = clampf(g, 0.0, 1.0);
    amount = maxi(1, roundi(max_amount * growth)) if growth < 1.0 else max_amount;

# Gathered without the player asking (berry bushes).
func is_auto() -> bool:
    return def.get("auto", false);

# A wild food (berries, mushrooms, nuts) the Forage tool and the Forager's Hut can pick.
func is_forageable() -> bool:
    return def.get("forage", false);

func info_text() -> String:
    var s:String = "%s: %d / %d\n" % [Defs.item_name(item), amount, max_amount];
    if not is_mature():
        s += "Growing: %d%%\n" % roundi(growth * 100.0);
    if is_forageable():
        s += "Fruits in: %s\n" % ", ".join((def["fruit_seasons"] as Array).map(func(i:int) -> String: return GameClock.SEASON_NAMES[i]));
    if designated:
        s += "Marked for foraging\n" if is_forageable() else "Marked for harvest\n";
    elif is_auto():
        s += "Foraged by gatherers\n";
    elif is_forageable():
        s += "Use the Forage tool to mark it, or a Forager's Hut picks it\n";
    else:
        s += "Use the Harvest tool to mark it\n";
    if reserved_by != null:
        s += "Being worked by %s\n" % reserved_by.get("first_name");
    return s;
