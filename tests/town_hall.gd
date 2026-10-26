# ----------------------------------------------------------------
# Town Hall test
#     The three starting difficulties (what the Town Hall comes with and
#     where the starting goods go), the supply cart giving and vanishing,
#     the upgrades (storage tiers, hearth, governance), there being only
#     one but a new one being buildable once it is lost, and relocating
#     buildings (half the cost, state carried over, the old one removed).
#     godot --headless --path . --fixed-fps 60 res://tests/town_hall.tscn
# ----------------------------------------------------------------
extends Node;

var world:World;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Engine.time_scale = 4.0;
    Defs.ageing_days_per_year = 400.0;
    var total:int = 0;
    for item in World.START_STOCK:
        total += World.START_STOCK[item];
    _make_world(&"hard");
    _expect("hard: the Town Hall is just a well", not world.town_hall.is_storage() and world.town_hall.upgrades_done.is_empty() and world.town_hall.def.get("water", false));
    var cart:Building = _cart();
    _expect("hard: all %d starting goods are in a supply cart" % total, cart != null and cart.used() == total and Stock.amount(&"wood") == World.START_STOCK[&"wood"]);
    _expect("hard: the cart takes nothing new", not cart.can_store(&"wood") and world.nearest_storage_for(&"wood", cart.position) == null);
    _expect("hard: nothing is heated and policies are locked", not world.town_hall.is_heated() and not world.has_governance());
    var wood:int = cart.amount(&"wood");
    cart.take(&"wood", wood);
    world._on_hour(0);
    _expect("hard: a cart with goods left stays", _cart() != null);
    for item in cart.stored.keys():
        cart.take(item, cart.amount(item));
    world._on_hour(0);
    _expect("hard: an empty cart is gone", _cart() == null);
    _make_world(&"normal");
    _expect("normal: the Town Hall holds 100", world.town_hall.is_storage() and world.town_hall.capacity() == 100 and world.town_hall.used() == 100);
    _expect("normal: the rest of the goods are in a cart", _cart() != null and _cart().used() == total - 100);
    _make_world(&"easy");
    var th:Building = world.town_hall;
    _expect("easy: 300 storage, a hearth, and every start good in the hall", th.capacity() == 300 and th.is_heated() and th.used() == total and _cart() == null);
    _expect("easy: it is warm enough to warm up in", world.warm_shelter_for(world.pawns[0]) == th);
    _expect("easy: still no governance, no beds", not world.has_governance() and not th.def.has("beds"));
    _check_upgrades();
    _check_unique();
    _check_relocation();
    get_tree().quit();

func _make_world(difficulty:StringName) -> void:
    if world != null:
        world.free();
    Defs.difficulty = difficulty;
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);

func _cart() -> Building:
    for b in world.buildings:
        if b.def_id == &"cart":
            return b;
    return null;

func _check_upgrades() -> void:
    _make_world(&"hard");
    var th:Building = world.town_hall;
    _expect("the second store room needs the first", th.upgrade_block_reason(&"storage2") != "");
    th.upgrades_done[&"storage"] = true;
    _expect("... and then it is allowed", th.upgrade_block_reason(&"storage2") == "");
    th.upgrades_done[&"storage2"] = true;
    _expect("both store rooms make 300", th.capacity() == 300);
    _expect("governance is locked until built", not world.has_governance());
    th.upgrades_done[&"governance"] = true;
    _expect("governance unlocks policies", world.has_governance());
    _expect("the hearth is its own upgrade", not th.is_heated());
    th.upgrades_done[&"heating"] = true;
    _expect("the hearth heats it", th.is_heated());
    # starting an upgrade for real costs materials and labor like the mine's
    _make_world(&"hard");
    th = world.town_hall;
    _expect("an upgrade can be started", th.start_upgrade(&"storage"));
    _expect("it costs its materials", th.cost() == {&"wood": 20, &"stone": 5});
    th.work_done = th.work_required() - 0.01;
    th.add_work(1.0);
    _expect("finishing it unlocks the storage", th.has_upgrade(&"storage") and th.capacity() == 100 and th.is_storage());

func _check_unique() -> void:
    _make_world(&"easy");
    var th:Building = world.town_hall;
    _expect("a second Town Hall can't be placed", world.can_place(&"town_hall", th.origin + Vector2i(8, 8), Vector2i(4, 4)) != "");
    var hud_blocked:bool = true;
    for b in world.buildings:
        if b.def_id == &"town_hall" and b != th:
            hud_blocked = false;
    _expect("only one stands", hud_blocked);
    world.remove_building(th, true);
    _expect("it can't be demolished while it holds goods", World.alive(th) and world.town_hall == th);
    for item in th.stored.keys():
        th.take(item, th.amount(item));
    world.remove_building(th, true);
    _expect("empty, it can be demolished and the colony has none", world.town_hall == null);
    _expect("a new one may be built now", world.can_place(&"town_hall", Vector2i(60, 60), Vector2i(4, 4)) == "");
    var site:Building = world.place_building(&"town_hall", Vector2i(60, 60), Vector2i(4, 4));
    _expect("the new one is a site that costs 30 wood and 10 stone", site.cost() == {&"wood": 30, &"stone": 10} and not site.is_complete());
    site.complete();
    _expect("finished, it is the Town Hall again, bare", world.town_hall == site and site.upgrades_done.is_empty() and not site.is_storage());
    _expect("the HUD offer goes away again (one stands)", world.can_place(&"town_hall", Vector2i(70, 70), Vector2i(4, 4)) != "");

func _check_relocation() -> void:
    _make_world(&"easy");
    var th:Building = world.town_hall;
    var house:Building = world.place_building(&"house", th.origin + Vector2i(-8, 2), Vector2i(3, 3), true);
    var field:Building = world.place_building(&"field", th.origin + Vector2i(10, 10), Vector2i(4, 4), true);
    _expect("fields can't be moved", world.relocation_block_reason(field) == "Can't be moved");
    var yard:Building = world.place_building(&"graveyard", th.origin + Vector2i(10, -10), Vector2i(4, 3), true);
    _expect("graveyards can't be moved", world.relocation_block_reason(yard) != "");
    _expect("a full store room must be emptied first", world.relocation_block_reason(th) == "Empty it first");
    var residents:Array = house.residents.duplicate();
    house.settings["heating"] = false;
    house.fuel = 7;
    var spot:Vector2i = th.origin + Vector2i(-8, 8);
    _expect("a house can be moved", world.relocation_block_reason(house) == "");
    var site:Building = world.relocate(house, spot, house.size);
    _expect("a relocation makes a site at half the cost", site != null and not site.is_complete() and site.cost() == {&"wood": 8, &"stone": 2} and is_equal_approx(site.work_required(), 12.0));
    _expect("the old house still stands and shelters", World.alive(house) and house.residents.size() == residents.size());
    _expect("it can't be moved twice at once", world.relocation_block_reason(house) == "Already being moved");
    var data:Dictionary = world.serialize();
    var linked:bool = false;
    for bd in data["buildings"]:
        if bd["reloc_from"] >= 0:
            linked = true;
    _expect("the link is saved", linked);
    var wood_before:int = Stock.amount(&"wood");
    site.complete();
    _expect("the old house is gone and the new one has its residents", not World.alive(house) and site.residents.size() == residents.size() and residents.all(func(p:Pawn) -> bool: return p.home == site));
    _expect("settings and fuel came along", site.settings["heating"] == false and site.fuel == 7);
    _expect("nothing was refunded for the old house", Stock.amount(&"wood") == wood_before);
    # the Town Hall itself, with its upgrades
    th.upgrades_done[&"governance"] = true;
    for item in th.stored.keys():
        th.take(item, th.amount(item));
    _expect("an emptied Town Hall can be moved", world.relocation_block_reason(th) == "");
    var hall_site:Building = world.relocate(th, th.origin + Vector2i(0, 12), th.size);
    _expect("a second Town Hall is allowed for the move", hall_site != null and world.town_hall == th);
    hall_site.complete();
    _expect("the moved Town Hall keeps its upgrades and the role", world.town_hall == hall_site and hall_site.has_upgrade(&"storage2") and world.has_governance() and not World.alive(th));
    _expect("only one Town Hall remains", world.buildings.filter(func(b:Building) -> bool: return b.def_id == &"town_hall").size() == 1);

func _expect(what:String, ok:bool) -> void:
    print("%s: %s" % ["PASS" if ok else "FAIL", what]);
