# ----------------------------------------------------------------
# JobManager
#     Decides what each pawn does next: urgent needs first, then
#     dropping off carried goods, sleep at night, then profession work
#     with general labor as the fallback.
# ----------------------------------------------------------------
class_name JobManager extends RefCounted;

enum Profession { LABORER, BUILDER, FARMER, GATHERER, WOODCUTTER, MINER, BLACKSMITH, TEACHER };

const PROFESSION_NAMES      :Array[String] = ["Laborer", "Builder", "Farmer", "Gatherer", "Woodcutter", "Miner", "Blacksmith", "Teacher"];
const MAX_BUILDERS_PER_SITE :int = 4;
const TEACHER_EARLY        :float = 0.5;   # hours before school starts that the teacher heads over
const FOOD_PER_PAWN_LOW     :int = 15;     # laborers forage when stock falls below this per pawn

var world:World;
var targets:Dictionary = {};       # profession -> how many citizens the player wants in it

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

    if p.is_baby():
        return _baby_task(p);

    var night:bool = GameClock.is_night();
    if p.carry_amount > 0:
        # no topping up the load when school is waiting for a child or the teacher
        if not night and p.carry_amount < Pawn.CARRY_CAP and not _school_calls(p):
            t = _gather_more_task(p, p.carry_item);
            if t != null:
                return t;
        t = _deliver_task(p);
        if t != null:
            return t;
        world.drop_pile(p.carry_item, p.carry_amount, p.cell());    # nowhere to put it
        p.clear_carry();

    if night or p.energy < 0.15:
        t = _sleep_task(p);
        if t != null:
            return t;

    if p.tool == &"":
        t = _equip_task(p);
        if t != null:
            return t;

    if p.is_child():
        t = _school_task(p);
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
            return [_woodcutter_task, _fuel_task, _haul_task, _collect_task, _clear_task];
        Profession.TEACHER:
            return [_teach_task, _fuel_task, _haul_task, _collect_task, _clear_task];
        Profession.BLACKSMITH:
            return [_blacksmith_task, _fuel_task, _haul_task, _collect_task, _clear_task];
        Profession.MINER:
            return [_miner_task, _surface_mine_task, _fuel_task, _haul_task, _collect_task, _clear_task];
    return [_fuel_task, _supply_inputs_task, _clear_task, _haul_task, _collect_task, _build_task, _forage_if_hungry_task];

# --------------------------------
# Professions

func count(prof:int) -> int:
    var n:int = 0;
    for p in world.pawns:
        if p.profession == prof:
            n += 1;
    return n;

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

# Experience does not exist yet, so ties (everyone) fall back to list order.
func _most_experienced_laborer(_prof:int) -> Pawn:
    for p in world.pawns:
        if p.profession == Profession.LABORER and p.is_adult():
            return p;
    return null;

func _least_experienced(prof:int) -> Pawn:
    for p in world.pawns:
        if p.profession == prof:
            return p;
    return null;

func _assign(p:Pawn, prof:int) -> void:
    p.profession = prof;
    if p.task != null and p.task.interruptible:
        p.end_task(false);

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
    if item == &"":
        return null;
    var s:Building = world.nearest_storage_with(item, p.position);
    if s == null:
        return null;
    var nutrition:float = Defs.ITEMS[item]["nutrition"];
    var n:int = s.reserve_out(item, clampi(ceili((0.95 - p.hunger) / nutrition), 1, 4));
    if n == 0:
        return null;
    var st:Dictionary = {"taken": false};
    var t:Task = Task.new(&"eat", "Going to eat", false);
    t.target = s;
    t.move_rect(s.rect(), s.is_walkable());
    t.act(func(_pw:Pawn) -> bool:
        s.take_reserved(item, n);
        st["taken"] = true;
        return true);
    t.work_for(0.4, "Eating %s" % Defs.item_name(item), func(pw:Pawn) -> void:
        pw.hunger = minf(1.0, pw.hunger + nutrition * n));
    t.on_cancel = func(_pw:Pawn) -> void:
        if not st["taken"] and World.alive(s):
            s.release_out(item, n);
    return t;

func _warm_task(p:Pawn) -> Task:
    var b:Building = world.warm_shelter_for(p);
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

# Babies never work and never leave the house: they go indoors and stay there.
func _baby_task(p:Pawn) -> Task:
    var b:Building = world.shelter_for(p);
    var t:Task = Task.new(&"stay_home", "Staying home", false);
    if b != null and not (p.indoors and is_same(p.shelter, b)):
        t.target = b;
        t.move_rect(b.rect());
        t.act(func(pw:Pawn) -> bool:
            pw.go_inside(b, false);
            return true);
    t.work_for(1.0, "Staying home");
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
    var room:Dictionary = {};     # item -> whether any storage has space (checked once per item)
    for rn in world.nodes:
        if rn.reserved_by != null or rn.amount <= 0 or not pred.call(rn) or p.has_failed(rn):
            continue;
        if not room.has(rn.item):
            room[rn.item] = Stock.has_room_for(rn.item);
        if not room[rn.item]:
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
# Woodcutting

func _woodcutter_task(p:Pawn) -> Task:
    var sites:Array[Building] = [];
    for b in world.buildings:
        if b.is_complete() and b.def.get("profession", "") == "WOODCUTTER":
            sites.append(b);
    sites.sort_custom(func(a:Building, c:Building) -> bool:
        return a.position.distance_squared_to(p.position) < c.position.distance_squared_to(p.position));
    for b in sites:
        if _workers_at(b) >= b.def.get("worker_slots", 1):
            continue;
        for job in [_chop_task, _forge_task, _stock_inputs_task, _plant_task]:
            var t:Task = (job as Callable).call(p, b);
            if t != null:
                t.workplace = b;
                return t;
    return null;

# --------------------------------
# School

# Whether it is school time for this citizen: a child, or the teacher, with a school standing.
func _school_calls(p:Pawn) -> bool:
    if not (_school_hours() or (p.profession == Profession.TEACHER and GameClock.hour() >= Defs.SCHOOL_START - TEACHER_EARLY and GameClock.hour() < Defs.SCHOOL_END)):
        return false;
    if not (p.is_child() or p.profession == Profession.TEACHER):
        return false;
    for b in world.buildings:
        if b.is_complete() and b.def.has("school_capacity"):
            return true;
    return false;

func _school_hours() -> bool:
    var h:float = GameClock.hour();
    return h >= Defs.SCHOOL_START and h < Defs.SCHOOL_END;

# A teacher works the school during school hours as long as there are children to teach.
func _teach_task(p:Pawn) -> Task:
    var h:float = GameClock.hour();
    if h < Defs.SCHOOL_START - TEACHER_EARLY or h >= Defs.SCHOOL_END:     # the teacher is in place when the bell rings
        return null;
    var has_children:bool = false;
    for pw in world.pawns:
        if pw.is_child():
            has_children = true;
            break;
    if not has_children:
        return null;
    var sites:Array[Building] = [];
    for b in world.buildings:
        if b.is_complete() and b.def.has("school_capacity") and _workers_at(b) < b.def.get("worker_slots", 1):
            sites.append(b);
    sites.sort_custom(func(a:Building, c:Building) -> bool:
        return a.position.distance_squared_to(p.position) < c.position.distance_squared_to(p.position));
    if sites.is_empty():
        return null;
    var school:Building = sites[0];
    var t:Task = Task.new(&"teach", "Teaching");
    t.target = school;
    t.workplace = school;
    t.move_rect(school.rect(), school.is_walkable(), "Walking to school");
    t.act(func(_pw:Pawn) -> bool:
        school.teaching = true;
        return true);
    var teach_tick:Callable = func(_pw:Pawn, _dh:float) -> bool:
        if not World.alive(school) or GameClock.hour() >= Defs.SCHOOL_END or GameClock.hour() < Defs.SCHOOL_START - TEACHER_EARLY:
            return true;
        for pw in world.pawns:
            if pw.is_child():
                return false;
        return true;
    t.work(teach_tick, "Teaching");
    t.on_end = func(_pw:Pawn) -> void:
        if World.alive(school):
            school.teaching = false;
    return t;

# A child goes to a school with a free seat while it is school hours and the colony has a teacher. School
# comes before child labor; if the teacher never turns up, the child gives up and works instead.
func _school_task(p:Pawn) -> Task:
    if not _school_hours() or count(Profession.TEACHER) == 0:
        return null;
    var school:Building = world.nearest_building(p.position, func(b:Building) -> bool:
        return b.is_complete() and b.def.has("school_capacity") and b.attendees < b.def["school_capacity"] and not p.has_failed(b));
    if school == null:
        return null;
    school.attendees += 1;
    var t:Task = Task.new(&"school", "Going to school");
    t.target = school;
    t.move_rect(school.rect(), school.is_walkable(), "Going to school");
    var st:Dictionary = {"waited": 0.0};
    var study:Callable = func(pw:Pawn, dh:float) -> bool:
        if not World.alive(school) or not _school_hours():
            return true;
        if not school.teaching:
            st["waited"] += dh;
            if st["waited"] > 1.5:
                pw.avoid(school, 3.0);
                return true;
            return false;
        pw.learn(dh);
        return false;
    t.work(study, "Studying");
    t.on_end = func(_pw:Pawn) -> void:
        if World.alive(school):
            school.attendees = maxi(0, school.attendees - 1);
    return t;

# --------------------------------
# Tools

# Fetches the best tool in storage for a citizen who has none.
func _equip_task(p:Pawn) -> Task:
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
func _supply_inputs_task(p:Pawn) -> Task:
    for b in world.buildings:
        if not b.is_complete() or p.has_failed(b) or b.inputs_wanted().is_empty():
            continue;
        var t:Task = _stock_inputs_task(p, b);
        if t != null:
            return t;
    return null;

func _blacksmith_task(p:Pawn) -> Task:
    var sites:Array[Building] = [];
    for b in world.buildings:
        if b.is_complete() and b.def.get("profession", "") == "BLACKSMITH":
            sites.append(b);
    sites.sort_custom(func(a:Building, c:Building) -> bool:
        return a.position.distance_squared_to(p.position) < c.position.distance_squared_to(p.position));
    for b in sites:
        if _workers_at(b) >= b.def.get("worker_slots", 1):
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
    for item in b.def["recipes"]:
        var recipe:Dictionary = b.def["recipes"][item];
        if not b.recipe_enabled(item):
            continue;
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

func _miner_task(p:Pawn) -> Task:
    var sites:Array[Building] = [];
    for b in world.buildings:
        if b.is_complete() and b.def.get("profession", "") == "MINER":
            sites.append(b);
    sites.sort_custom(func(a:Building, c:Building) -> bool:
        return a.position.distance_squared_to(p.position) < c.position.distance_squared_to(p.position));
    for b in sites:
        if _workers_at(b) >= b.def.get("worker_slots", 1):
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
func _surface_mine_task(p:Pawn) -> Task:
    for b in world.buildings:
        if b.is_complete() and b.def.get("profession", "") == "MINER" and _workers_at(b) < b.def.get("worker_slots", 1):
            return null;
    for item in [&"iron", &"stone"]:
        var t:Task = _harvest_node_task(p, func(rn:ResourceNode) -> bool:
            return rn.item == item);
        if t != null:
            return t;
    return null;

func _workers_at(b:Building) -> int:
    var n:int = 0;
    for pw in world.pawns:
        if pw.task != null and is_same(pw.task.workplace, b):
            n += 1;
    return n;

func _in_radius(b:Building, c:Vector2i) -> bool:
    return b.center_cell().distance_to(Vector2(c) + Vector2(0.5, 0.5)) <= b.radius();

func _chop_task(p:Pawn, b:Building) -> Task:
    var mode:int = b.settings.get("chop", 0);
    if mode == 0:
        return null;
    return _harvest_node_task(p, func(rn:ResourceNode) -> bool:
        return rn.kind == &"tree" and _in_radius(b, rn.cell) and (mode == 2 or rn.is_mature()));

func _plant_task(_p:Pawn, b:Building) -> Task:
    if not b.settings.get("plant", false):
        return null;
    var growing:int = 0;
    for rn in world.saplings:
        if _in_radius(b, rn.cell):
            growing += 1;
    if growing + world.planting.size() >= 25:
        return null;
    var center:Vector2i = Vector2i(b.center_cell());
    var r:int = ceili(b.radius());
    var spot:Vector2i = Vector2i(-1, -1);
    for i in 30:
        var c:Vector2i = center + Vector2i(world.rng.randi_range(-r, r), world.rng.randi_range(-r, r));
        if _in_radius(b, c) and world.can_plant_tree(c):
            spot = c;
            break;
    if spot.x < 0:
        return null;
    world.planting[spot] = true;
    var t:Task = Task.new(&"plant", "Planting a tree");
    t.target = b;
    t.move_cell(spot, "Walking to plant a tree");
    t.work_for(0.4, "Planting a tree", func(_pw:Pawn) -> void:
        world.planting.erase(spot);
        world.plant_tree(spot));
    t.on_cancel = func(_pw:Pawn) -> void:
        world.planting.erase(spot);
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
