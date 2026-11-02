# ----------------------------------------------------------------
# ClothesSwap
#     Better clothes: fine clothes lift the mood of whoever wears them,
#     and a citizen in plainer clothes swaps up to fine ones in storage
#     (but never ahead of someone with none), putting the old set back
#     if it has more than half its wear left.
#     godot --headless --path . --fixed-fps 60 res://tests/clothes_swap.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;
var world:World;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    Weather.drought_enabled = false;
    GameRules.reset();
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    await get_tree().process_frame;
    var hall:Building = world.town_hall;
    var p:Pawn = world.pawns[1];
    for q in world.pawns:
        if not q.is_baby():
            q.dress(&"clothes_wool");
    _expect("wool gives no mood", not _has_factor(p, "Fine clothes"));
    p.dress(&"clothes_fine");
    _expect("fine clothes lift the mood by %.2f" % Defs.ITEMS[&"clothes_fine"]["clothing"]["mood"], _has_factor(p, "Fine clothes") and p.clothes_mood() > 0.05);
    p.dress(&"clothes_wool");
    var tailor_desc:String = Defs.BUILDINGS[&"tailor"]["desc"];
    _expect("the tailor's help mentions it", tailor_desc.contains("mood"));
    # nothing better in storage: no swap
    _expect("no fine clothes, no swap", world.jobs.needs.dress_task(p) == null);
    hall.store(&"clothes_fine", 1);
    var t:Task = world.jobs.needs.dress_task(p);
    _expect("a set of fine clothes in storage tempts someone in wool", t != null);
    if t != null:
        t.on_cancel.call(p);          # (give the reservation back: we run the steps by hand below)
    # someone with none comes first
    var bare:Pawn = world.pawns[2];
    bare.clothing = &"";
    _expect("but not while a citizen has none", world.jobs.needs.dress_task(p) == null);
    var t2:Task = world.jobs.needs.dress_task(bare);
    _expect("who gets the fine set first", t2 != null and t2.label.contains("fine"));
    if t2 != null:
        t2.on_cancel.call(bare);
    bare.dress(&"clothes_wool");
    # the swap: the old set returns while it is good
    p.clothing_hours = Defs.ITEMS[&"clothes_wool"]["clothing"]["days"] * GameClock.HOURS_PER_DAY * 0.8;
    var wool_before:int = hall.amount(&"clothes_wool");
    var t3:Task = world.jobs.needs.dress_task(p);
    _expect("the swap is offered", t3 != null);
    if t3 != null:
        _run_act(t3, p);
        _expect("they now wear fine clothes", p.clothing == &"clothes_fine");
        _expect("the good wool set went back (%d to %d)" % [wool_before, hall.amount(&"clothes_wool")], hall.amount(&"clothes_wool") == wool_before + 1);
        _expect("the fine set left storage", hall.amount(&"clothes_fine") == 0);
    # a worn-out set is not put back
    hall.store(&"clothes_fine", 1);
    var u:Pawn = world.pawns[3];
    u.dress(&"clothes_wool");
    u.clothing_hours = 10.0;
    var wool_mid:int = hall.amount(&"clothes_wool");
    var t4:Task = world.jobs.needs.dress_task(u);
    if t4 != null:
        _run_act(t4, u);
    _expect("a nearly worn-out set is thrown away", t4 != null and u.clothing == &"clothes_fine" and hall.amount(&"clothes_wool") == wool_mid);
    # nobody in fine clothes swaps for plainer ones
    hall.store(&"clothes_wool", 2);
    _expect("fine clothes never swap down", world.jobs.needs.dress_task(p) == null);
    print("CLOTHES_SWAP %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _run_act(t:Task, p:Pawn) -> void:
    for s in t.steps:
        if s["type"] == Task.Step.ACT:
            (s["fn"] as Callable).call(p);

func _has_factor(p:Pawn, name:String) -> bool:
    for f in p.happiness_factors():
        if f[0] == name:
            return true;
    return false;

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
