# ----------------------------------------------------------------
# TreeOrder
#     A cell the player marked with the Plant tool: a tree will be
#     planted there by a laborer. A light object so the mark can be
#     selected and inspected (and cancelled) like anything else.
# ----------------------------------------------------------------
class_name TreeOrder extends RefCounted;

var cell    :Vector2i;
var removed :bool = false;

func _init(c:Vector2i) -> void:
    cell = c;

func display_name() -> String:
    return "Tree to plant";

func info_text() -> String:
    var claimed:bool = World.instance.tree_claimed.has(cell);
    return "A laborer will plant a tree here.\n%s\n" % ("Someone is on the way." if claimed else "Waiting for a free laborer.");

func help_text() -> String:
    return "Marked with the Plant trees tool. It costs nothing but a laborer's time. The sapling takes a long while to grow into a tree that gives wood.";
