# ----------------------------------------------------------------
# TreeOrders
#     Single trees the player asks for with the Plant tool: marking a
#     cell, the selectable object and the stake that shows it,
#     cancelling, and the check that a tree may stand there.
# ----------------------------------------------------------------
class_name TreeOrders extends RefCounted;

# The Plant tool: asks for a tree on this cell (the ground must take one and no other order or tree may touch it).
static func order_tree(world:World, c:Vector2i) -> bool:
    if world.tree_orders.has(c) or not world.can_plant_tree(c):
        return false;
    for dz in range(-1, 2):
        for dx in range(-1, 2):
            if world.tree_orders.has(c + Vector2i(dx, dz)):
                return false;
    world.tree_orders[c] = true;
    TreeOrders._add_order_mark(world, c);
    return true;

# The selectable object for an order at this cell, or null.
static func tree_order_at(world:World, c:Vector2i) -> TreeOrder:
    if not world.tree_orders.has(c):
        return null;
    if not world._order_objects.has(c):
        world._order_objects[c] = TreeOrder.new(c);
    return world._order_objects[c];

static func cancel_tree_order(world:World, c:Vector2i) -> void:
    if world._order_objects.has(c):
        (world._order_objects[c] as TreeOrder).removed = true;
        world._order_objects.erase(c);
    if world.tree_orders.erase(c):
        world.tree_claimed.erase(c);
        TreeOrders._remove_order_mark(world, c);

static func _add_order_mark(world:World, c:Vector2i) -> void:
    if world._order_marks.has(c):
        return;
    var stake:MeshInstance3D = MeshInstance3D.new();
    var pole:BoxMesh = BoxMesh.new();
    pole.size = Vector3(0.07, 0.7, 0.07);
    stake.mesh = pole;
    var mat:StandardMaterial3D = StandardMaterial3D.new();
    mat.albedo_color = Color(0.5, 0.82, 0.35);
    stake.material_override = mat;
    stake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
    stake.position = Vector3(c.x + 0.5, world.terrain.height_at(c.x + 0.5, c.y + 0.5) + 0.35, c.y + 0.5);
    world._entities.add_child(stake);
    world._order_marks[c] = stake;

static func _remove_order_mark(world:World, c:Vector2i) -> void:
    if world._order_marks.has(c):
        (world._order_marks[c] as Node).queue_free();
        world._order_marks.erase(c);
