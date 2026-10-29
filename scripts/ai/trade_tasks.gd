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
    return _collect_from_yard(p, post);

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
