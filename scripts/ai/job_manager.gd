# ----------------------------------------------------------------
# JobManager
#     Decides what each pawn does next: urgent needs first, then
#     dropping off carried goods, sleep at night, then profession work
#     with general labor as the fallback.
# ----------------------------------------------------------------
class_name JobManager extends TaskBase;

enum Profession { LABORER, BUILDER, FARMER, GATHERER, WOODCUTTER, MINER, BLACKSMITH, TEACHER };

const PROFESSION_NAMES      :Array[String] = ["Laborer", "Builder", "Farmer", "Gatherer", "Woodcutter", "Miner", "Blacksmith", "Teacher"];
const MAX_BUILDERS_PER_SITE :int = 4;
const FOOD_PER_PAWN_LOW     :int = 15;     # laborers forage when stock falls below this per pawn

var needs:NeedsTasks;
var school:SchoolTasks;
var production:ProductionTasks;
var targets:Dictionary = {};       # profession -> how many citizens the player wants in it

func _init(w:World) -> void:
    world = w;
    needs = NeedsTasks.new(w);
    school = SchoolTasks.new(w);
    production = ProductionTasks.new(w);

func choose_task(p:Pawn) -> Task:
    var t:Task = null;
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

    if p.is_baby():
        return needs.baby_task(p);

    var night:bool = GameClock.is_night();
    if p.carry_amount > 0:
        # no topping up the load when school is waiting for a child or the teacher
        if not night and p.carry_amount < Pawn.CARRY_CAP and not school.calls(p):
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

    if p.tool == &"":
        t = production.equip_task(p);
        if t != null:
            return t;

    if p.is_child():
        t = school.school_task(p);
        if t != null:
            return t;

    for job in _job_order(p.profession):
        t = (job as Callable).call(p);
        if t != null:
            return t;
    return _idle_task(p);

func _job_order(prof:int) -> Array[Callable]:
    match prof:
        Profession.BUILDER:
            return [_build_task, _haul_task, _fuel_task, _collect_task, _clear_task];
        Profession.FARMER:
            return [_farm_task, _haul_task, _fuel_task, _collect_task, _clear_task];
        Profession.GATHERER:
            return [_forage_task, _clear_task, _haul_task, _fuel_task, _collect_task];
        Profession.WOODCUTTER:
            return [production.woodcutter_task, _fuel_task, _haul_task, _collect_task, _clear_task];
        Profession.TEACHER:
            return [school.teach_task, _fuel_task, _haul_task, _collect_task, _clear_task];
        Profession.BLACKSMITH:
            return [production.blacksmith_task, _fuel_task, _haul_task, _collect_task, _clear_task];
        Profession.MINER:
            return [production.miner_task, production.surface_mine_task, _fuel_task, _haul_task, _collect_task, _clear_task];
    return [_fuel_task, production.supply_inputs_task, _clear_task, _haul_task, _collect_task, _build_task, _forage_if_hungry_task];

# --------------------------------
# Professions

# The player sets how many citizens should have each profession (a target); reconcile() moves citizens
# between the laborer pool and professions to match, and keeps doing so as citizens die or are born.
# A target the laborer pool can't fill stays and is filled as soon as someone is free.
func target(prof:int) -> int:
    return targets.get(prof, 0);

func change_profession(prof:int, delta:int) -> void:
    if prof == Profession.LABORER:
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
    for prof in PROFESSION_NAMES.size():
        if prof == Profession.LABORER:
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

func _haul_task(p:Pawn) -> Task:
    var best:Building = null;
    var best_item:StringName = &"";
    var best_d:float = INF;
    for b in world.buildings:
        if not b.is_site() or p.has_failed(b):
            continue;
        for item in b.cost():
            if b.remaining(item) > 0 and Stock.available(item) > 0:
                var d:float = b.position.distance_squared_to(p.position);
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

# Carries firewood from storage to the house that is lowest on it.
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
    var fuel_items:Array[StringName] = [&"firewood", &"coal"];
    match house.settings.get("fuel_type", 0):
        0: fuel_items = [&"firewood"];
        1: fuel_items = [&"coal"];
    var item:StringName = &"";
    var src:Building = null;
    for candidate in fuel_items:
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
        house.fuel = mini(house.def["fuel_capacity"], house.fuel + put * heat);
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

# --------------------------------
# Construction

func _build_task(p:Pawn) -> Task:
    var best:Building = null;
    var best_d:float = INF;
    for b in world.buildings:
        if b.builders >= MAX_BUILDERS_PER_SITE or p.has_failed(b) or not b.ready_for_work():
            continue;
        var d:float = b.position.distance_squared_to(p.position);
        if b is Field:
            d = Vector2(b.origin).distance_squared_to(Vector2(p.position.x, p.position.z));
        if d < best_d:
            best = b;
            best_d = d;
    if best == null:
        return null;
    var b:Building = best;
    b.builders += 1;
    var verb:String = "Tilling" if b is Field else "Upgrading" if b.upgrading != &"" else "Building";
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

# --------------------------------
# Gathering

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
    var best:Field = null;
    var best_work:Dictionary = {};
    var best_d:float = INF;
    var pc:Vector2i = p.cell();
    for b in world.buildings:
        if not (b is Field) or p.has_failed(b):
            continue;
        var w:Dictionary = (b as Field).find_work(pc, only_action, Stock.has_room_for);
        if w.is_empty():
            continue;
        var d:float = Vector2((b as Field).plot_cell(w["index"]) - pc).length_squared();
        if d < best_d:
            best = b as Field;
            best_work = w;
            best_d = d;
    if best == null:
        return null;
    var f:Field = best;
    var i:int = best_work["index"];
    var action:StringName = best_work["action"];
    f.reserved[i] = p;
    var verbs:Dictionary = {&"plant": "Planting", &"harvest": "Harvesting", &"clear": "Clearing dead crops"};
    var label:String = "%s %s" % [verbs[action], f.crop()["name"].to_lower()] if action == &"plant" else verbs[action];
    var t:Task = Task.new(&"farm", label);
    t.job = Profession.FARMER;
    t.target = f;
    t.move_cell(f.plot_cell(i), "Walking to field");
    t.work_for(Field.ACTION_HOURS[action], label, func(pw:Pawn) -> void:
        if World.alive(f):
            f.apply(i, action, pw));
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
