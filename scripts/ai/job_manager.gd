# ----------------------------------------------------------------
# JobManager
#     Decides what each pawn does next: urgent needs first, then
#     dropping off carried goods, sleep at night, then profession work
#     with general labor as the fallback.
# ----------------------------------------------------------------
class_name JobManager extends RefCounted;

enum Profession { LABORER, BUILDER, FARMER, GATHERER };

const PROFESSION_NAMES      :Array[String] = ["Laborer", "Builder", "Farmer", "Gatherer"];
const MAX_BUILDERS_PER_SITE :int = 4;
const FOOD_PER_PAWN_LOW     :int = 15;     # laborers forage when stock falls below this per pawn

var world:World;

func _init(w:World) -> void:
    world = w;

func choose_task(p:Pawn) -> Task:
    var t:Task = null;
    if not p.needs_blocked():
        var wants:bool = false;
        if p.thirst < 0.45:
            wants = true;
            t = _drink_task(p);
        if t == null and p.hunger < 0.4:
            wants = true;
            t = _eat_task(p);
        if t == null and p.warmth < 0.35:
            wants = true;
            t = _warm_task(p);
        if t != null:
            return t;
        if wants:
            p.block_needs(1.5);

    var night:bool = GameClock.is_night();
    if p.carry_amount > 0:
        if not night and p.carry_amount < Pawn.CARRY_CAP:
            t = _gather_more_task(p, p.carry_item);
            if t != null:
                return t;
        t = _deliver_task(p);
        if t != null:
            return t;
        p.clear_carry();    # nowhere to put it

    if night or p.energy < 0.15:
        t = _sleep_task(p);
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
            return [_build_task, _haul_task, _clear_task];
        Profession.FARMER:
            return [_farm_task, _haul_task, _clear_task];
        Profession.GATHERER:
            return [_forage_task, _clear_task, _haul_task];
    return [_clear_task, _haul_task, _build_task, _forage_if_hungry_task];

# --------------------------------
# Professions

func count(prof:int) -> int:
    var n:int = 0;
    for p in world.pawns:
        if p.profession == prof:
            n += 1;
    return n;

# Moves one pawn between a profession and the laborer pool.
func change_profession(prof:int, delta:int) -> void:
    if prof == Profession.LABORER:
        return;
    var from:int = Profession.LABORER if delta > 0 else prof;
    var to:int = prof if delta > 0 else Profession.LABORER;
    for p in world.pawns:
        if p.profession == from:
            p.profession = to;
            if p.task != null and p.task.interruptible:
                p.end_task(false);
            return;

# --------------------------------
# Needs

func _drink_task(p:Pawn) -> Task:
    var b:Building = world.nearest_building(p.position, func(x:Building) -> bool:
        return x.is_complete() and x.def.get("water", false));
    if b == null:
        return null;
    var t:Task = Task.new(&"drink", "Getting a drink", false);
    t.target = b;
    t.move_rect(b.rect(), b.is_walkable());
    t.work_for(0.25, "Drinking", func(pw:Pawn) -> void:
        pw.thirst = 1.0);
    return t;

func _eat_task(p:Pawn) -> Task:
    var item:StringName = Stock.best_food();
    var s:Building = world.nearest_storage(p.position);
    if item == &"" or s == null:
        return null;
    var nutrition:float = Defs.ITEMS[item]["nutrition"];
    var n:int = Stock.reserve(item, clampi(ceili((0.95 - p.hunger) / nutrition), 1, 4));
    if n == 0:
        return null;
    var st:Dictionary = {"taken": false};
    var t:Task = Task.new(&"eat", "Going to eat", false);
    t.target = s;
    t.move_rect(s.rect(), s.is_walkable());
    t.act(func(_pw:Pawn) -> bool:
        Stock.take_reserved(item, n);
        st["taken"] = true;
        return true);
    t.work_for(0.4, "Eating %s" % Defs.item_name(item), func(pw:Pawn) -> void:
        pw.hunger = minf(1.0, pw.hunger + nutrition * n));
    t.on_cancel = func(_pw:Pawn) -> void:
        if not st["taken"]:
            Stock.unreserve(item, n);
    return t;

func _warm_task(p:Pawn) -> Task:
    var b:Building = world.shelter_for(p);
    if b == null:
        return null;
    var t:Task = Task.new(&"warm", "Seeking warmth", false);
    t.target = b;
    t.move_rect(b.rect());
    t.act(func(pw:Pawn) -> bool:
        pw.go_inside(b, false);
        return true);
    var warm_tick:Callable = func(pw:Pawn, _dh:float) -> bool:
        return not World.alive(b) or pw.warmth >= 0.9;
    t.work(warm_tick, "Warming up");
    t.on_end = func(pw:Pawn) -> void:
        pw.go_outside();
    return t;

func _sleep_task(p:Pawn) -> Task:
    var b:Building = world.shelter_for(p);
    var t:Task = Task.new(&"sleep", "Going to bed", false);
    if b != null:
        t.target = b;
        t.move_rect(b.rect());
        t.act(func(pw:Pawn) -> bool:
            pw.go_inside(b, true);
            return true);
    else:
        t.act(func(pw:Pawn) -> bool:
            pw.sleeping = true;
            return true);
    var sleep_tick:Callable = func(pw:Pawn, _dh:float) -> bool:
        if b != null and not World.alive(b):
            return true;
        # wake at dawn, or mid-night if fully rested and hungry/thirsty
        if not GameClock.is_night() and pw.energy >= 0.95:
            return true;
        return pw.energy >= 1.0 and (pw.thirst < 0.2 or pw.hunger < 0.2);
    t.work(sleep_tick, "Sleeping");
    t.on_end = func(pw:Pawn) -> void:
        pw.sleeping = false;
        pw.go_outside();
    return t;

# --------------------------------
# Logistics

func _deliver_task(p:Pawn) -> Task:
    var s:Building = world.nearest_storage(p.position);
    if s == null:
        return null;
    var t:Task = Task.new(&"deliver", "Storing %s" % Defs.item_name(p.carry_item));
    t.target = s;
    t.move_rect(s.rect(), s.is_walkable());
    t.act(func(pw:Pawn) -> bool:
        Stock.add(pw.carry_item, pw.carry_amount);
        pw.clear_carry();
        return true);
    return t;

func _haul_task(p:Pawn) -> Task:
    var storage:Building = world.nearest_storage(p.position);
    if storage == null:
        return null;
    var best:Building = null;
    var best_item:StringName = &"";
    var best_d:float = INF;
    for b in world.buildings:
        if b.is_complete() or p.has_failed(b):
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
    var n:int = Stock.reserve(item, mini(Pawn.CARRY_CAP, b.remaining(item)));
    b.incoming[item] = b.incoming.get(item, 0) + n;
    var st:Dictionary = {"picked": false, "delivered": false};
    var t:Task = Task.new(&"haul", "Hauling %s to %s" % [Defs.item_name(item), b.display_name()]);
    t.target = b;
    t.move_rect(storage.rect(), storage.is_walkable(), "Fetching %s" % Defs.item_name(item));
    t.act(func(pw:Pawn) -> bool:
        pw.set_carry(item, Stock.take_reserved(item, n));
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
        if not st["picked"]:
            Stock.unreserve(item, n);
        if not st["delivered"] and World.alive(b):
            b.cancel_incoming(item, n);
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
    var verb:String = "Tilling" if b is Field else "Building";
    var t:Task = Task.new(&"build", "%s %s" % [verb, b.display_name()]);
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
    return _harvest_node_task(p, func(rn:ResourceNode) -> bool:
        return rn.designated);

func _forage_task(p:Pawn) -> Task:
    return _harvest_node_task(p, func(rn:ResourceNode) -> bool:
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
    return _harvest_node_task(p, same_item, 30.0);

func _harvest_node_task(p:Pawn, pred:Callable, max_dist:float = INF) -> Task:
    var best:ResourceNode = null;
    var best_d:float = max_dist * max_dist;
    var pc:Vector2 = Vector2(p.position.x, p.position.z);
    for rn in world.nodes:
        if rn.reserved_by != null or rn.amount <= 0 or not pred.call(rn) or p.has_failed(rn):
            continue;
        var d:float = pc.distance_squared_to(Vector2(rn.cell) + Vector2(0.5, 0.5));
        if d < best_d:
            best = rn;
            best_d = d;
    if best == null:
        return null;
    var rn:ResourceNode = best;
    rn.reserved_by = p;
    var st:Dictionary = {"acc": 0.0};
    var verb:String = rn.def.get("verb", "Gathering");
    var t:Task = Task.new(&"harvest", "%s (%s)" % [verb, rn.display_name()]);
    t.target = rn;
    t.move_cell(rn.cell, "Walking to %s" % rn.display_name().to_lower());
    t.work(func(pw:Pawn, dh:float) -> bool:
        if rn.removed or rn.amount <= 0:
            return true;
        st["acc"] += dh;
        while st["acc"] >= rn.work_per_unit and rn.amount > 0 and pw.carry_amount < Pawn.CARRY_CAP:
            st["acc"] -= rn.work_per_unit;
            rn.amount -= 1;
            pw.add_carry(rn.item, 1);
            world.node_changed(rn);
        return rn.amount <= 0 or pw.carry_amount >= Pawn.CARRY_CAP);
    t.on_end = func(_pw:Pawn) -> void:
        rn.reserved_by = null;
        if rn.amount <= 0 and not rn.regrows and not rn.removed:
            world.remove_node(rn);
    return t;

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
        var w:Dictionary = (b as Field).find_work(pc, only_action);
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
