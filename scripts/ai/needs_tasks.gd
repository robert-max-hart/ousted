# ----------------------------------------------------------------
# NeedsTasks
#     Tasks that answer a citizen's needs: drinking, eating, warming up, sleeping, a baby staying home and
#     an adult feeding and watering a baby.
# ----------------------------------------------------------------
class_name NeedsTasks extends TaskBase;

func drink_task(p:Pawn) -> Task:
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

func eat_task(p:Pawn) -> Task:
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

# A citizen with no treat boost running (and a random pause since the last, so they don't all go at once) eats one from storage.
func treat_task(p:Pawn) -> Task:
    if not world.policies.is_on(&"treats") or not p.wants_treat():
        return null;
    var item:StringName = Stock.best_treat();
    if item == &"":
        return null;
    var s:Building = world.nearest_storage_with(item, p.position);
    if s == null or s.reserve_out(item, 1) == 0:
        return null;
    var info:Dictionary = Defs.ITEMS[item]["treat"];
    var st:Dictionary = {"taken": false};
    var t:Task = Task.new(&"eat", "Fetching %s" % Defs.item_name(item).to_lower(), false);
    t.target = s;
    t.move_rect(s.rect(), s.is_walkable());
    t.act(func(_pw:Pawn) -> bool:
        s.take_reserved(item, 1);
        st["taken"] = true;
        return true);
    t.work_for(0.25, "Enjoying %s" % Defs.item_name(item).to_lower(), func(pw:Pawn) -> void:
        pw.enjoy_treat(item, info));
    t.on_cancel = func(_pw:Pawn) -> void:
        if not st["taken"] and World.alive(s):
            s.release_out(item, 1);
    return t;

# An evening at the tavern: adults go once a day (about half of them on a given evening) between 17:00 and 20:00, spend an
# hour and a half there and come out a little happier; with spirits in the tavern's store, one who is ready for a treat drinks one.
func tavern_task(p:Pawn) -> Task:
    var today:int = GameClock.day_index();
    if not p.tavern_due():
        return null;
    p.tavern_day = today;         # decided for tonight, whatever comes of it
    if hash(Vector2i(p.get_instance_id() % 100003, today)) % 100 >= Defs.TAVERN_SHARE:
        return null;              # not tonight
    var b:Building = world.nearest_building(p.position, func(x:Building) -> bool:
        return x.is_complete() and x.def.get("tavern", false) and not p.has_failed(x) and _patrons(x) < x.def.get("patrons", 10));
    if b == null:
        return null;
    var t:Task = Task.new(&"tavern", "Going to the tavern", false);
    t.target = b;
    t.move_rect(b.rect(), false);
    t.act(func(pw:Pawn) -> bool:
        pw.go_inside(b, false);
        return true);
    t.work_for(Defs.TAVERN_STAY, "At the tavern", func(pw:Pawn) -> void:
        pw.tavern_until = GameClock.total_hours + Defs.TAVERN_MOOD_HOURS;
        if world.policies.is_on(&"treats") and b.input_amount(&"spirits") > 0 and pw.wants_treat():
            b.take_input(&"spirits", 1);
            pw.enjoy_treat(&"spirits", Defs.ITEMS[&"spirits"]["treat"]);
        pw.go_outside());
    t.on_cancel = func(pw:Pawn) -> void:
        if pw.indoors and is_same(pw.shelter, b):
            pw.go_outside();
    return t;

func _patrons(b:Building, kind:StringName = &"tavern") -> int:
    var n:int = 0;
    for q in world.pawns:
        if q.task != null and q.task.kind == kind and is_same(q.task.target, b):
            n += 1;
    return n;

# The morning service on a service day (Defs.is_service_day): about 6 in 10 adults go to the nearest chapel with room, stay
# a couple of hours, and come out lifted for a few days, with the grief for any recent death halved.
func chapel_task(p:Pawn) -> Task:
    if not p.chapel_due():
        return null;
    var today:int = GameClock.day_index();
    p.chapel_day = today;         # decided for this service day, whatever comes of it
    if hash(Vector3i(p.get_instance_id() % 100003, today, 7)) % 100 >= Defs.CHAPEL_SHARE:
        return null;
    var b:Building = world.nearest_building(p.position, func(x:Building) -> bool:
        return x.is_complete() and x.def.get("chapel", false) and not p.has_failed(x) and _patrons(x, &"chapel") < x.def.get("patrons", 20));
    if b == null:
        return null;
    var t:Task = Task.new(&"chapel", "Going to the service", false);
    t.target = b;
    t.move_rect(b.rect(), false);
    t.act(func(pw:Pawn) -> bool:
        pw.go_inside(b, false);
        return true);
    t.work_for(Defs.CHAPEL_STAY, "At the service", func(pw:Pawn) -> void:
        pw.chapel_until = GameClock.total_hours + Defs.CHAPEL_MOOD_HOURS;
        pw.pray();
        pw.go_outside());
    t.on_cancel = func(pw:Pawn) -> void:
        if pw.indoors and is_same(pw.shelter, b):
            pw.go_outside();
    return t;

# A citizen with no clothes on fetches a set from storage and puts it on (the best there is).
func dress_task(p:Pawn) -> Task:
    var item:StringName = Stock.best_clothing();
    if item == &"":
        return null;
    var s:Building = world.nearest_storage_with(item, p.position);
    if s == null or p.has_failed(s) or s.reserve_out(item, 1) == 0:
        return null;
    var st:Dictionary = {"taken": false};
    var t:Task = Task.new(&"equip", "Fetching %s" % Defs.item_name(item).to_lower());
    t.target = s;
    t.move_rect(s.rect(), s.is_walkable());
    t.act(func(pw:Pawn) -> bool:
        st["taken"] = true;
        if s.take_reserved(item, 1) < 1:
            return false;
        pw.dress(item);
        return true);
    t.on_cancel = func(_pw:Pawn) -> void:
        if not st["taken"] and World.alive(s):
            s.release_out(item, 1);
    return t;

func warm_task(p:Pawn) -> Task:
    var b:Building = world.warm_shelter_for(p);
    if b == null or not b.is_heated():
        var camp:Task = campfire_task(p);          # no warm place to go to: a fire outside, if there is a fire or wood to make one
        if camp != null:
            return camp;
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
func stay_home_task(p:Pawn) -> Task:
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

func sleep_task(p:Pawn) -> Task:
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

# Fetches food and water for a baby in the adult's house (whichever it is low on, or both) and takes them home.
func care_task(p:Pawn) -> Task:
    var baby:Pawn = world.families.baby_needing_care(p);
    if baby == null:
        return null;
    var home:Building = baby.home;      # null for a homeless baby: it is brought to where it lies
    var st:Dictionary = {"fed": false, "watered": false};
    var t:Task = Task.new(&"care", "Caring for %s" % baby.first_name, false);
    t.target = baby;
    var cleanup:Array = [];
    if baby.hunger < Defs.BABY_CARE_BELOW:
        var item:StringName = Stock.best_food();
        var s:Building = world.nearest_storage_with(item, p.position) if item != &"" else null;
        if s != null:
            var nutrition:float = Defs.ITEMS[item]["nutrition"];
            var n:int = s.reserve_out(item, clampi(ceili((0.95 - baby.hunger) / nutrition), 1, 4));
            if n > 0:
                t.move_rect(s.rect(), s.is_walkable(), "Fetching food for %s" % baby.first_name);
                t.act(func(_pw:Pawn) -> bool:
                    s.take_reserved(item, n);
                    st["fed"] = true;
                    st["gain"] = nutrition * n;
                    return true);
                cleanup = [s, item, n];
    if baby.thirst < Defs.BABY_CARE_BELOW:
        var well:Building = world.nearest_building(p.position, func(x:Building) -> bool:
            return x.is_complete() and x.def.get("water", false));
        if well != null:
            t.move_rect(well.rect(), well.is_walkable(), "Fetching water for %s" % baby.first_name);
            t.act(func(_pw:Pawn) -> bool:
                st["watered"] = true;
                return true);
    if t.steps.is_empty():
        p.avoid(baby, 3.0);      # nothing to bring: don't keep trying every moment
        return null;
    if home != null:
        t.move_rect(home.rect(), false, "Taking it home");
    else:
        t.move_cell(baby.cell(), "Taking it to %s" % baby.first_name);
    t.work_for(0.4, "Feeding %s" % baby.first_name, func(_pw:Pawn) -> void:
        if st["fed"]:
            baby.hunger = minf(1.0, baby.hunger + st["gain"]);
        if st["watered"]:
            baby.thirst = 1.0);
    baby.carer = p;
    t.on_cancel = func(_pw:Pawn) -> void:
        if not cleanup.is_empty() and not st["fed"] and World.alive(cleanup[0]):
            (cleanup[0] as Building).release_out(cleanup[1], cleanup[2]);
    t.on_end = func(_pw:Pawn) -> void:
        if World.alive(baby) and baby.carer == p:
            baby.carer = null;
    return t;

# --------------------------------
# Campfires

const CAMP_NEAR     :int = 14;         # cells: a campfire this close is where they go
const CAMP_SITE_R   :Vector2i = Vector2i(2, 7);

# Cold, with nowhere warm: sit by a campfire that is burning, or fetch firewood (or a log) and light one on a bare spot with nothing
# flammable beside it, near home, and sit by it until warm.
func campfire_task(p:Pawn) -> Task:
    var fires:Fires = world.fires;
    var warmed:Callable = func(pw:Pawn, _dh:float) -> bool:
        return pw.warmth >= 0.9 or not fires.camp_near(pw.cell(), Fires.CAMP_WARM_RADIUS + 1.0);
    var camp:Vector2i = fires.nearest_camp(p.cell(), CAMP_NEAR);
    if camp != Fires.NO_CELL:
        var t:Task = Task.new(&"camp", "Warming by the fire", false);
        t.move_cell(_beside(camp));
        t.work(warmed, "Warming by the fire");
        return t;
    var item:StringName = &"firewood" if Stock.amount(&"firewood") > 0 else (&"wood" if Stock.amount(&"wood") > 0 else &"");
    if item == &"" or fires.camp_count() >= Fires.MAX_CAMPS:
        return null;
    var s:Building = world.nearest_storage_with(item, p.position);
    if s == null or s.reserve_out(item, 1) == 0:
        return null;
    var anchor:Vector2i = p.cell();
    if world.alive(p.home):
        anchor = Vector2i(p.home.center_cell());
    var site:Vector2i = _camp_site(anchor);
    if site == Fires.NO_CELL:
        s.release_out(item, 1);
        return null;
    var st:Dictionary = {"taken": false};
    var t2:Task = Task.new(&"camp", "Fetching firewood", false);
    t2.target = s;
    t2.move_rect(s.rect(), s.is_walkable());
    t2.act(func(_pw:Pawn) -> bool:
        s.take_reserved(item, 1);
        st["taken"] = true;
        return true);
    t2.move_cell(site);
    t2.act(func(_pw:Pawn) -> bool:
        fires.light_campfire(site);
        return true);
    t2.work(warmed, "Warming by the fire");
    t2.on_cancel = func(_pw:Pawn) -> void:
        if not st["taken"] and World.alive(s):
            s.release_out(item, 1);
    return t2;

# A walkable cell next to the campfire.
func _beside(camp:Vector2i) -> Vector2i:
    for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1)]:
        if world.nav.is_walkable(camp + d):
            return camp + d;
    return camp;

# A bare walkable cell within a few cells of the anchor with the fewest flammable cells round it.
func _camp_site(anchor:Vector2i) -> Vector2i:
    var best:Vector2i = Fires.NO_CELL;
    var best_score:float = INF;
    for dz in range(-CAMP_SITE_R.y, CAMP_SITE_R.y + 1):
        for dx in range(-CAMP_SITE_R.y, CAMP_SITE_R.y + 1):
            var d:int = maxi(absi(dx), absi(dz));
            if d < CAMP_SITE_R.x or d > CAMP_SITE_R.y:
                continue;
            var c:Vector2i = anchor + Vector2i(dx, dz);
            if not world.terrain.in_bounds(c) or not world.nav.is_walkable(c) or world.terrain.is_water(c):
                continue;
            var i:int = world.idx(c);
            if world.node_at[i] != null or world.occupant[i] != null or world.terrain.get_overlay(c) != Terrain.Overlay.NONE or world.fires.is_burning(c):
                continue;
            var fuel_near:float = 0.0;
            for nz in range(-1, 2):
                for nx in range(-1, 2):
                    var fl:Dictionary = world.fires.flammability(c + Vector2i(nx, nz));
                    if not fl.is_empty() and fl["catch"] > Fires.GRASS_CATCH:
                        fuel_near += fl["catch"];
            var score:float = fuel_near * 10.0 + d;
            if score < best_score:
                best_score = score;
                best = c;
    return best;

# --------------------------------
# Cooling off

const COOL_SEARCH_R :int = 14;        # cells: how far they look for shade

# Too hot: go to the nearest shade (their home, a well, or the foot of a tree) and rest there until they are cool again.
func cool_task(p:Pawn) -> Task:
    var rested:Callable = func(pw:Pawn, _dh:float) -> bool:
        return pw.overheat <= Heat.SHADE_UNTIL or Weather.temperature < Heat.FROM - 4.0;
    if Heat.cooling_spot(p):
        var here:Task = Task.new(&"cool", "Resting in the shade", false);
        here.work(rested, "Resting in the shade");
        return here;
    var here_c:Vector2 = Vector2(p.cell());
    var home:Building = world.shelter_for(p);
    var well:Building = world.nearest_building(p.position, func(x:Building) -> bool:
        return x.is_complete() and x.def.get("water", false));
    var shade:Building = world.nearest_building(p.position, func(x:Building) -> bool:
        return x.is_complete() and x.def.get("shade", false));
    var shade_d:float = INF if shade == null else Vector2(shade.center_cell()).distance_to(here_c);
    var tree:Vector2i = _nearest_tree(p.cell());
    var home_d:float = INF if home == null else Vector2(home.center_cell()).distance_to(here_c);
    var well_d:float = INF if well == null else Vector2(well.center_cell()).distance_to(here_c);
    var tree_d:float = INF if tree == Fires.NO_CELL else Vector2(tree).distance_to(here_c);
    var t:Task = Task.new(&"cool", "Going to cool off", false);
    if shade != null and shade_d <= home_d and shade_d <= well_d and shade_d <= tree_d:
        t.target = shade;
        t.move_rect(shade.rect(), true);
    elif home_d <= well_d and home_d <= tree_d and home != null:
        t.target = home;
        t.move_rect(home.rect());
        t.act(func(pw:Pawn) -> bool:
            pw.go_inside(home, false);
            return true);
    elif well_d <= tree_d and well != null:
        t.target = well;
        t.move_rect(well.rect(), well.is_walkable());
    elif tree != Fires.NO_CELL:
        t.move_cell(_beside_cell(tree));
    else:
        return null;
    t.work(rested, "Cooling off");
    t.on_end = func(pw:Pawn) -> void:
        pw.go_outside();
    return t;

func _nearest_tree(from:Vector2i) -> Vector2i:
    for r in range(1, COOL_SEARCH_R + 1):
        for dz in range(-r, r + 1):
            for dx in range(-r, r + 1):
                if maxi(absi(dx), absi(dz)) != r:
                    continue;
                var c:Vector2i = from + Vector2i(dx, dz);
                if world.terrain.in_bounds(c):
                    var rn:ResourceNode = world.node_at[world.idx(c)];
                    if rn != null and rn.is_tree() and _beside_cell(c) != Fires.NO_CELL:
                        return c;
    return Fires.NO_CELL;

# A walkable cell next to a tree (they stand in its shade), or NO_CELL.
func _beside_cell(c:Vector2i) -> Vector2i:
    for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
        if world.nav.is_walkable(c + d):
            return c + d;
    return Fires.NO_CELL;
