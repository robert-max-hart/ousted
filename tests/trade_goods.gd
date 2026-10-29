# ----------------------------------------------------------------
# Seeds, saplings and animals from merchants (M6 step 3)
#     Merchants offer crops the colony does not know (those in season
#     likelier) and animals for pastures with room; buying a seed unlocks
#     the crop at once; bought animals wait at the post until a citizen
#     leads them to a pasture of their kind.
#     godot --headless --path . --fixed-fps 60 res://tests/trade_goods.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;
var world:World;
var _post:TradingPost;
var _pen:Pasture;
var _phase:int = 0;
var _start:float = 0.0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"normal";           # wheat, beans and radishes known
    Weather.drought_enabled = false;
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON * 1 + 2) * GameClock.HOURS_PER_DAY + 12.0;      # early summer
    Weather._day_offset = 0.0;
    Weather._update_temperature();
    var o:Vector2i = world.town_hall.origin + Vector2i(8, -10);
    for rn in world.nodes.duplicate():
        if Rect2i(o - Vector2i(3, 3), Vector2i(24, 12)).has_point(rn.cell):
            world.remove_node(rn);
    world.terrain.flatten_rect(Rect2i(o - Vector2i(2, 2), Vector2i(26, 14)));
    _post = world.place_building(&"trading_post", o, Vector2i(4, 3), true) as TradingPost;
    # names and values
    _expect("a seed is worth something and has a name", Defs.trade_value(Defs.seed_key(&"potato")) == 30 and Defs.offer_name(Defs.seed_key(&"potato")) == "Seed potatoes" and Defs.offer_name(Defs.seed_key(&"wheat")) == "Wheat seeds");
    _expect("a sapling is named as one", Defs.offer_name(Defs.seed_key(&"apple")) == "Apple saplings");
    _expect("animals are worth more than eggs", Defs.trade_value(Defs.animal_key(&"cow")) == 70 and Defs.offer_name(Defs.animal_key(&"cow")) == "Cow");
    # what is offered: no animals without a pasture, none of the crops already known
    var offered:Dictionary = {};
    for i in 200:
        var stock:Dictionary = world.traders._make_visit()["stock"];
        for key in stock:
            offered[key] = offered.get(key, 0) + 1;
    _expect("no animals are offered without a pasture", not offered.has(Defs.animal_key(&"cow")) and not offered.has(Defs.animal_key(&"chicken")));
    _expect("known crops are never offered as seeds", not offered.has(Defs.seed_key(&"wheat")) and not offered.has(Defs.seed_key(&"beans")) and not offered.has(Defs.seed_key(&"radish")));
    _expect("unknown crops are (%s)" % [offered.keys().filter(func(k:StringName) -> bool: return Defs.is_seed_key(k))], offered.has(Defs.seed_key(&"pumpkin")) or offered.has(Defs.seed_key(&"potato")));
    # in-season crops are likelier: pumpkins can be sown in summer (9 C), apples too; compare with a cold start
    var summer:int = _count_offers(Defs.seed_key(&"pumpkin"), 600);
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON * 0 + 1) * GameClock.HOURS_PER_DAY + 12.0;        # first spring days: pumpkins (9 C) cannot be sown
    Weather._update_temperature();
    var spring:int = _count_offers(Defs.seed_key(&"pumpkin"), 600);
    _expect("a crop that can be sown now is offered more often (%d in summer, %d when it is too cold)" % [summer, spring], summer > spring);
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON * 1 + 2) * GameClock.HOURS_PER_DAY + 12.0;
    Weather._update_temperature();
    # a pasture with room gets animals offered
    _pen = world.place_building(&"coop", o + Vector2i(8, 0), Vector2i(4, 4), true) as Pasture;
    offered.clear();
    for i in 200:
        var stock2:Dictionary = world.traders._make_visit()["stock"];
        for key in stock2:
            offered[key] = offered.get(key, 0) + 1;
    _expect("with a chicken run, chickens are offered (%d of 200)" % offered.get(Defs.animal_key(&"chicken"), 0), offered.get(Defs.animal_key(&"chicken"), 0) > 60);
    _expect("but still no cows", not offered.has(Defs.animal_key(&"cow")));
    # a visit with a seed and some chickens on offer
    world.traders.last_visit_day = -99;
    world.traders.start_visit();
    world.traders.merchant.state = Merchant.State.TRADING;
    world.traders.merchant.path = [];
    world.traders.visit = {"stock": {Defs.seed_key(&"potato"): 1, Defs.animal_key(&"chicken"): 6}, "wants": {&"wheat": 1.0}, "days_left": 4, "arrived": true};
    world.town_hall.store(&"wheat", 100);
    _expect("potatoes are not known yet", not world.seeds.has(&"potato"));
    # seed 30 x 1.25 = 37.5, six chickens 6 x 15 = 90: 128 for 65 wheat at 2
    var err:String = _post.place_order({&"wheat": 70}, {Defs.seed_key(&"potato"): 1, Defs.animal_key(&"chicken"): 4});
    _expect("an order for a seed and animals is accepted (%s)" % err, err == "" and _post.has_order());
    _post.deliver(&"wheat", 70);
    world.town_hall.take(&"wheat", 70);
    _expect("when it settles the seed is known at once", not _post.has_order() and world.seeds.has(&"potato"));
    _expect("and the chickens wait at the post (%s)" % [_post.animals_waiting], _post.animals_waiting.get(&"chicken", 0) == 4);
    _expect("the merchant has two chickens left", world.traders.visit["stock"].get(Defs.animal_key(&"chicken"), 0) == 2);
    _expect("the inspector says so", _post.info_text().contains("Waiting to be led to a pasture: 4 chickens"));
    _expect("the post cannot be moved with animals waiting", world.relocation_block_reason(_post) != "");
    _expect("the pen is still empty", _pen.animals == 0);
    GameClock.set_speed(3);
    Engine.time_scale = 4.0;
    _start = GameClock.total_hours;
    _phase = 1;

func _count_offers(key:StringName, visits:int) -> int:
    var n:int = 0;
    for i in visits:
        if world.traders._make_visit()["stock"].has(key):
            n += 1;
    return n;

func _process(_delta:float) -> void:
    for p in world.pawns:
        p.hunger = 1.0; p.thirst = 1.0; p.energy = 1.0; p.warmth = 1.0;
    var hours:float = GameClock.total_hours - _start;
    if _phase == 1 and _pen.animals >= 4:
        _expect("a citizen led the chickens to the pasture (%.1f hours)" % hours, true);
        _expect("none are left at the post", _post.animals_waiting.is_empty() and _pen.incoming_animals == 0);
        _expect("the pen now has them", _pen.animals == 4 or _pen.animals > 4);
        _phase = 2;
        _cancel_case();
    elif _phase == 2 and _pen.animals >= 6:
        _expect("a trip cut short puts the animals back at the post, and the next trip finishes it (%d in the pen)" % _pen.animals, _post.animals_waiting.is_empty());
        print("TRADE GOODS %s" % ("PASS" if _fails == 0 else "FAIL"));
        get_tree().quit(1 if _fails > 0 else 0);
    if hours > 80.0:
        print("FAIL timed out in phase %d (pen %d, waiting %s)" % [_phase, _pen.animals, _post.animals_waiting]);
        print("TRADE GOODS FAIL");
        get_tree().quit(1);

# Two more chickens arrive; whoever sets out with them is stopped halfway, and they must go back to the post.
func _cancel_case() -> void:
    _post.animals_waiting[&"chicken"] = 2;
    for p in world.pawns:
        p.end_task(false);
    var guide:Task = null;
    for p in world.pawns:
        var t:Task = world.jobs.trade.trade_task(p);
        if t != null and t.kind == &"guide":
            p.task = t;
            guide = t;
            _expect("setting out takes the animals off the post's list", _post.animals_waiting.is_empty() and _pen.incoming_animals == 2);
            p.end_task(false);
            break;
    _expect("a guide task existed", guide != null);
    _expect("cutting it short gives them back and frees the room (post %s, incoming %d)" % [_post.animals_waiting, _pen.incoming_animals], _post.animals_waiting.get(&"chicken", 0) == 2 and _pen.incoming_animals == 0);

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
