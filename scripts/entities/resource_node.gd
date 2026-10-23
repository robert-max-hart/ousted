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

func display_name() -> String:
    return def["name"];

# Gathered without the player asking (berry bushes).
func is_auto() -> bool:
    return def.get("auto", false);

func info_text() -> String:
    var s:String = "%s: %d / %d\n" % [Defs.item_name(item), amount, max_amount];
    if designated:
        s += "Marked for harvest\n";
    elif is_auto():
        s += "Foraged by gatherers\n";
    else:
        s += "Use the Harvest tool to mark it\n";
    if reserved_by != null:
        s += "Being worked by %s\n" % reserved_by.get("first_name");
    return s;
