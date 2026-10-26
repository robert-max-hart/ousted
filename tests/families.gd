# ----------------------------------------------------------------
# Families test
#     Pairing rules (adults only, an age gap of at most 10 years, no kin),
#     births needing a free slot in the pair's house, a baby fed by an
#     adult from its house, widowing, orphans moving into a house with room
#     and the family links surviving a save. Prints PASS or FAIL lines.
#     godot --headless --path . --fixed-fps 60 res://tests/families.tscn
# ----------------------------------------------------------------
extends Node;

var world:World;
var h1:Building;
var h2:Building;
var baby:Pawn;
var _stage:int = 0;
var _stage_start:float = 0.0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";        # the whole starting stock fits in the Town Hall
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    Engine.time_scale = 4.0;
    Defs.ageing_days_per_year = 400.0;      # nobody changes life stage during the test
    var th:Building = world.town_hall;
    var spots:Array[Vector2i] = [];
    for dz in range(-12, 12, 4):
        var o:Vector2i = th.origin + Vector2i(6, dz);
        if world.can_place(&"house", o, Vector2i(3, 3)) == "":
            spots.append(o);
    h1 = world.place_building(&"house", spots[0], Vector2i(3, 3), true);
    h2 = world.place_building(&"house", spots[1], Vector2i(3, 3), true);
    h1.settings["heating"] = false;
    h2.settings["heating"] = false;
    _expect("a house sleeps 6", h1.def["beds"] == 6);
    _expect("the six settlers filled the first house", h1.residents.size() == 6 and h2.residents.is_empty());
    var a:Pawn = world.pawns[0];
    var b:Pawn = world.pawns[1];
    a.age = 25.0; b.age = 34.0;
    var far:Pawn = world.pawns[2];
    far.age = 50.0;
    var kid:Pawn = world.pawns[3];
    kid.age = 10.0;
    var rel:Pawn = world.pawns[4];
    rel.age = 27.0;
    rel.parents = [a];
    _expect("9 years apart can pair", world.families.can_pair(a, b));
    _expect("25 years apart cannot pair", not world.families.can_pair(a, far));
    _expect("a child cannot pair", not world.families.can_pair(a, kid));
    _expect("a parent and child cannot pair", not world.families.can_pair(a, rel));
    var sib:Pawn = world.pawns[5];
    sib.age = 26.0;
    sib.parents = [a];
    _expect("siblings cannot pair", not world.families.can_pair(rel, sib));
    world.families.pair(a, b);
    _expect("a pair is linked both ways", a.partner == b and b.partner == a);
    # nobody else should pair or have kids behind this test's back
    for p in world.pawns:
        if p != a and p != b:
            p.pair_ready_hour = INF;
    # house is full (6/6): no conception however often we try
    for i in 300:
        world.families._births();
    _expect("a full house gets no pregnancy", a.due_hour < 0.0 and b.due_hour < 0.0);
    # free a slot: the house now has room
    world.families.move_home(world.pawns[5], h2);
    var tries:int = 0;
    while a.due_hour < 0.0 and b.due_hour < 0.0 and tries < 400:
        world.families._births();
        tries += 1;
    var carrier:Pawn = a if a.due_hour >= 0.0 else b;
    _expect("a pair in a house with room conceives (%d tries)" % tries, carrier.due_hour >= 0.0);
    _expect("the due date is %d days away" % Defs.PREGNANCY_DAYS, is_equal_approx(carrier.due_hour - GameClock.total_hours, Defs.PREGNANCY_DAYS * 24.0));
    _expect("the inspector says expecting", carrier.info_text().contains("Expecting a baby"));
    world.families.move_home(world.pawns[5], h1);       # room taken again before the birth
    carrier.due_hour = GameClock.total_hours - 1.0;
    world.families._births();
    _expect("no birth while the house is full", carrier.due_hour >= 0.0);
    world.families.move_home(world.pawns[5], h2);
    var count:int = world.pawns.size();
    world.families._births();
    _expect("a baby is born once there is room", world.pawns.size() == count + 1);
    baby = world.pawns[world.pawns.size() - 1];
    _expect("it is a baby with both parents and the parents' house", baby.is_baby() and baby.age == 0.0 and baby.parents.size() == 2 and baby.home == h1 and h1.residents.has(baby));
    _expect("the carrier is no longer expecting and cannot conceive soon", carrier.due_hour < 0.0 and carrier.conceive_ready_hour > GameClock.total_hours);
    _expect("the baby is indoors", baby.indoors);
    _expect("children are listed in the inspector", a.info_text().contains(baby.first_name) and a.info_text().contains("Children: "));
    # food and a hungry baby: an adult from the house brings it
    for item in Defs.ITEMS:
        if Defs.is_food(item):
            world.town_hall.store(item, 20);
            break;
    baby.hunger = 0.3;
    baby.thirst = 0.3;
    for p in world.pawns:
        p.hunger = 1.0;
    _stage_start = GameClock.total_hours;
    GameClock.set_speed(3);
    _stage = 1;

func _process(_delta:float) -> void:
    if _stage == 1:
        var hours:float = GameClock.total_hours - _stage_start;
        for p in world.pawns:
            if p.is_adult():
                p.hunger = maxf(p.hunger, 0.8);
                p.thirst = maxf(p.thirst, 0.8);
        if baby.hunger > 0.7 and baby.thirst > 0.7:
            _expect("an adult from the house fed and watered the baby within %.1f hours" % hours, true);
            _stage = 2;      # the task ends a frame later
            _stage_start = 0.0;
        elif hours > 12.0:
            _expect("the baby was fed (hunger %.2f, thirst %.2f)" % [baby.hunger, baby.thirst], false);
            get_tree().quit();

    elif _stage == 2:
        _expect("the reservation is released", baby.carer == null);
        _after_care();

func _after_care() -> void:
    _stage = 3;
    var data:Dictionary = world.serialize();
    var saved_baby:Dictionary = data["pawns"][data["pawns"].size() - 1];
    var linked:int = 0;
    for pd in data["pawns"]:
        if pd["partner"] >= 0 and data["pawns"][pd["partner"]]["partner"] == data["pawns"].find(pd):
            linked += 1;
    _expect("a saved pair points at each other (%d citizens)" % linked, linked == 2);
    _expect("a saved baby keeps both parents", saved_baby["parents"].size() == 2 and saved_baby["age"] < 1.0);
    var a:Pawn = baby.parents[0];
    var b:Pawn = baby.parents[1];
    var t0:float = GameClock.total_hours;
    world.kill_pawn(a, "test");
    _expect("the survivor is widowed", b.partner == null and b.pair_ready_hour > t0);
    _expect("the baby lost that parent", baby.parents == [b]);
    world.kill_pawn(b, "test");
    _expect("the baby is an orphan", baby.parents.is_empty() and baby.info_text().contains("orphan"));
    # a homeless orphan moves into a house with room
    world.families.move_home(baby, null);
    _expect("the orphan is homeless", baby.home == null);
    world.families.assign_homes();
    _expect("the orphan moved into a house with room", baby.home != null and baby.home != world.town_hall);
    get_tree().quit();

func _expect(what:String, ok:bool) -> void:
    print("%s: %s" % ["PASS" if ok else "FAIL", what]);
