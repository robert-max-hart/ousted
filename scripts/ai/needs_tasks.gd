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
