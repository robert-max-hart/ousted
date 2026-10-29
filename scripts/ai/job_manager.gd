# ----------------------------------------------------------------
# JobManager
#     Decides what each pawn does next: urgent needs first, then
#     dropping off carried goods, sleep at night, then profession work
#     with general labor as the fallback.
# ----------------------------------------------------------------
class_name JobManager extends TaskBase;

# GATHERER is retired (laborers harvest what is marked, food included); the slot stays so old saves and the
# experience of the "gathering" job keep their numbers, and reconcile() turns any left into laborers.
enum Profession { LABORER, BUILDER, FARMER, GATHERER, WOODCUTTER, MINER, BLACKSMITH, TEACHER, FORAGER };

const PROFESSION_NAMES      :Array[String] = ["Laborer", "Builder", "Farmer", "Gatherer", "Woodcutter", "Miner", "Blacksmith", "Teacher", "Forager"];
const MAX_BUILDERS_PER_SITE :int = 4;
const PRIORITY_WEIGHT       :float = 1.0e6;     # one build priority step outweighs any distance on the map
const FOOD_PER_PAWN_LOW     :int = 15;     # laborers forage when stock falls below this per pawn

var needs:NeedsTasks;
var school:SchoolTasks;
var burial:BurialTasks;
var herd:HerdTasks;
var trade:TradeTasks;
var production:ProductionTasks;
var targets:Dictionary = {};       # profession -> how many citizens the player wants in it

func _init(w:World) -> void:
    world = w;
    needs = NeedsTasks.new(w);
    school = SchoolTasks.new(w);
    burial = BurialTasks.new(w);
    herd = HerdTasks.new(w);
    trade = TradeTasks.new(w);
    production = ProductionTasks.new(w);

func choose_task(p:Pawn) -> Task:
    var t:Task = null;
    if p.is_baby():
        return needs.stay_home_task(p);     # a carer brings a baby what it needs
    if not p.needs_blocked():
        var wants:bool = false;
        if p.thirst < 0.45:
            wants = true;
            t = needs.drink_task(p);
        if t == null and p.hunger < 0.4:
            wants = true;
            t = needs.eat_task(p);
        if t == null and p.warmth < 0.35:
            wants = true;
            t = needs.warm_task(p);
        if t != null:
            return t;
        if wants:
            p.block_needs(1.5);

    var night:bool = GameClock.is_night();
    if p.carry_amount > 0:
        # no topping up the load when school is waiting for a child or the teacher
        if not night and p.carry_amount < Pawn.CARRY_CAP and not school.calls(p) and not _child_barred(p):
            t = _gather_more_task(p, p.carry_item);
            if t != null:
                return t;
        t = _deliver_task(p);
        if t != null:
            return t;
        world.drop_pile(p.carry_item, p.carry_amount, p.cell());    # nowhere to put it
        p.clear_carry();

    if night or p.energy < 0.15:
        t = needs.sleep_task(p);
        if t != null:
            return t;

    if p.is_adult():
        t = needs.care_task(p);
        if t != null:
            return t;
        t = burial.bury_task(p);     # kin first: laborers take over after a while (see Body.can_be_taken_by)
        if t != null:
            return t;

    if p.tool == &"":
        t = production.equip_task(p);
        if t != null:
            return t;

    if p.is_child():
        t = school.school_task(p);
        if t != null:
            return t;
        if _child_barred(p):
            return needs.stay_home_task(p);

    var own:Array[Callable] = _job_order(p.profession);
    for job in own:
        t = (job as Callable).call(p);
        if t != null:
            return t;
    if p.profession != Profession.LABORER:
        # nothing of their own to do: work as a laborer would (skipping what the list above already tried)
        for job in _job_order(Profession.LABORER):
            if own.has(job):
                continue;
            t = (job as Callable).call(p);
            if t != null:
                return t;
    return _idle_task(p);

func _job_order(prof:int) -> Array[Callable]:
    match prof:
        Profession.BUILDER:
            return [_build_task, _road_task, _haul_task, _fuel_task, _collect_task, _clear_task];
        Profession.FARMER:
            return [_farm_task, _herd_task, _haul_task, _fuel_task, _collect_task, _clear_task];
        Profession.WOODCUTTER:
            return [production.woodcutter_task, _fuel_task, _haul_task, _collect_task, _clear_task];
        Profession.FORAGER:
            return [production.forager_task, _forage_task, _fuel_task, _haul_task, _collect_task, _clear_task];
        Profession.TEACHER:
            return [school.teach_task, _fuel_task, _haul_task, _collect_task, _clear_task];
        Profession.BLACKSMITH:
            return [production.blacksmith_task, _fuel_task, _haul_task, _collect_task, _clear_task];
        Profession.MINER:
            return [production.miner_task, production.surface_mine_task, _fuel_task, _haul_task, _collect_task, _clear_task];
    return [_fuel_task, production.supply_inputs_task, _clear_task, _haul_task, _collect_task, _herd_task, trade.trade_task, _build_task, _road_task, _forage_if_hungry_task, _rebalance_task];

# --------------------------------
# Professions

# The player sets how many citizens should have each profession (a target); reconcile() moves citizens
# between the laborer pool and professions to match, and keeps doing so as citizens die or are born.
# A target the laborer pool can't fill stays and is filled as soon as someone is free.
func target(prof:int) -> int:
    return targets.get(prof, 0);

func change_profession(prof:int, delta:int) -> void:
    if prof == Profession.LABORER or prof == Profession.GATHERER:
        return;
    targets[prof] = clampi(target(prof) + delta, 0, maxi(world.pawns.size(), count(prof)));
    reconcile();

# Makes the targets match who has which profession now (after setup, a load, or direct assignment).
func sync_targets() -> void:
    targets.clear();
    for p in world.pawns:
        if p.profession != Profession.LABORER:
            targets[p.profession] = targets.get(p.profession, 0) + 1;

func reconcile() -> void:
    targets.erase(Profession.GATHERER);
    for p in world.pawns:
        if p.profession == Profession.GATHERER:
            p.profession = Profession.LABORER;
    for prof in PROFESSION_NAMES.size():
        if prof == Profession.LABORER or prof == Profession.GATHERER:
            continue;
        var have:int = count(prof);
        while have > target(prof):
            _assign(_least_experienced(prof), Profession.LABORER);
            have -= 1;
        while have < target(prof):
            var p:Pawn = _most_experienced_laborer(prof);
            if p == null:
                break;
            _assign(p, prof);
            have += 1;

# Adding to a profession takes the adult laborer with the most experience in it, removing takes the member with
# the least. Ties fall back to list order.
func _most_experienced_laborer(prof:int) -> Pawn:
    var best:Pawn = null;
    for p in world.pawns:
        if p.profession == Profession.LABORER and p.is_adult() and (best == null or p.experience(prof) > best.experience(prof)):
            best = p;
    return best;

func _least_experienced(prof:int) -> Pawn:
    var best:Pawn = null;
    for p in world.pawns:
        if p.profession == prof and (best == null or p.experience(prof) < best.experience(prof)):
            best = p;
    return best;

# A child who may not work (the child labor policy is off).
func _child_barred(p:Pawn) -> bool:
    return p.is_child() and not world.policies.is_on(&"child_labor");

# Forbidding child labor sends working children home at once; school and needs are left alone.
func on_policy_changed(id:StringName) -> void:
    if id != &"child_labor" or world.policies.is_on(id):
        return;
    for p in world.pawns:
        if p.is_child() and p.task != null and p.task.interruptible and p.task.kind != &"school" and p.task.kind != &"stay_home":
            p.end_task(false);

func _assign(p:Pawn, prof:int) -> void:
    p.profession = prof;
    if p.task != null and p.task.interruptible:
        p.end_task(false);

# --------------------------------
# Logistics

func _deliver_task(p:Pawn) -> Task:
    var item:StringName = p.carry_item;
    var s:Building = world.nearest_storage_for(item, p.position);
    if s == null:
        return null;
    var n:int = s.reserve_space(p.carry_amount);
    if n == 0:
        return null;
    var st:Dictionary = {"done": false};
    var t:Task = Task.new(&"deliver", "Storing %s" % Defs.item_name(item));
    t.target = s;
    t.move_rect(s.rect(), s.is_walkable());
    t.act(func(pw:Pawn) -> bool:
        s.release_space(n);
        st["done"] = true;
        var put:int = s.store(item, mini(n, pw.carry_amount));
        if put >= pw.carry_amount:
            pw.clear_carry();
        else:
            pw.set_carry(item, pw.carry_amount - put);
        return true);
    t.on_cancel = func(_pw:Pawn) -> void:
        if not st["done"] and World.alive(s):
            s.release_space(n);
    return t;

# With nothing more urgent to do, a laborer carries goods from a store that suits them badly to one that suits
# them better: food into a Granary, firewood to the woodcutter, anything out of a store that now forbids it.
const REBALANCE_MARGIN:float = 0.5;

func _rebalance_task(p:Pawn) -> Task:
    var from:Building = null;
    var to:Building = null;
    var item:StringName = &"";
    var best_gain:float = REBALANCE_MARGIN;
    for s in world.buildings:
        if not s.is_storage() or s.def.get("temporary", false) or p.has_failed(s):
            continue;
        for it in s.stored:
            if s.available(it) <= 0:
                continue;
            var here:float = s.storage_rank(it);
            for d in world.buildings:
                if d == s or not d.can_store(it) or p.has_failed(d):
                    continue;
                var gain:float = here - d.storage_rank(it);
                if gain > best_gain:
                    best_gain = gain;
                    from = s;
                    to = d;
                    item = it;
    if from == null:
        return null;
    var n:int = from.reserve_out(item, mini(Pawn.CARRY_CAP, to.free_space()));
    if n == 0:
        return null;
    to.reserve_space(n);
    var st:Dictionary = {"picked": false, "done": false};
    var name:String = Defs.item_name(item).to_lower();
    var t:Task = Task.new(&"rebalance", "Moving %s to %s" % [name, to.display_name()]);
    t.target = to;
    t.related = from;
    t.move_rect(from.rect(), from.is_walkable(), "Fetching %s" % name);
    t.act(func(pw:Pawn) -> bool:
        pw.set_carry(item, from.take_reserved(item, n));
        st["picked"] = true;
        return true);
    t.move_rect(to.rect(), to.is_walkable(), "Moving %s to %s" % [name, to.display_name()]);
    t.act(func(pw:Pawn) -> bool:
        to.release_space(n);
        st["done"] = true;
        var put:int = to.store(item, mini(n, pw.carry_amount));
        if put >= pw.carry_amount:
            pw.clear_carry();
        else:
            pw.set_carry(item, pw.carry_amount - put);
        return true);
    t.on_cancel = func(_pw:Pawn) -> void:
        if not st["picked"] and World.alive(from):
            from.release_out(item, n);
        if not st["done"] and World.alive(to):
            to.release_space(n);
    return t;

func _haul_task(p:Pawn) -> Task:
    var best:Building = null;
    var best_item:StringName = &"";
    var best_d:float = INF;
    for b in world.buildings:
        if not b.is_site() or b.is_paused() or p.has_failed(b):
            continue;
        for item in b.cost():
            if b.remaining(item) > 0 and Stock.available(item) > 0:
                var d:float = b.position.distance_squared_to(p.position) - b.priority * PRIORITY_WEIGHT;
                if d < best_d:
                    best = b;
                    best_item = item;
                    best_d = d;
                break;
    if best == null:
        return null;
    var b:Building = best;
    var item:StringName = best_item;
    var storage:Building = world.nearest_storage_with(item, p.position);
    if storage == null:
        return null;
    var n:int = storage.reserve_out(item, mini(Pawn.CARRY_CAP, b.remaining(item)));
    if n == 0:
        return null;
    b.incoming[item] = b.incoming.get(item, 0) + n;
    var st:Dictionary = {"picked": false, "delivered": false};
    var t:Task = Task.new(&"haul", "Hauling %s to %s" % [Defs.item_name(item), b.display_name()]);
    t.target = b;
    t.move_rect(storage.rect(), storage.is_walkable(), "Fetching %s" % Defs.item_name(item));
    t.act(func(pw:Pawn) -> bool:
        pw.set_carry(item, storage.take_reserved(item, n));
        st["picked"] = true;
        return true);
    t.move_rect(b.rect(), b.is_walkable());
    t.act(func(pw:Pawn) -> bool:
        if not World.alive(b):
            return false;
        b.receive(item, pw.carry_amount);
        b.cancel_incoming(item, n - pw.carry_amount);
        pw.clear_carry();
        st["delivered"] = true;
        return true);
    t.on_cancel = func(_pw:Pawn) -> void:
        if not st["picked"] and World.alive(storage):
            storage.release_out(item, n);
        if not st["delivered"] and World.alive(b):
            b.cancel_incoming(item, n);
    return t;

# Carries fuel from storage to the house that is lowest on it. Raw wood is the last resort: only in the cold,
# for a house under half its target, and never when it is set to burn coal only.
func _fuel_items(house:Building) -> Array[StringName]:
    var items:Array[StringName] = [&"firewood", &"coal"];
    match house.settings.get("fuel_type", 0):
        0: items = [&"firewood"];
        1: items = [&"coal"];
    var target:float = house.settings.get("fuel_target", 1);
    var short:bool = float(house.fuel + house.fuel_incoming) < target * Defs.WOOD_FUEL_BELOW_SHARE;
    if house.settings.get("fuel_type", 0) != 1 and short and Weather.temperature < Defs.HEATING_BELOW:
        items.append(&"wood");
    return items;

# Carries fuel from storage to the house that is lowest on it.
func _fuel_task(p:Pawn) -> Task:
    var best:Building = null;
    var best_ratio:float = INF;
    for b in world.buildings:
        if b.fuel_wanted() <= 0 or p.has_failed(b):
            continue;
        var ratio:float = float(b.fuel + b.fuel_incoming) / maxf(1.0, b.settings.get("fuel_target", 1));
        if ratio < best_ratio:
            best = b;
            best_ratio = ratio;
    if best == null:
        return null;
    var house:Building = best;
    var item:StringName = &"";
    var src:Building = null;
    for candidate in _fuel_items(house):
        src = world.nearest_storage_with(candidate, p.position);
        if src != null:
            item = candidate;
            break;
    if src == null:
        return null;
    var heat:int = Defs.ITEMS[item]["heat"];
    var n:int = src.reserve_out(item, mini(Pawn.CARRY_CAP, ceili(float(house.fuel_wanted()) / heat)));
    if n == 0:
        return null;
    house.fuel_incoming += n * heat;
    var st:Dictionary = {"picked": false, "done": false};
    var name:String = Defs.item_name(item).to_lower();
    var t:Task = Task.new(&"fuel", "Bringing %s to a house" % name);
    t.target = house;
    t.move_rect(src.rect(), src.is_walkable(), "Fetching %s" % name);
    t.act(func(pw:Pawn) -> bool:
        pw.set_carry(item, src.take_reserved(item, n));
        st["picked"] = true;
        return true);
    t.move_rect(house.rect(), house.is_walkable(), "Bringing %s to a house" % name);
    t.act(func(pw:Pawn) -> bool:
        st["done"] = true;
        house.fuel_incoming = maxi(0, house.fuel_incoming - n * heat);
        var room:int = maxi(0, house.def["fuel_capacity"] - house.fuel);
        var put:int = mini(ceili(float(room) / heat), pw.carry_amount);
        house.add_fuel(item, put * heat);
        if put >= pw.carry_amount:
            pw.clear_carry();
        else:
            pw.set_carry(item, pw.carry_amount - put);
        return true);
    t.on_cancel = func(_pw:Pawn) -> void:
        if not st["picked"] and World.alive(src):
            src.release_out(item, n);
        if not st["done"] and World.alive(house):
            house.fuel_incoming = maxi(0, house.fuel_incoming - n * heat);
    return t;

# Picks up goods lying on the ground (see GroundPile) so they can be stored once there is room.
func _collect_task(p:Pawn) -> Task:
    var best:GroundPile = null;
    var best_d:float = INF;
    var pc:Vector2 = Vector2(p.position.x, p.position.z);
    for pl in world.piles:
        if pl.reserved_by != null or pl.removed or p.has_failed(pl) or not Stock.has_room_for(pl.item):
            continue;
        var d:float = pc.distance_squared_to(Vector2(pl.cell) + Vector2(0.5, 0.5));
        if d < best_d:
            best = pl;
            best_d = d;
    if best == null:
        return null;
    var pl:GroundPile = best;
    pl.reserved_by = p;
    var t:Task = Task.new(&"collect", "Collecting %s" % Defs.item_name(pl.item));
    t.target = pl;
    t.move_cell(pl.cell, "Walking to %s" % pl.display_name().to_lower());
    t.act(func(pw:Pawn) -> bool:
        if pl.removed or pl.amount <= 0:
            return false;
        pw.set_carry(pl.item, pl.take(Pawn.CARRY_CAP));
        if pl.amount <= 0:
            world.remove_pile(pl);
        return true);
    t.on_end = func(_pw:Pawn) -> void:
        # a pile emptied by this very task is freed here, once nothing captures it any more
        if pl.removed:
            pl.queue_free();
        else:
            pl.reserved_by = null;
    return t;

# Positions in this profession's finished buildings (0 for professions with no job buildings). A field counts
# as a farmer position for each Defs.PLOTS_PER_FARMER plots.
func total_slots(prof:int) -> int:
    var slots:int = 0;
    for b in world.buildings:
        if prof == Profession.FARMER and b is Field and b.is_complete():
            slots += (b as Field).farmer_positions();
        if b.is_complete() and b.def.has("worker_slots") and JobManager.PROFESSION_NAMES.find(String(b.def.get("profession", "")).capitalize()) == prof:
            slots += b.def["worker_slots"];
    return slots;

# Positions in the profession's buildings that no citizen of the profession fills.
func open_slots(prof:int) -> int:
    return maxi(0, total_slots(prof) - count(prof));

# --------------------------------
# Construction

func _build_task(p:Pawn) -> Task:
    var best:Building = null;
    var best_d:float = INF;
    for b in world.buildings:
        if b.builders >= MAX_BUILDERS_PER_SITE or b.is_paused() or p.has_failed(b) or not b.ready_for_work():
            continue;
        var d:float = b.position.distance_squared_to(p.position);
        if b is Field:
            d = Vector2(b.origin).distance_squared_to(Vector2(p.position.x, p.position.z));
        d -= b.priority * PRIORITY_WEIGHT;
        if d < best_d:
            best = b;
            best_d = d;
    if best == null:
        return null;
    var b:Building = best;
    b.builders += 1;
    var verb:String = "Tilling" if b is Field else "Expanding" if b.upgrading == Expansion.ID else "Upgrading" if b.upgrading != &"" else "Building";
    var t:Task = Task.new(&"build", "%s %s" % [verb, b.display_name()]);
    t.job = Profession.BUILDER;
    t.target = b;
    t.move_rect(b.rect(), b.is_walkable(), "Walking to %s" % b.display_name());
    t.work(func(_pw:Pawn, dh:float) -> bool:
        if not World.alive(b):
            return true;
        return b.add_work(dh));
    t.on_end = func(_pw:Pawn) -> void:
        if World.alive(b):
            b.builders -= 1;
    return t;

# Lays a staked road cell (World.road_work): the nearest one nobody is working on.
func _road_task(p:Pawn) -> Task:
    var best:Vector2i = Vector2i.ZERO;
    var best_d:float = INF;
    var pc:Vector2 = Vector2(p.position.x, p.position.z);
    for c in world.road_work:
        if world.road_claimed.has(c) or p.has_failed(c):
            continue;
        var d:float = pc.distance_squared_to(Vector2(c) + Vector2(0.5, 0.5));
        if d < best_d:
            best = c;
            best_d = d;
    if best_d == INF:
        return null;
    var cell:Vector2i = best;
    world.road_claimed[cell] = true;
    var t:Task = Task.new(&"road", "Digging a channel" if world.road_kind.get(cell, Terrain.Overlay.ROAD) == Terrain.Overlay.CHANNEL else "Laying road");
    t.job = Profession.BUILDER;
    t.move_cell(cell, "Walking to the work");
    t.work(func(_pw:Pawn, dh:float) -> bool:
        return world.work_road(cell, dh));
    t.on_end = func(_pw:Pawn) -> void:
        world.road_claimed.erase(cell);
    return t;

# --------------------------------
# Gathering

# Farm animals: collect what is ready, else bring grain to a herd that is short of it.
func _herd_task(p:Pawn) -> Task:
    var t:Task = herd.collect_task(p);
    if t != null:
        return t;
    for b in world.buildings:
        if b is Pasture and b.is_complete() and not p.has_failed(b) and not b.inputs_wanted().is_empty():
            t = production._stock_inputs_task(p, b);
            if t != null:
                return t;
    return null;

func _clear_task(p:Pawn) -> Task:
    return harvest_node_task(p, func(rn:ResourceNode) -> bool:
        return rn.designated);

func _forage_task(p:Pawn) -> Task:
    return harvest_node_task(p, func(rn:ResourceNode) -> bool:
        return rn.is_auto());

func _forage_if_hungry_task(p:Pawn) -> Task:
    if Stock.food_total() >= world.pawns.size() * FOOD_PER_PAWN_LOW:
        return null;
    return _forage_task(p);

# Keep filling our hands with the same item before walking back.
func _gather_more_task(p:Pawn, item:StringName) -> Task:
    for crop_id in Defs.CROPS:
        if Defs.CROPS[crop_id]["item"] == item:
            return _farm_task(p, &"harvest");
    var same_item:Callable = func(rn:ResourceNode) -> bool:
        return rn.item == item and (rn.designated or rn.is_auto());
    return harvest_node_task(p, same_item, 30.0);

# --------------------------------
# Farming

func _farm_task(p:Pawn, only_action:StringName = &"") -> Task:
    var well:Building = world.nearest_building(p.position, func(x:Building) -> bool:
        return x.is_complete() and x.def.get("water", false));
    var manure_src:Building = world.nearest_storage_with(&"manure", p.position);
    var best:Field = null;
    var best_work:Dictionary = {};
    var best_d:float = INF;
    var pc:Vector2i = p.cell();
    for b in world.buildings:
        if not (b is Field) or p.has_failed(b):
            continue;
        var w:Dictionary = (b as Field).find_work(pc, only_action, Stock.has_room_for, well != null, manure_src != null);
        if w.is_empty():
            continue;
        if w["rank"] < best_d:
            best = b as Field;
            best_work = w;
            best_d = w["rank"];
    if best == null:
        return null;
    var f:Field = best;
    var i:int = best_work["index"];
    var action:StringName = best_work["action"];
    f.reserved[i] = p;
    var verbs:Dictionary = {&"plant": "Planting", &"harvest": "Harvesting", &"clear": "Clearing dead crops", &"water": "Watering", &"treat": "Picking off pests", &"manure": "Spreading manure"};
    var load:Dictionary = {"n": 0, "picked": false};
    if action == &"manure":         # one load of manure from storage
        load["n"] = manure_src.reserve_out(&"manure", 1);
        if load["n"] == 0:
            f.reserved[i] = null;
            return null;
    var label:String = "%s %s" % [verbs[action], f.crop()["name"].to_lower()] if action == &"plant" else verbs[action];
    var t:Task = Task.new(&"farm", label);
    t.job = Profession.FARMER;
    t.target = f;
    if action == &"manure":
        t.related = manure_src;
        t.move_rect(manure_src.rect(), manure_src.is_walkable(), "Fetching manure");
        t.act(func(pw:Pawn) -> bool:
            load["picked"] = true;
            var got:int = manure_src.take_reserved(&"manure", load["n"]);
            if got < 1:
                return false;
            pw.set_carry(&"manure", got);
            return true);
    if action == &"water":         # fill a bucket at the well first
        t.related = well;
        t.move_rect(well.rect(), well.is_walkable(), "Fetching water");
        t.work_for(0.1, "Filling a bucket");
    t.move_cell(f.plot_cell(i), "Walking to field");
    t.work_for(Field.ACTION_HOURS[action], label, func(pw:Pawn) -> void:
        if World.alive(f):
            f.apply(i, action, pw);
        if action == &"manure":
            pw.clear_carry());
    t.on_cancel = func(_pw:Pawn) -> void:
        if action == &"manure" and not load["picked"] and World.alive(manure_src):
            manure_src.release_out(&"manure", load["n"]);
    t.on_end = func(_pw:Pawn) -> void:
        if World.alive(f):
            f.reserved[i] = null;
    return t;

# --------------------------------
# Idle

func _idle_task(p:Pawn) -> Task:
    var center:Vector2i = world.town_hall.origin + Vector2i(2, 2) if World.alive(world.town_hall) else p.cell();
    var c:Vector2i = center + Vector2i(world.rng.randi_range(-7, 7), world.rng.randi_range(-7, 7));
    var t:Task = Task.new(&"idle", "Idle");
    t.move_cell(c, "Wandering");
    t.work_for(1.0, "Idle");
    return t;
