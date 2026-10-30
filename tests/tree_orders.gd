# ----------------------------------------------------------------
# Planting single trees (the Plant tool)
#     A marked cell takes a tree and the marks keep one cell apart;
#     a laborer walks there and plants it for no materials; the marks
#     are saved and can be cancelled.
#     godot --headless --path . --fixed-fps 60 res://tests/tree_orders.tscn
# ----------------------------------------------------------------
extends Node;

var world:World;
var _fails:int = 0;
var _spot:Vector2i;
var _start:float = 0.0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    _spot = _free_cell();
    for rn in world.nodes.duplicate():
        if Vector2(rn.cell - _spot).length() < 4.0:
            world.remove_node(rn);
    _expect("a free cell takes a tree order", world.order_tree(_spot));
    _expect("the same cell again does not", not world.order_tree(_spot));
    _expect("nor the cell next to it (trees need room)", not world.order_tree(_spot + Vector2i(1, 0)));
    _expect("but one two cells off does", world.order_tree(_spot + Vector2i(2, 0)));
    _expect("the order shows a stake", world._order_marks.has(_spot));
    var data:Dictionary = world.serialize();
    _expect("orders are saved", (data["tree_orders"] as Array).has(_spot));
    world.cancel_tree_order(_spot + Vector2i(2, 0));
    _expect("an order can be cancelled", not world.tree_orders.has(_spot + Vector2i(2, 0)) and not world._order_marks.has(_spot + Vector2i(2, 0)));
    var wood:int = Stock.amount(&"wood");
    GameClock.set_speed(3);
    Engine.time_scale = 4.0;
    _start = GameClock.total_hours;
    set_process(true);

func _process(_delta:float) -> void:
    if world == null:
        return;
    for p in world.pawns:
        p.hunger = 1.0; p.thirst = 1.0; p.energy = 1.0; p.warmth = 1.0;
    var hours:float = GameClock.total_hours - _start;
    var planted:bool = world.node_at[world.idx(_spot)] != null and (world.node_at[world.idx(_spot)] as ResourceNode).is_tree();
    if planted:
        _expect("a laborer planted a sapling there (%.1f hours)" % hours, world.saplings.has(world.node_at[world.idx(_spot)]));
        _expect("and the order is gone", not world.tree_orders.has(_spot) and not world._order_marks.has(_spot));
        _finish();
    elif hours > 20.0:
        _expect("the tree was planted within 20 hours", false);
        _finish();

func _free_cell() -> Vector2i:
    for r in range(6, 30):
        for dx in range(-r, r + 1, 2):
            var c:Vector2i = world.town_hall.origin + Vector2i(dx, r);
            if world.can_plant_tree(c) and world.can_plant_tree(c + Vector2i(2, 0)):
                return c;
    return world.town_hall.origin + Vector2i(0, 8);

func _finish() -> void:
    Engine.time_scale = 1.0;
    set_process(false);
    print("TREE ORDERS %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
