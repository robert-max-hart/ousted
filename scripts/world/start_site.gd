# ----------------------------------------------------------------
# StartSite
#     Where and how a colony starts: finding the start spot, topping
#     up the rocks and iron around it, clearing it, and founding the
#     colony (Town Hall, goods, settlers) once the spot is chosen.
#     World keeps thin delegates.
# ----------------------------------------------------------------
class_name StartSite extends RefCounted;

@warning_ignore("integer_division")
static func _find_start_cell(world:World) -> Vector2i:
    var center:Vector2i = Vector2i(Terrain.SIZE / 2, Terrain.SIZE / 2);
    var best:Vector2i = center;
    var best_score:float = INF;
    for z in range(16, Terrain.SIZE - 16, 2):
        for x in range(16, Terrain.SIZE - 16, 2):
            var c:Vector2i = Vector2i(x, z);
            var r:Rect2i = Rect2i(c - Vector2i(5, 5), Vector2i(10, 10));
            var hr:Vector2 = world.terrain.rect_height_range(r);
            if hr.x < Terrain.WATER_LEVEL + 0.5:
                continue;
            # level ground matters most close in (the first buildings), and a wider level apron leaves room to grow
            var near:Vector2 = world.terrain.rect_height_range(Rect2i(c - Vector2i(8, 8), Vector2i(16, 16)));
            var wide:Vector2 = world.terrain.rect_height_range(Rect2i(c - Vector2i(14, 14), Vector2i(28, 28)).intersection(Rect2i(0, 0, Terrain.SIZE, Terrain.SIZE)));
            var score:float = (hr.y - hr.x) * 4.0 + (near.y - near.x) * 3.0 + (wide.y - wide.x) * 1.5 + Vector2(c - center).length() * 0.1;
            if not world.terrain.river_path.is_empty() or Terrain.river_style == Terrain.RiverStyle.COAST:       # settle by the river (or the sea): close, but not on its bank
                var rd:float = minf(world.terrain.river_distance(c), 40.0);
                score += absf(rd - world.START_RIVER_AT) * 0.7 + maxf(0.0, 9.0 - rd);
            if score < best_score:
                best_score = score;
                best = c;
    return best;

# Tops the rings around the start up with loose rocks, so the first buildings always have stone close by (the random
# scatter leaves some seeds with one or two, and a start by the river has few): START_ROCKS_MIN in the whole ring, and
# START_ROCKS_CLOSE of them within START_ROCKS_CLOSE_FAR cells.
static func _ensure_start_rocks(world:World, start:Vector2i) -> void:
    StartSite._top_up(world, &"rock", start, world.START_ROCKS_NEAR, world.START_ROCKS_CLOSE_FAR, world.START_ROCKS_CLOSE);
    StartSite._top_up(world, &"rock", start, world.START_ROCKS_NEAR, world.START_ROCKS_FAR, world.START_ROCKS_MIN);

# Adds nodes of one kind on level, dry, empty ground in the ring near..far cells from the start until it holds at least
# `minimum` of them (picked with the world's own rng).
static func _top_up(world:World, kind:StringName, start:Vector2i, near:float, far:float, minimum:int) -> void:
    var have:int = 0;
    for rn in world.nodes:
        var d:float = Vector2(rn.cell - start).length();
        if rn.kind == kind and d >= near and d <= far:
            have += 1;
    var free:Array[Vector2i] = [];
    var reach:int = ceili(far);
    for z in range(start.y - reach, start.y + reach + 1):
        for x in range(start.x - reach, start.x + reach + 1):
            var c:Vector2i = Vector2i(x, z);
            var d:float = Vector2(c - start).length();
            if d < near or d > far or not world.terrain.in_bounds(c):
                continue;
            if world.terrain.is_water(c) or world.terrain.cell_height(c) < Terrain.WATER_LEVEL + 0.4 or world.terrain.cell_slope(c) > 1.4:
                continue;
            if world.node_at[world.idx(c)] == null and world.occupant[world.idx(c)] == null:
                free.append(c);
    while have < minimum and not free.is_empty():
        var pick:int = world.rng.randi_range(0, free.size() - 1);
        world.add_node(kind, free[pick]);
        free.remove_at(pick);
        have += 1;

# Founds the colony around a start cell: what it starts with (the Town Hall, a well or a supply cart: GameRules.start),
# its goods and the first settlers.
static func _found_colony(world:World, start:Vector2i) -> void:
    StartSite._ensure_start_rocks(world, start);
    StartSite._ensure_start_ore(world, start);
    var def:StringName = GameRules.start_def();
    var size:Vector2i = Defs.BUILDINGS[def]["size"];
    world.start_building = world.place_building(def, start - size / 2, size, true);
    if def == &"town_hall":
        world.town_hall = world.start_building;
    StartSite._start_colony_goods(world, start);
    world.seeds.grant_trees(world.rng);
    Defs.ageing_days_per_year = GameRules.ageing_days();
    StartSite._spawn_settlers(world, start);
    world.jobs.sync_targets();

# The player's choice of start (see awaiting_start): returns "" once the colony is founded with its first building at
# origin, else why that spot will not do.
static func begin_colony(world:World, origin:Vector2i) -> String:
    if not world.awaiting_start:
        return "The colony is already founded";
    var def:StringName = GameRules.start_def();
    var size:Vector2i = Defs.BUILDINGS[def]["size"];
    var start:Vector2i = origin + size / 2;
    var why:String = world.can_place(def, origin, size);
    if why != "":
        return why;
    StartSite._clear_nodes(world, start, 13);        # the hall's ground and the settlers' first yard are cleared of trees and rocks
    world.awaiting_start = false;
    StartSite._found_colony(world, start);
    GameClock.locked = false;
    GameClock.set_speed(1);
    world.camera_rig._distance = 40.0;
    world.camera_rig._target_distance = 40.0;
    world.camera_rig.focus_on(world.start_building.position);
    world.notify("Your settlers have arrived. Spring has begun.");
    return "";

# Iron is a little scarce on the bigger map, so the ring START_ORE_NEAR to START_ORE_FAR cells from the start always
# holds at least START_ORE_MIN outcrops (placed on the gentler ground; the hills keep their own).
static func _ensure_start_ore(world:World, start:Vector2i) -> void:
    StartSite._top_up(world, &"ore", start, world.START_ORE_NEAR, world.START_ORE_FAR, world.START_ORE_MIN);

static func _clear_nodes(world:World, c:Vector2i, radius:int) -> void:
    for rn in world.nodes.duplicate():
        if Vector2(rn.cell - c).length() <= radius:
            world.remove_node(rn);

# The starting upgrades of the chosen difficulty, then the starting goods: into the Town Hall's store room as far as it
# goes (with a well or nothing there is no store room), the rest in supply carts beside it (gone once empty).
static func _start_colony_goods(world:World, start:Vector2i) -> void:
    var hall:Building = world.town_hall;
    if hall != null:
        for id in Defs.DIFFICULTIES[Defs.difficulty]["town_hall"]:
            hall.upgrades_done[id] = true;
    var left:Dictionary = {};
    for item in world.START_STOCK:
        var amount:int = roundi(world.START_STOCK[item] * GameRules.supply_share());
        var rest:int = amount - (hall.store(item, amount) if hall != null else 0);
        if rest > 0:
            left[item] = rest;
    if left.is_empty():
        return;
    var cart:Building = world.start_building if world.start_building.def_id == &"cart" else StartSite._place_cart(world, start);
    for item in left:
        var rest:int = left[item];
        while rest > 0 and cart != null:
            rest -= cart.store(item, rest);
            if rest > 0:
                cart = StartSite._place_cart(world, start);       # that one is full: another cart takes the rest
    if cart == null:
        world.notify("There was no room beside the settlers for all of the starting goods.")

# A supply cart on open ground close to the start, or null if there is no room.
static func _place_cart(world:World, start:Vector2i) -> Building:
    var size:Vector2i = Defs.BUILDINGS[&"cart"]["size"];
    for r in range(3, 14):
        for dz in range(-r, r + 1):
            for dx in range(-r, r + 1):
                if maxi(absi(dx), absi(dz)) != r:
                    continue;
                var o:Vector2i = start + Vector2i(dx, dz);
                if world.can_place(&"cart", o, size) == "" and world._rect_free_of_nodes(Rect2i(o, size)):
                    return world.place_building(&"cart", o, size, true);
    return null;

static func _spawn_settlers(world:World, start:Vector2i) -> void:
    var used:Array[String] = [];
    for i in GameRules.settlers:
        var c:Vector2i = world.nav.nearest_walkable(start + Vector2i(world.rng.randi_range(-4, 4), 3 + world.rng.randi_range(0, 2)), 6);
        var p:Pawn = Pawn.new();
        p.setup(world, c, world.rng, used);
        if i >= GameRules.settlers - GameRules.children():
            p.age = world.rng.randi_range(6, 14) + world.rng.randf();
        used.append(p.first_name);
        if i < world.START_PROFESSIONS.size():
            p.profession = world.START_PROFESSIONS[i];
        world._entities.add_child(p);
        world.pawns.append(p);
