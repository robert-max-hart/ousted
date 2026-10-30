# ----------------------------------------------------------------
# ProductionTasks
#     Work at production buildings and tool handling: woodcutting, mining, the blacksmith, input stocking and fetching tools.
# ----------------------------------------------------------------
class_name ProductionTasks extends TaskBase;

func woodcutter_task(p:Pawn) -> Task:
    var sites:Array[Building] = [];
    for b in world.buildings:
        if b.is_complete() and b.def.get("profession", "") == "WOODCUTTER":
            sites.append(b);
    sites.sort_custom(func(a:Building, c:Building) -> bool:
        return a.position.distance_squared_to(p.position) < c.position.distance_squared_to(p.position));
    for b in sites:
        if workers_at(b) >= b.def.get("worker_slots", 1):
            continue;
        var order:Array = [_chop_task, _forge_task, _stock_inputs_task, _plant_task] if b.settings.get("priority", 0) == 1 \
            else [_forge_task, _stock_inputs_task, _chop_task, _plant_task];       # firewood first: split and fetch logs before felling more
        for job in order:
            var t:Task = (job as Callable).call(p, b);
            if t != null:
                t.workplace = b;
                return t;
    return null;

# A Forager's Hut: pick the nearest wild food in its radius that the hut is set to pick, while the food stock is
# under the hut's cap. Experience counts as Forager experience.
func forager_task(p:Pawn) -> Task:
    var sites:Array[Building] = [];
    for b in world.buildings:
        if b.is_complete() and b.def.get("profession", "") == "FORAGER" and b.production_allowed(&"food"):
            sites.append(b);
    sites.sort_custom(func(a:Building, c:Building) -> bool:
        return a.position.distance_squared_to(p.position) < c.position.distance_squared_to(p.position));
    for b in sites:
        if workers_at(b) >= b.def.get("worker_slots", 1):
            continue;
        var t:Task = null;
        for kind in _forage_order(b):
            var only:StringName = kind;
            t = harvest_node_task(p, func(rn:ResourceNode) -> bool:
                return rn.is_forageable() and rn.is_mature() and in_radius(b, rn.cell) and b.settings.get("forage_%s" % rn.kind, true) \
                    and (only == &"" or rn.kind == only));
            if t != null:
                break;
        if t == null and b.has_upgrade(&"cultivation"):
            t = _sow_task(b);
        if t != null:
            t.workplace = b;
            t.job = JobManager.Profession.FORAGER;
            return t;
    return null;

const FORAGE_KINDS:Array[StringName] = [&"bush", &"mushroom", &"hazel"];

# The wild foods a hut's foragers try in turn: each is "pick only this kind", and &"" at the end means anything
# switched on (the nearest). The hut's "Pick first" choice is Nearest, What we have least of, or one food.
func _forage_order(b:Building) -> Array[StringName]:
    var order:Array[StringName] = [];
    var pref:int = b.settings.get("forage_pref", 0);
    if pref == 1:
        var kinds:Array[StringName] = FORAGE_KINDS.filter(func(k:StringName) -> bool: return b.settings.get("forage_%s" % k, true));
        kinds.sort_custom(func(a:StringName, c:StringName) -> bool:
            return Stock.amount(Defs.RESOURCE_NODES[a]["item"]) < Stock.amount(Defs.RESOURCE_NODES[c]["item"]));
        order.append_array(kinds);
    elif pref >= 2 and pref - 2 < FORAGE_KINDS.size():
        order.append(FORAGE_KINDS[pref - 2]);
    order.append(&"");
    return order;

const SOW_PER_KIND:int = 18;       # a hut sows no more of a kind than this within its radius

# Sows a new patch of one of the wild foods switched on, on free ground in the hut's radius.
func _sow_task(b:Building) -> Task:
    var kinds:Array[StringName] = [];
    for kind in [&"bush", &"mushroom", &"hazel"]:
        if b.settings.get("sow_%s" % kind, false):
            kinds.append(kind);
    kinds.shuffle();
    var center:Vector2i = Vector2i(b.center_cell());
    var r:int = ceili(b.radius());
    for kind in kinds:
        var have:int = 0;
        for rn in world.nodes:
            if rn.kind == kind and in_radius(b, rn.cell):
                have += 1;
        if have + world.planting.size() >= SOW_PER_KIND:
            continue;
        for i in 30:
            var c:Vector2i = center + Vector2i(world.rng.randi_range(-r, r), world.rng.randi_range(-r, r));
            if not in_radius(b, c) or not WildGrowth.can_grow(world, c, kind):
                continue;
            world.planting[c] = true;
            var name:String = String(Defs.RESOURCE_NODES[kind]["name"]).to_lower();
            var t:Task = Task.new(&"plant", "Sowing %s" % name);
            t.target = b;
            t.move_cell(c, "Walking to sow %s" % name);
            t.work_for(0.3, "Sowing %s" % name, func(_pw:Pawn) -> void:
                world.planting.erase(c);
                if WildGrowth.can_grow(world, c, kind):
                    world.sow_wild(kind, c));
            t.on_cancel = func(_pw:Pawn) -> void:
                world.planting.erase(c);
            return t;
    return null;

# --------------------------------
# Tools

# Fetches the best tool in storage for a citizen who has none.
func equip_task(p:Pawn) -> Task:
    var item:StringName = &"";
    for candidate in Defs.TOOL_PRIORITY:
        if Stock.available(candidate) > 0:
            item = candidate;
            break;
    if item == &"":
        return null;
    var src:Building = world.nearest_storage_with(item, p.position);
    if src == null or p.has_failed(src) or src.reserve_out(item, 1) == 0:
        return null;
    var st:Dictionary = {"picked": false};
    var t:Task = Task.new(&"equip", "Fetching a %s" % Defs.item_name(item).to_lower());
    t.target = src;
    t.move_rect(src.rect(), src.is_walkable());
    t.act(func(pw:Pawn) -> bool:
        st["picked"] = true;
        if src.take_reserved(item, 1) < 1:
            return false;
        pw.equip(item);
        return true);
    t.on_cancel = func(_pw:Pawn) -> void:
        if not st["picked"] and World.alive(src):
            src.release_out(item, 1);
    return t;

# Brings inputs from storage to a production building that is short of them.
func _stock_inputs_task(p:Pawn, b:Building) -> Task:
    var want:Dictionary = b.inputs_wanted();
    var item:StringName = &"";
    var src:Building = null;
    var most:int = 0;
    for in_item in want:
        if want[in_item] > most and Stock.available(in_item) > 0:
            var s:Building = world.nearest_storage_with(in_item, p.position);
            if s != null:
                item = in_item;
                src = s;
                most = want[in_item];
    if src == null:
        return null;
    var n:int = src.reserve_out(item, mini(Pawn.CARRY_CAP, most));
    if n == 0:
        return null;
    b.input_incoming[item] = b.input_incoming.get(item, 0) + n;
    var st:Dictionary = {"picked": false, "done": false};
    var t:Task = Task.new(&"supply", "Fetching %s for %s" % [Defs.item_name(item).to_lower(), b.display_name().to_lower()]);
    t.target = b;
    t.move_rect(src.rect(), src.is_walkable(), "Fetching %s" % Defs.item_name(item).to_lower());
    t.act(func(pw:Pawn) -> bool:
        pw.set_carry(item, src.take_reserved(item, n));
        st["picked"] = true;
        return true);
    t.move_rect(b.rect(), b.is_walkable());
    t.act(func(pw:Pawn) -> bool:
        if not World.alive(b):
            return false;
        st["done"] = true;
        b.cancel_input_incoming(item, n);
        b.add_input(item, pw.carry_amount);
        pw.clear_carry();
        return true);
    t.on_cancel = func(_pw:Pawn) -> void:
        if not st["picked"] and World.alive(src):
            src.release_out(item, n);
        if not st["done"] and World.alive(b):
            b.cancel_input_incoming(item, n);
    return t;

# General labor: top up any production building that is short of inputs.
func supply_inputs_task(p:Pawn) -> Task:
    for b in world.buildings:
        if not b.is_complete() or p.has_failed(b) or b.inputs_wanted().is_empty():
            continue;
        var t:Task = _stock_inputs_task(p, b);
        if t != null:
            return t;
    return null;

func blacksmith_task(p:Pawn) -> Task:
    return craft_task(p, "BLACKSMITH");

# Weavers and the other artisans (a craft building with recipes and an input buffer, like the Blacksmith).
func artisan_task(p:Pawn) -> Task:
    return craft_task(p, "ARTISAN");

func craft_task(p:Pawn, profession:String) -> Task:
    var sites:Array[Building] = [];
    for b in world.buildings:
        if b.is_complete() and b.def.get("profession", "") == profession:
            sites.append(b);
    sites.sort_custom(func(a:Building, c:Building) -> bool:
        return a.position.distance_squared_to(p.position) < c.position.distance_squared_to(p.position));
    for b in sites:
        if workers_at(b) >= b.def.get("worker_slots", 1):
            continue;
        for job in [_forge_task, _stock_inputs_task]:
            var t:Task = (job as Callable).call(p, b);
            if t != null:
                t.workplace = b;
                return t;
    return null;

# Runs the first recipe that is switched on, under its cap and has its inputs, for up to its batch size
# (the Blacksmith makes one tool, the Woodcutter splits a couple of logs at a time).
@warning_ignore("integer_division")
func _forge_task(_p:Pawn, b:Building) -> Task:
    for id in b.def["recipes"]:
        var recipe:Dictionary = b.def["recipes"][id];
        if not b.recipe_enabled(id):
            continue;
        var item:StringName = recipe.get("output", id);       # alternative recipes for one product have their own ids and an "output"
        var per:int = recipe.get("yield", 1);
        var crafts:int = recipe.get("batch", 1);
        for in_item in recipe["inputs"]:
            crafts = mini(crafts, b.input_amount(in_item) / recipe["inputs"][in_item]);
        var cap:int = b.production_cap(item);
        if cap > 0:
            crafts = mini(crafts, ceili(float(cap - Stock.amount(item)) / per));
        crafts = mini(crafts, b.free_space() / per);
        if crafts <= 0:
            continue;
        for in_item in recipe["inputs"]:
            b.take_input(in_item, recipe["inputs"][in_item] * crafts);
        var out:int = per * crafts;
        var space:int = b.reserve_space(out);
        var st:Dictionary = {"done": false};
        var label:String = "Splitting firewood" if item == &"firewood" else "Making a %s" % Defs.item_name(item).to_lower();
        var t:Task = Task.new(&"forge", label);
        t.job = _building_job(b);
        t.target = b;
        t.move_rect(b.rect(), b.is_walkable(), "Walking to %s" % b.display_name().to_lower());
        t.work_for(recipe["hours"] * crafts, label);
        t.act(func(_pw:Pawn) -> bool:
            st["done"] = true;
            b.release_space(space);
            b.store(item, out);
            return true);
        t.on_cancel = func(_pw:Pawn) -> void:
            if not st["done"] and World.alive(b):
                b.release_space(space);
                for in_item in recipe["inputs"]:
                    b.add_input(in_item, recipe["inputs"][in_item] * crafts);
        return t;
    return null;

# --------------------------------
# Mining

func miner_task(p:Pawn) -> Task:
    var sites:Array[Building] = [];
    for b in world.buildings:
        if b.is_complete() and b.def.get("profession", "") == "MINER":
            sites.append(b);
    sites.sort_custom(func(a:Building, c:Building) -> bool:
        return a.position.distance_squared_to(p.position) < c.position.distance_squared_to(p.position));
    for b in sites:
        if workers_at(b) >= b.def.get("worker_slots", 1):
            continue;
        var t:Task = _dig_task(p, b);
        if t != null:
            t.workplace = b;
            return t;
    return null;

# Digs a few units and carries them out. Iron comes first; stone once iron is at its cap or
# has nowhere to go.
func _dig_task(_p:Pawn, b:Building) -> Task:
    var item:StringName = &"";
    for candidate in [&"iron", &"coal", &"stone"]:
        if b.item_unlocked(candidate) and b.production_allowed(candidate) and Stock.has_room_for(candidate):
            item = candidate;
            break;
    if item == &"":
        return null;
    var n:int = Defs.MINE_BATCH;
    var cap:int = b.production_cap(item);
    if cap > 0:
        n = clampi(cap - Stock.amount(item), 1, n);
    var verb:String = "Quarrying" if item == &"stone" else "Mining";
    var t:Task = Task.new(&"dig", "%s %s" % [verb, Defs.item_name(item).to_lower()]);
    t.job = JobManager.Profession.MINER;
    t.target = b;
    t.move_rect(b.rect(), b.is_walkable(), "Walking to %s" % b.display_name().to_lower());
    var unit_hours:float = b.def["mine_hours"][item];
    var min_bonus:float = b.def.get("needs_tool", {}).get(item, 0.0);
    var dig:Callable = func(pw:Pawn, dh:float) -> bool:
        if not World.alive(b):
            return true;
        # progress lives on the mine, so a unit started before sleep or a meal is not lost
        var progress:float = b.dig_progress.get(item, 0.0) + dh * (1.0 if pw.tool_bonus() >= min_bonus - 0.001 else Defs.HARD_ORE_UNTOOLED_SPEED);
        while progress >= unit_hours and pw.carry_amount < n:
            progress -= unit_hours;
            pw.add_carry(item, 1);
        b.dig_progress[item] = progress;
        return pw.carry_amount >= n;
    t.work(dig);
    return t;

# With no mine to work at, miners gather loose rock and iron on the surface (iron first).
func surface_mine_task(p:Pawn) -> Task:
    for b in world.buildings:
        if b.is_complete() and b.def.get("profession", "") == "MINER" and workers_at(b) < b.def.get("worker_slots", 1):
            return null;
    for item in [&"iron", &"stone"]:
        var t:Task = harvest_node_task(p, func(rn:ResourceNode) -> bool:
            return rn.item == item);
        if t != null:
            return t;
    return null;

func _chop_task(p:Pawn, b:Building) -> Task:
    var mode:int = b.settings.get("chop", 0);
    if mode == 0:
        return null;
    return harvest_node_task(p, func(rn:ResourceNode) -> bool:
        return rn.is_tree() and in_radius(b, rn.cell) and (mode == 2 or rn.is_mature()));

func _plant_task(_p:Pawn, b:Building) -> Task:
    if not b.settings.get("plant", false):
        return null;
    var growing:int = 0;
    for rn in world.saplings:
        if in_radius(b, rn.cell):
            growing += 1;
    if growing + world.planting.size() >= 25:
        return null;
    var center:Vector2i = Vector2i(b.center_cell());
    var r:int = ceili(b.radius());
    var spot:Vector2i = Vector2i(-1, -1);
    for i in 30:
        var c:Vector2i = center + Vector2i(world.rng.randi_range(-r, r), world.rng.randi_range(-r, r));
        if in_radius(b, c) and world.can_plant_tree(c):
            spot = c;
            break;
    if spot.x < 0:
        return null;
    world.planting[spot] = true;
    var t:Task = Task.new(&"plant", "Planting a tree");
    t.job = JobManager.Profession.WOODCUTTER;
    t.target = b;
    t.move_cell(spot, "Walking to plant a tree");
    t.work_for(0.4, "Planting a tree", func(_pw:Pawn) -> void:
        world.planting.erase(spot);
        world.plant_tree(spot));
    t.on_cancel = func(_pw:Pawn) -> void:
        world.planting.erase(spot);
    return t;

# The job of the building's profession (a Blacksmith's crafting is smithing, the Woodcutter's splitting is woodcutting).
func _building_job(b:Building) -> int:
    return JobManager.PROFESSION_NAMES.find(String(b.def.get("profession", "")).capitalize());
