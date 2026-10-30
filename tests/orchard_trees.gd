# ----------------------------------------------------------------
# Orchard trees
#     Every tree crop has its fruit or nut item, a trade value, a seed
#     price and a plant shape; fruit can be distilled and nuts cannot.
#     godot --headless --path . --fixed-fps 60 res://tests/orchard_trees.tscn
# ----------------------------------------------------------------
extends Node;

func _ready() -> void:
    var fails:int = 0;
    var trees:Array = Defs.CROPS.keys().filter(func(id:StringName) -> bool: return Defs.CROPS[id].get("tree", false));
    for id in [&"apple", &"pear", &"cherry", &"peach", &"plum", &"walnut", &"pecan"]:
        if not trees.has(id):
            print("FAIL %s is not a tree crop" % id);
            fails += 1;
    var distilled:Dictionary = {};
    for rid in Defs.BUILDINGS[&"still"]["recipes"]:
        for item in Defs.BUILDINGS[&"still"]["recipes"][rid]["inputs"]:
            distilled[item] = true;
    for id in trees:
        var item:StringName = Defs.CROPS[id]["item"];
        var nut:bool = Defs.ITEMS[item].get("nut", false);
        if not Defs.ITEMS.has(item) or not Defs.ITEMS[item].get("food", false):
            print("FAIL %s: %s is not a food item" % [id, item]);
            fails += 1;
        if Defs.trade_value(item) <= 0 or Defs.SEED_VALUE.get(id, 0) < 500:
            print("FAIL %s: no trade value for %s or a cheap sapling (%s)" % [id, item, Defs.SEED_VALUE.get(id, 0)]);
            fails += 1;
        if CropMeshes.shape_of(id) != &"tree":
            print("FAIL %s is not drawn as a tree" % id);
            fails += 1;
        if nut == distilled.has(item) and item != &"apples" and item != &"pears":
            print("FAIL %s: a nut must not be distilled and a fruit must be (nut %s, distilled %s)" % [item, nut, distilled.has(item)]);
            fails += 1;
        if not Traders.BRINGS.has(item) or not Traders.WANTS.has(item):
            print("FAIL merchants do not trade %s" % item);
            fails += 1;
    print("ORCHARD TREES %s (%d tree crops)" % ["PASS" if fails == 0 else "FAIL", trees.size()]);
    get_tree().quit(1 if fails > 0 else 0);
