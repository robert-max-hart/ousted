# ----------------------------------------------------------------
# FireTasks
#     What citizens do about a fire: run from the flames (flee), and
#     the able ones go and fight it, in rounds of fetching a bucket of
#     water (a well or the shore) and throwing it on the nearest burning
#     cell, which puts out the flames there and soaks the ground round
#     it so it cannot catch for a while (Fires.douse). At most
#     MAX_FIGHTERS fight at once. Owned by the World (world.fire_tasks)
#     and called from JobManager.choose_task and Pawn._should_interrupt.
# ----------------------------------------------------------------
class_name FireTasks extends TaskBase;

const FIGHT_RANGE   :int = 45;       # cells: how far from a fire a citizen is called to it
const MAX_FIGHTERS  :int = 8;
var max_fighters    :int = MAX_FIGHTERS;      # (a variable so a test can send nobody)
const BUCKET_HOURS  :float = 0.15;
const DOUSE_HOURS   :float = 0.1;

# Whether this citizen should stop what they are doing for the fire (Pawn._should_interrupt).
func wants(p:Pawn) -> bool:
    var fires:Fires = world.fires;
    if p.indoors or p.is_baby():
        return false;
    if is_fighter(p):
        return fires.nearest_wild(p.cell(), FIGHT_RANGE) != Fires.NO_CELL;
    if fires.nearest_wild(p.cell(), Fires.FLEE_RADIUS) != Fires.NO_CELL:
        return true;
    return can_fight(p) and fires.fighters.size() < max_fighters and fires.nearest_wild(p.cell(), FIGHT_RANGE) != Fires.NO_CELL;

func is_fighter(p:Pawn) -> bool:
    return world.fires.fighters.has(p) and can_fight(p);

# Adults who are awake and well enough.
func can_fight(p:Pawn) -> bool:
    return p.is_adult() and not p.sleeping and not p.indoors and p.energy > 0.15 and not Illness.must_rest(p) and p.health > 0.4;

# Run from flames close by: to ground well clear of them. Fighters stay at the front.
func flee_task(p:Pawn) -> Task:
    var fires:Fires = world.fires;
    if p.indoors or is_fighter(p) or not fires.wild_burning():
        return null;
    var here:Vector2i = p.cell();
    var fire:Vector2i = fires.nearest_wild(here, Fires.FLEE_RADIUS);
    if fire == Fires.NO_CELL:
        return null;
    var best:Vector2i = Fires.NO_CELL;
    var best_score:float = -INF;
    for k in 16:
        var a:float = TAU * k / 16.0;
        for r in [Fires.SAFE_RADIUS, Fires.SAFE_RADIUS + 3]:
            var c:Vector2i = here + Vector2i(roundi(cos(a) * r), roundi(sin(a) * r));
            if not world.terrain.in_bounds(c) or not world.nav.is_walkable(c) or fires.nearest_wild(c, Fires.FLEE_RADIUS) != Fires.NO_CELL:
                continue;
            var score:float = Vector2(c - fire).length() - Vector2(c - here).length() * 0.3;
            if score > best_score:
                best_score = score;
                best = c;
    if best == Fires.NO_CELL:
        return null;
    var t:Task = Task.new(&"flee", "Running from the fire", true);
    t.move_cell(best);
    t.work_for(0.3, "Waiting out the fire");
    return t;

# Fight the fire: fetch water if there is no bucket in hand, then put it on the nearest flames.
func fight_task(p:Pawn) -> Task:
    var fires:Fires = world.fires;
    if not fires.wild_burning() or p.carry_amount > 0 or not can_fight(p):
        return null;
    if not fires.fighters.has(p):
        if fires.fighters.size() >= max_fighters:
            return null;
    var target:Vector2i = fires.nearest_wild(p.cell(), FIGHT_RANGE);
    if target == Fires.NO_CELL:
        return null;
    fires.fighters[p] = true;
    if not p.bucket:
        return _fetch_water_task(p);
    var t:Task = Task.new(&"fire", "Putting out the fire", true);
    t.move_rect(Rect2i(target, Vector2i.ONE));
    t.work_for(DOUSE_HOURS, "Putting out the fire", func(pw:Pawn) -> void:
        pw.bucket = false;
        world.fires.douse(target));
    return t;

func _fetch_water_task(p:Pawn) -> Task:
    var well:Building = world.nearest_building(p.position, func(x:Building) -> bool:
        return x.is_complete() and x.def.get("water", false));
    var shore:Vector2i = _nearest_shore(p.cell(), 40);
    var well_d:float = INF if well == null else Vector2(well.center_cell()).distance_to(Vector2(p.cell()));
    var shore_d:float = INF if shore == Fires.NO_CELL else Vector2(shore).distance_to(Vector2(p.cell()));
    if well == null and shore == Fires.NO_CELL:
        return null;
    var t:Task = Task.new(&"fire", "Fetching water", true);
    if well != null and well_d <= shore_d:
        t.target = well;
        t.move_rect(well.rect(), well.is_walkable());
    else:
        t.move_cell(shore);
    t.work_for(BUCKET_HOURS, "Filling a bucket", func(pw:Pawn) -> void:
        pw.bucket = true);
    return t;

# The nearest walkable cell beside open water, or NO_CELL.
func _nearest_shore(from:Vector2i, max_r:int) -> Vector2i:
    for r in range(1, max_r + 1):
        for dz in range(-r, r + 1):
            for dx in range(-r, r + 1):
                if maxi(absi(dx), absi(dz)) != r:
                    continue;
                var c:Vector2i = from + Vector2i(dx, dz);
                if world.terrain.in_bounds(c) and world.nav.is_walkable(c) and _water_beside(c):
                    return c;
    return Fires.NO_CELL;

func _water_beside(c:Vector2i) -> bool:
    for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
        var n:Vector2i = c + d;
        if world.terrain.in_bounds(n) and world.terrain.is_water(n):
            return true;
    return false;
