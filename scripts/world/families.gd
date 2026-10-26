# ----------------------------------------------------------------
# Families
#     Pairing, pregnancy, births, rehoming and baby care, run once a
#     day (see Defs for the rules). Owned by World. No sex is tracked
#     for any of it: a pair is two adults, and either may carry.
# ----------------------------------------------------------------
class_name Families extends RefCounted;

var world:World;

func _init(w:World) -> void:
    world = w;

func on_hour() -> void:
    _build_shacks();

func on_day() -> void:
    _pair_up();
    _births();
    assign_homes();

# --------------------------------
# Pairing

static func are_kin(a:Pawn, b:Pawn) -> bool:
    if a.parents.has(b) or b.parents.has(a):
        return true;
    for par in a.parents:
        if b.parents.has(par):
            return true;
    return false;

func can_pair(a:Pawn, b:Pawn) -> bool:
    return a != b and a.is_adult() and b.is_adult() and a.partner == null and b.partner == null \
        and absf(a.age - b.age) <= Defs.PAIR_MAX_AGE_GAP and not are_kin(a, b) \
        and GameClock.total_hours >= a.pair_ready_hour and GameClock.total_hours >= b.pair_ready_hour;

func _pair_up() -> void:
    var order:Array[Pawn] = world.pawns.duplicate();
    _shuffle(order);
    for a in order:
        if a.partner != null or not a.is_adult() or world.rng.randf() >= Defs.PAIR_CHANCE_PER_DAY:
            continue;
        var options:Array[Pawn] = [];
        for b in order:
            if can_pair(a, b):
                options.append(b);
        if options.is_empty():
            continue;
        pair(a, options[world.rng.randi() % options.size()]);

func pair(a:Pawn, b:Pawn) -> void:
    a.partner = b;
    b.partner = a;
    world.notify("%s and %s are now a couple." % [a.first_name, b.first_name]);
    _move_in_together(a, b);

# One moves into the other's house when there is room, preferring the emptier house so a child can follow.
func _move_in_together(a:Pawn, b:Pawn) -> void:
    if a.home == b.home:
        return;
    var from:Pawn = a;
    var to:Pawn = b;
    if a.home != null and (b.home == null or a.home.residents.size() < b.home.residents.size()):
        from = b;
        to = a;
    if house_has_room(to.home):
        move_home(from, to.home);

func move_home(p:Pawn, b:Building) -> void:
    if p.home != null:
        p.home.residents.erase(p);
    p.home = b;
    if b != null:
        b.residents.append(p);

# --------------------------------
# Pregnancy and birth

func fertile(p:Pawn) -> bool:
    return p.age >= Defs.FERTILE_FROM and p.age <= Defs.FERTILE_TO;

func house_has_room(b:Building) -> bool:
    return b != null and World.alive(b) and b.def.has("beds") and not b.def.get("shack", false) and b.is_complete() and b.residents.size() < b.def["beds"];

# Food, warmth and the pair's happiness scale the daily chance of a conception.
func birth_chance(home:Building, a:Pawn, b:Pawn) -> float:
    var food:float = clampf(Stock.food_total() / maxf(1.0, world.pawns.size()) / Defs.FOOD_PER_PAWN_PLENTY, Defs.STARVING_BIRTH_MULT, 1.0);
    var warm:float = 1.0 if home.is_heated() or Weather.temperature >= Defs.HEATING_BELOW else Defs.STARVING_BIRTH_MULT;
    var mood:float = (a.mood + b.mood) * 0.5;
    return Defs.BIRTH_CHANCE_PER_DAY * food * warm * lerpf(Defs.BIRTH_MOOD_RANGE.x, Defs.BIRTH_MOOD_RANGE.y, mood);

func _births() -> void:
    var now:float = GameClock.total_hours;
    for p in world.pawns.duplicate():
        if p.removed:
            continue;
        if p.due_hour >= 0.0:
            if now >= p.due_hour and house_has_room(p.home):
                _give_birth(p);
            continue;
        var q:Pawn = p.partner;
        if q == null or world.pawns.find(q) < world.pawns.find(p):
            continue;       # each pair is handled once, from the first partner in the list
        if p.home == null or p.home != q.home or not house_has_room(p.home):
            continue;
        if now < p.conceive_ready_hour or now < q.conceive_ready_hour or p.due_hour >= 0.0 or q.due_hour >= 0.0:
            continue;
        var carrier:Pawn = null;
        var candidates:Array[Pawn] = [];
        for c in [p, q]:
            if fertile(c):
                candidates.append(c);
        if candidates.is_empty():
            continue;
        carrier = candidates[world.rng.randi() % candidates.size()];
        if world.rng.randf() < birth_chance(p.home, p, q):
            carrier.due_hour = now + Defs.PREGNANCY_DAYS * GameClock.HOURS_PER_DAY;

func _give_birth(carrier:Pawn) -> void:
    var home:Building = carrier.home;
    carrier.due_hour = -1.0;
    var wait:float = GameClock.total_hours + Defs.POSTPARTUM_DAYS * GameClock.HOURS_PER_DAY;
    carrier.conceive_ready_hour = wait;
    var parents:Array[Pawn] = [carrier];
    if World.alive(carrier.partner):
        carrier.partner.conceive_ready_hour = wait;
        parents.append(carrier.partner);
    var names:Array[String] = [];
    for p in world.pawns:
        names.append(p.first_name);
    var baby:Pawn = Pawn.new();
    baby.setup(world, home.origin + home.size / 2, world.rng, names);
    baby.age = 0.0;
    baby.profession = JobManager.Profession.LABORER;
    baby.parents = parents;
    world.add_pawn(baby);
    move_home(baby, home);
    baby.go_inside(home, false);
    world.notify("A baby, %s, was born to %s." % [baby.first_name, " and ".join(PackedStringArray(parents.map(func(x:Pawn) -> String: return x.first_name)))]);

# --------------------------------
# Homes

func lives_in_shack(p:Pawn) -> bool:
    return p.home != null and p.home.def.get("shack", false);

# Homeless citizens and those in a shack, children first, move into the nearest house with a free slot.
func assign_homes() -> void:
    var homeless:Array[Pawn] = [];
    for p in world.pawns:
        if p.home == null or lives_in_shack(p):
            homeless.append(p);
    homeless.sort_custom(func(a:Pawn, b:Pawn) -> bool:
        return a.age < b.age);
    for p in homeless:
        var b:Building = world.nearest_building(p.position, func(x:Building) -> bool:
            return house_has_room(x));
        if b == null:
            return;
        move_home(p, b);

# Those closest to a citizen: their partner, parents, children and siblings who are adults and alive.
func kin_of(c:Pawn) -> Array[Pawn]:
    var out:Array[Pawn] = [];
    for p in world.pawns:
        if p == c or not p.is_adult():
            continue;
        if p == c.partner or c.parents.has(p) or p.parents.has(c) or are_kin(c, p):
            out.append(p);
    return out;

# --------------------------------
# Shacks

func homeless_count() -> int:
    var n:int = 0;
    for p in world.pawns:
        if p.home == null:
            n += 1;
    return n;

# An adult with no home for a few hours gets a house with room, else an empty shack, else a new shack site next
# to them (the usual builders put it up).
func _build_shacks() -> void:
    if not world.policies.is_on(&"build_shacks"):
        return;
    for p in world.pawns:
        if p.home != null or not p.is_adult() or p.homeless_hours < Defs.SHACK_AFTER_HOURS:
            continue;
        var house:Building = world.nearest_building(p.position, func(x:Building) -> bool:
            return house_has_room(x));
        if house != null:
            move_home(p, house);
            continue;
        var shack:Building = world.nearest_building(p.position, func(x:Building) -> bool:
            return x.def.get("shack", false) and x.residents.is_empty());
        if shack == null:
            shack = _place_shack(p);
            if shack != null:
                world.notify("%s has no home and is putting up a shack." % p.first_name);
        if shack != null:
            move_home(p, shack);

func _place_shack(p:Pawn) -> Building:
    var size:Vector2i = Defs.BUILDINGS[&"shack"]["size"];
    var c:Vector2i = p.cell();
    for r in range(1, 14):
        for dz in range(-r, r + 1):
            for dx in range(-r, r + 1):
                if maxi(absi(dx), absi(dz)) != r:
                    continue;
                var o:Vector2i = c + Vector2i(dx, dz);
                if _shack_spot_ok(o, size):
                    return world.place_building(&"shack", o, size);
    return null;

# Free ground with no roads, trees or rocks on it, and the ring around it left open so nothing gets walled in.
func _shack_spot_ok(o:Vector2i, size:Vector2i) -> bool:
    if world.can_place(&"shack", o, size) != "":
        return false;
    for z in range(o.y - 1, o.y + size.y + 1):
        for x in range(o.x - 1, o.x + size.x + 1):
            var cell:Vector2i = Vector2i(x, z);
            if not world.terrain.in_bounds(cell):
                return false;
            var inside:bool = x >= o.x and x < o.x + size.x and z >= o.y and z < o.y + size.y;
            if inside and (world.node_at[world.idx(cell)] != null or world.terrain.get_overlay(cell) != Terrain.Overlay.NONE):
                return false;
            if not inside and world.occupant[world.idx(cell)] != null:
                return false;
    return true;

# Called when someone dies (body_id) or leaves (-1): everyone grieves, kin most; the partner is widowed, children lose
# them as a parent, and anyone caring for them stops.
func on_death(dead:Pawn, body_id:int) -> void:
    var mult:float = 1.0 if body_id >= 0 else Defs.GRIEF_LEFT_MULT;
    for p in world.pawns:
        if p == dead:
            continue;
        var g:Vector2 = Defs.GRIEF_COLONY;
        if p == dead.partner:
            g = Defs.GRIEF_PARTNER;
        elif dead.parents.has(p) or p.parents.has(dead):
            g = Defs.GRIEF_FAMILY;
        elif are_kin(p, dead):
            g = Defs.GRIEF_SIBLING;
        p.add_grief(g.x * mult, g.y, body_id);
        p.parents.erase(dead);
        if p.partner == dead:
            p.partner = null;
            p.pair_ready_hour = GameClock.total_hours + Defs.WIDOW_WAIT_DAYS * GameClock.HOURS_PER_DAY;
        if p.carer == dead:
            p.carer = null;

# --------------------------------
# Baby care

# A baby in this adult's house whose hunger or thirst is low and who has nobody on the way.
func baby_needing_care(p:Pawn) -> Pawn:
    var candidates:Array[Pawn] = [];
    if p.home != null and World.alive(p.home):
        candidates.append_array(p.home.residents);
    for b in world.pawns:
        if b.home == null and b.is_baby():       # any adult may look after a homeless baby
            candidates.append(b);
    var best:Pawn = null;
    for b in candidates:
        if not b.is_baby() or b.removed or (b.carer != null and World.alive(b.carer) and b.carer != p):
            continue;
        if b.hunger >= Defs.BABY_CARE_BELOW and b.thirst >= Defs.BABY_CARE_BELOW:
            continue;
        if p.has_failed(b):
            continue;
        if best == null or minf(b.hunger, b.thirst) < minf(best.hunger, best.thirst):
            best = b;
    return best;

func soften_grief(body_id:int) -> void:
    for p in world.pawns:
        p.soften_grief(body_id);

func _shuffle(a:Array[Pawn]) -> void:
    for i in range(a.size() - 1, 0, -1):
        var j:int = world.rng.randi() % (i + 1);
        var t:Pawn = a[i];
        a[i] = a[j];
        a[j] = t;
