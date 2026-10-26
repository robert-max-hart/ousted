# ----------------------------------------------------------------
# NeedsTasks
#     Tasks that answer a citizen's needs: drinking, eating, warming up, sleeping, and a baby staying home.
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
