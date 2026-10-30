# ----------------------------------------------------------------
# One Pasture building, many animals; starting orchard seeds
#     The pasture keeps the animal chosen in the inspector (changeable
#     only while empty); old saves with a Chicken Run, Cow Pasture or
#     Sheep Pasture load as a pasture of that animal; a new game starts
#     with 0, 1 or 2 random orchard seeds by difficulty.
#     godot --headless --path . --fixed-fps 60 res://tests/pasture_kind.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;
var world:World;
var _frame:int = 0;
var _data:Dictionary = {};

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    var easy:int = _tree_count(world.seeds);
    _expect("easy starts with two orchard seeds (%d)" % easy, easy == 2);
    var again:Seeds = Seeds.new();
    var rng:RandomNumberGenerator = RandomNumberGenerator.new();
    rng.seed = 7;
    again.grant_trees(rng);
    var other:Seeds = Seeds.new();
    rng.seed = 7;
    other.grant_trees(rng);
    _expect("the pick is random but follows the seed", again.known.keys() == other.known.keys());
    var variety:Dictionary = {};
    for s in 30:
        var sd:Seeds = Seeds.new();
        rng.seed = s;
        sd.grant_trees(rng);
        variety[str(sd.known.keys())] = true;
    _expect("and varies between seeds (%d different sets)" % variety.size(), variety.size() > 1 or Defs.CROPS.size() < 4);
    Defs.difficulty = &"normal";
    var n:Seeds = Seeds.new();
    n.grant_trees(rng);
    _expect("normal starts with one (%d)" % _tree_count(n), _tree_count(n) == 1);
    Defs.difficulty = &"hard";
    var h:Seeds = Seeds.new();
    h.grant_trees(rng);
    _expect("hard with none (%d)" % _tree_count(h), _tree_count(h) == 0);
    Defs.difficulty = &"easy";
    # the pasture
    var o:Vector2i = TestSite.near(world, Vector2i(8, -10));
    for rn in world.nodes.duplicate():
        if Rect2i(o - Vector2i(3, 3), Vector2i(20, 14)).has_point(rn.cell):
            world.remove_node(rn);
    world.terrain.flatten_rect(Rect2i(o - Vector2i(2, 2), Vector2i(22, 16)));
    var pen:Pasture = world.place_building(&"pasture", o, Vector2i(5, 5), true) as Pasture;
    _expect("there is one pasture building and no per-animal ones", Defs.BUILDINGS.has(&"pasture") and not Defs.BUILDINGS.has(&"coop") and not Defs.BUILDINGS.has(&"sheepfold"));
    _expect("it starts on chickens", pen.kind == &"chicken" and pen.display_name() == "Chicken Pasture");
    _expect("any animal can be chosen while it is empty", pen.set_kind(&"cow") and pen.kind == &"cow" and pen.display_name() == "Cow Pasture");
    _expect("an unknown animal is refused", not pen.set_kind(&"dragon") and pen.kind == &"cow");
    pen.add_animals(1);
    _expect("with an animal in it the choice is locked", not pen.can_change_kind() and not pen.set_kind(&"sheep") and pen.kind == &"cow");
    pen.animals = 0;
    pen.incoming_animals = 1;
    _expect("and while some are on the way", not pen.set_kind(&"sheep"));
    pen.incoming_animals = 0;
    _expect("merchants count the pasture under its animal", pen.free_room() > 0 and pen.kind == &"cow");
    pen.set_kind(&"sheep");
    var d:Dictionary = pen.to_dict();
    _expect("the animal is saved", d["kind"] == &"sheep");
    # old saves
    _data = world.serialize();
    for bd in _data["buildings"]:
        if bd["id"] == &"pasture":
            bd["id"] = &"coop";
            bd.erase("kind");
    var old_cows:Dictionary = (_data["buildings"] as Array)[0].duplicate(true);
    remove_child(world);
    world.queue_free();
    World.pending_load = _data;
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    var pens:Array[Pasture] = [];
    for b in world.buildings:
        if b is Pasture:
            pens.append(b);
    _expect("an old Chicken Run loads as a chicken pasture (%d pens)" % pens.size(), pens.size() == 1 and pens[0].kind == &"chicken" and pens[0].def_id == &"pasture");
    var legacy:Dictionary = Defs.LEGACY_PASTURES;
    _expect("the old ids map to their animals", legacy[&"coop"] == &"chicken" and legacy[&"pasture"] == &"cow" and legacy[&"sheepfold"] == &"sheep");
    _expect("loading kept the starting seeds of the save", old_cows.size() > 0 and _tree_count(world.seeds) >= 2);
    print("PASTURE KIND %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _tree_count(s:Seeds) -> int:
    var k:int = 0;
    for id in s.known:
        if Defs.CROPS.has(id) and Defs.CROPS[id].get("tree", false):
            k += 1;
    return k;

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
