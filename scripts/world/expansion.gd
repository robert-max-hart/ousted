# ----------------------------------------------------------------
# Expansion
#     Growing a finished fields, stockpile or graveyard: the new,
#     bigger rectangle must contain the old one, the extra cells
#     must be free, and the building pays the difference in cost
#     and work. It runs through the upgrade pipeline (upgrading is
#     &"expand", Building.expansion holds the plan), so the
#     building keeps working while its new ground is staked out,
#     materials are hauled and builders do the work. The cells are
#     held for it from the start; the size changes when the work is
#     done. Cancelling hands the materials back.
# ----------------------------------------------------------------
class_name Expansion extends RefCounted;

const ID:StringName = &"expand";

# The rectangle that would result from growing b to take in a cell.
static func target_rect(b:Building, cell:Vector2i) -> Rect2i:
    return b.rect().merge(Rect2i(cell, Vector2i.ONE));

# "" when b can grow into r, else why not.
static func block_reason(w:World, b:Building, r:Rect2i) -> String:
    if not b.def.get("drag_size", false):
        return "This can't be expanded";
    if not b.is_complete():
        return "Not finished yet";
    if b.upgrading != &"":
        return "Another project is in progress";
    if b.relocating_to != null and World.alive(b.relocating_to):
        return "It is being moved";
    if r == b.rect():
        return "Click beyond one of its edges to grow it there";
    if r.size.x > PlayerTools.FIELD_MAX_SIDE or r.size.y > PlayerTools.FIELD_MAX_SIDE:
        return "The largest size is %d cells a side" % PlayerTools.FIELD_MAX_SIDE;
    if not Rect2i(0, 0, Terrain.SIZE, Terrain.SIZE).encloses(r):
        return "Out of bounds";
    var old:Rect2i = b.rect();
    for z in range(r.position.y, r.end.y):
        for x in range(r.position.x, r.end.x):
            var c:Vector2i = Vector2i(x, z);
            if old.has_point(c):
                continue;
            if w.terrain.is_water(c):
                return "Can't build on water";
            if w.occupant[w.idx(c)] != null:
                return "Something is already built here";
            if w.terrain.get_overlay(c) == Terrain.Overlay.ROAD:
                return "A road is in the way";
    var hr:Vector2 = w.terrain.rect_height_range(r);
    if hr.y - hr.x > World.MAX_BUILD_SLOPE * 2.0:
        return "Ground is too steep";
    return "";

# {"rect", "cost", "work"}: the extra materials and labor for growing b to r.
static func plan(b:Building, r:Rect2i) -> Dictionary:
    var old_cost:Dictionary = b.cost();
    var old_work:float = b.work_required();
    var old_origin:Vector2i = b.origin;
    var old_size:Vector2i = b.size;
    b.origin = r.position;
    b.size = r.size;
    var new_cost:Dictionary = b.cost();
    var new_work:float = b.work_required();
    b.origin = old_origin;
    b.size = old_size;
    var extra:Dictionary = {};
    for item in new_cost:
        var more:int = new_cost[item] - old_cost.get(item, 0);
        if more > 0:
            extra[item] = more;
    return {"rect": r, "cost": extra, "work": maxf(0.5, new_work - old_work)};

static func start(w:World, b:Building, r:Rect2i) -> bool:
    if block_reason(w, b, r) != "":
        return false;
    b.expansion = plan(b, r);
    b._base_spent = b.delivered;
    b.delivered = {};
    b.incoming = {};
    b.work_done = 0.0;
    b.upgrading = ID;
    hold_cells(w, b);
    b.update_site_label();
    return true;

# The new cells belong to b from now on; anything standing in them is marked for the laborers.
static func hold_cells(w:World, b:Building) -> void:
    var r:Rect2i = b.expansion["rect"];
    for z in range(r.position.y, r.end.y):
        for x in range(r.position.x, r.end.x):
            var c:Vector2i = Vector2i(x, z);
            if b.rect().has_point(c):
                continue;
            w.occupant[w.idx(c)] = b;
            if b is Field or b is Graveyard or b is Pasture:
                w.terrain.set_overlay(c, Terrain.Overlay.SITE);
            var rn:ResourceNode = w.node_at[w.idx(c)];
            if rn != null:
                w.mark_for_clearing(rn);

# The work is done: take the new size.
static func finish(w:World, b:Building) -> void:
    var old:Rect2i = b.rect();
    var r:Rect2i = b.expansion["rect"];
    b.expansion = {};
    w.release_site_workers(b);       # tasks hold plot numbers, which change
    for z in range(r.position.y, r.end.y):
        for x in range(r.position.x, r.end.x):
            var c:Vector2i = Vector2i(x, z);
            var rn:ResourceNode = w.node_at[w.idx(c)];
            if rn != null:
                w.remove_node(rn);       # what the laborers didn't get to
    b.origin = r.position;
    b.size = r.size;
    if b.def.get("flatten", false):
        w.terrain.flatten_rect(r);
    b.on_resized(old);
    for z in range(r.position.y, r.end.y):
        for x in range(r.position.x, r.end.x):
            var c:Vector2i = Vector2i(x, z);
            if old.has_point(c):
                continue;
            if b is Field:
                w.terrain.set_overlay(c, Terrain.Overlay.ORCHARD if (b as Field).is_orchard() else Terrain.Overlay.TILLED);
            elif b is Graveyard:
                w.terrain.set_overlay(c, Terrain.Overlay.GRAVE);
            elif b is Pasture:
                w.terrain.set_overlay(c, Terrain.Overlay.ORCHARD);
    w._refresh_nav_rect(r);
    w.notify("%s expanded to %dx%d." % [b.display_name(), r.size.x, r.size.y]);

# The project is cancelled: let go of the new cells.
static func cancel(w:World, b:Building) -> void:
    if b.expansion.is_empty():
        return;
    var r:Rect2i = b.expansion["rect"];
    for z in range(r.position.y, r.end.y):
        for x in range(r.position.x, r.end.x):
            var c:Vector2i = Vector2i(x, z);
            if b.rect().has_point(c):
                continue;
            if w.occupant[w.idx(c)] == b:
                w.occupant[w.idx(c)] = null;
            if b is Field or b is Graveyard or b is Pasture:
                w.terrain.set_overlay(c, Terrain.Overlay.NONE);
    b.expansion = {};
