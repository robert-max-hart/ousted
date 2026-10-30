# ----------------------------------------------------------------
# TradeTasks
#     Hauling for the Trading Post: sold goods from storage into the
#     yard, and bought goods from the yard out to storage (the carried
#     goods are then put away by the ordinary delivery step).
# ----------------------------------------------------------------
class_name TradeTasks extends TaskBase;

func trade_task(p:Pawn) -> Task:
    var post:TradingPost = _post();
    if post == null:
        return null;
    var t:Task = _deliver_to_yard(p, post);
    if t != null:
        return t;
    t = _collect_from_yard(p, post);
    if t != null:
        return t;
    t = _return_excess(p, post);
    if t != null:
        return t;
    return _guide_animals(p, post);

func _post() -> TradingPost:
    for b in world.buildings:
        if b is TradingPost and b.is_complete():
            return b as TradingPost;
    return null;

# Carry some of a sold item from the nearest store that has it to the post.
func _deliver_to_yard(p:Pawn, post:TradingPost) -> Task:
    if p.has_failed(post):
        return null;
    for item in post.owed_items():
        var src:Building = world.nearest_storage_with(item, p.position);
        if src == null:
            continue;
        var n:int = src.reserve_out(item, mini(Pawn.CARRY_CAP, post.owed(item)));
        if n == 0:
            continue;
        post.en_route[item] = post.en_route.get(item, 0) + n;
        var st:Dictionary = {"picked": false, "done": false};
        var name:String = Defs.item_name(item).to_lower();
        var t:Task = Task.new(&"trade", "Taking %s to the Trading Post" % name);
        t.target = post;
        t.related = src;
        t.move_rect(src.rect(), src.is_walkable(), "Fetching %s for the merchant" % name);
        t.act(func(pw:Pawn) -> bool:
            st["picked"] = true;
            var got:int = src.take_reserved(item, n);
            if got < 1:
                return false;
            pw.set_carry(item, got);
            return true);
        t.move_rect(post.rect(), post.is_walkable(), "Taking %s to the Trading Post" % name);
        t.act(func(pw:Pawn) -> bool:
            st["done"] = true;
            post.deliver(item, pw.carry_amount);
            pw.clear_carry();
            return true);
        t.on_cancel = func(_pw:Pawn) -> void:
            if not st["picked"] and World.alive(src):
                src.release_out(item, n);
            if not st["done"] and World.alive(post):
                post.en_route[item] = maxi(0, post.en_route.get(item, 0) - n);
        return t;
    return null;

# Pick up purchased (or returned) goods at the post; the ordinary delivery step takes them to storage.
func _collect_from_yard(p:Pawn, post:TradingPost) -> Task:
    if p.has_failed(post):
        return null;
    for item in post.pickup:
        if not Stock.has_room_for(item):
            continue;
        var t:Task = Task.new(&"trade", "Fetching %s from the Trading Post" % Defs.item_name(item).to_lower());
        t.target = post;
        t.move_rect(post.rect(), post.is_walkable(), "Walking to the Trading Post");
        t.act(func(pw:Pawn) -> bool:
            var got:int = post.take_pickup(item, Pawn.CARRY_CAP);
            if got < 1:
                return false;
            pw.set_carry(item, got);
            return true);
        return t;
    return null;

# Held goods above their level go back to storage (the ordinary delivery step puts them away).
func _return_excess(p:Pawn, post:TradingPost) -> Task:
    if p.has_failed(post):
        return null;
    for item in post.excess():
        if not Stock.has_room_for(item):
            continue;
        var t:Task = Task.new(&"trade", "Carrying %s back from the Trading Post" % Defs.item_name(item).to_lower());
        t.target = post;
        t.move_rect(post.rect(), post.is_walkable(), "Walking to the Trading Post");
        t.act(func(pw:Pawn) -> bool:
            var got:int = mini(Pawn.CARRY_CAP, post.excess().get(item, 0));
            if got < 1:
                return false;
            post.take_input(item, got);
            pw.set_carry(item, got);
            return true);
        return t;
    return null;

# Lead bought animals from the post to the nearest pasture of their kind that has room. They are taken off the
# post's list when the citizen sets out and put back if the trip is cut short.
func _guide_animals(p:Pawn, post:TradingPost) -> Task:
    if p.has_failed(post):
        return null;
    for kind in post.animals_waiting:
        var pasture:Pasture = _pasture_for(kind, post);
        if pasture == null:
            continue;
        var n:int = mini(post.animals_waiting[kind], mini(pasture.free_room(), Defs.ANIMALS[kind]["guide"]));
        if n <= 0:
            continue;
        post.animals_waiting[kind] -= n;
        if post.animals_waiting[kind] <= 0:
            post.animals_waiting.erase(kind);
        pasture.incoming_animals += n;
        var st:Dictionary = {"herd": null, "done": false};
        var name:String = Defs.ANIMALS[kind]["name"].to_lower();
        var t:Task = Task.new(&"guide", "Leading %s to the %s" % [name, pasture.display_name().to_lower()]);
        t.target = pasture;
        t.related = post;
        t.move_rect(post.rect(), post.is_walkable(), "Fetching the %s" % name);
        t.act(func(pw:Pawn) -> bool:
            st["herd"] = GuidedHerd.lead(world, kind, n, pw);
            return true);
        t.move_rect(pasture.rect(), pasture.is_walkable(), "Leading the %s to the pasture" % name);
        t.act(func(_pw:Pawn) -> bool:
            st["done"] = true;
            pasture.incoming_animals = maxi(0, pasture.incoming_animals - n);
            var left:int = n - pasture.add_animals(n);
            if left > 0 and World.alive(post):
                post.animals_waiting[kind] = post.animals_waiting.get(kind, 0) + left;       # no room after all: back to the post
            return true);
        var finish:Callable = func(_pw:Pawn) -> void:
            if st["herd"] != null and is_instance_valid(st["herd"]):
                (st["herd"] as Node).queue_free();
            st["herd"] = null;
        t.on_end = finish;
        t.on_cancel = func(pw:Pawn) -> void:
            if not st["done"]:
                if World.alive(pasture):
                    pasture.incoming_animals = maxi(0, pasture.incoming_animals - n);
                if World.alive(post):
                    post.animals_waiting[kind] = post.animals_waiting.get(kind, 0) + n;
            finish.call(pw);
        return t;
    return null;

# The nearest finished pasture for this kind of animal with room for at least one more.
func _pasture_for(kind:StringName, post:TradingPost) -> Pasture:
    var best:Pasture = null;
    var best_d:float = INF;
    for b in world.buildings:
        if b is Pasture and b.is_complete() and b.kind == kind and (b as Pasture).free_room() > 0:
            var d:float = b.position.distance_squared_to(post.position);
            if d < best_d:
                best_d = d;
                best = b as Pasture;
    return best;
