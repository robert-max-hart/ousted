# ----------------------------------------------------------------
# Citizens
#     Citizens leaving the colony and dying: the body left behind, the
#     tasks that were aimed at them, adding a newcomer.
# ----------------------------------------------------------------
class_name Citizens extends RefCounted;

# A citizen too unhappy to stay walks away: no body, and half the grief.
static func leave_colony(world:World, p:Pawn) -> void:
    if p.removed:
        return;
    p.removed = true;
    p.end_task(false);
    if p.carry_amount > 0:
        world.drop_pile(p.carry_item, p.carry_amount, p.cell());
        p.clear_carry();
    if p.home != null:
        p.home.residents.erase(p);
        p.home.update_windows();
    world.pawns.erase(p);
    world.families.on_death(p, -1);
    world.jobs.reconcile();
    world.notify("%s has left the colony, unhappy." % p.first_name);
    if world.tools != null and world.tools.selected == p:
        world.tools.select(null);
    Citizens._end_tasks_aimed_at(world, p);
    p.queue_free();

# Stops what others are doing for a citizen who is about to be freed (a carer's callbacks still hold the baby).
static func _end_tasks_aimed_at(world:World, p:Pawn) -> void:
    for q in world.pawns:
        if q.task != null and is_same(q.task.target, p):
            q.end_task(false);

static func add_body(world:World, p:Pawn, cause:String, at:Vector3) -> Body:
    var b:Body = Body.new();
    b.setup(world, world._next_body_id, {"name": p.first_name, "age": int(p.age), "cause": cause, "died_hour": GameClock.total_hours}, at);
    world._next_body_id += 1;
    b.kin = world.families.kin_of(p);
    world._entities.add_child(b);
    world.bodies.append(b);
    return b;

static func remove_body(world:World, b:Body) -> void:
    if b.removed:
        return;
    b.removed = true;
    world.bodies.erase(b);
    b.queue_free();

static func add_pawn(world:World, p:Pawn) -> void:
    world._entities.add_child(p);
    world.pawns.append(p);

@warning_ignore("integer_division")
static func kill_pawn(world:World, p:Pawn, cause:String, at_home:bool = false) -> void:
    if p.removed:
        return;
    p.removed = true;
    p.end_task(false);
    var spot:Vector3 = p.position;
    if at_home and world.alive(p.home):
        spot = world.terrain.cell_center(p.home.origin + Vector2i(p.home.size.x / 2, p.home.size.y));     # just outside the door
    if p.carry_amount > 0:
        world.drop_pile(p.carry_item, p.carry_amount, world.terrain.world_to_cell(spot));
        p.clear_carry();
    world.ledger.deaths_today += 1;
    world.death_log.append({"name": p.first_name, "age": int(p.age), "cause": cause, "when": "%s, %s" % [GameClock.date_string(), GameClock.time_string()], "profession": p.profession_name()});
    if p.home != null:
        p.home.residents.erase(p);
        p.home.update_windows();
    var body:Body = Citizens.add_body(world, p, cause, spot);
    world.pawns.erase(p);
    world.families.on_death(p, body.id);
    world.jobs.reconcile();
    world.notify("%s has died of %s." % [p.first_name, cause]);
    if world.tools != null and world.tools.selected == p:
        world.tools.select(null);
    Citizens._end_tasks_aimed_at(world, p);
    p.queue_free();
