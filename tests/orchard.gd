# ----------------------------------------------------------------
# Orchards
#     Trees are planted once and fruit every year; fields and orchards
#     keep to their own crops; the cold does not kill trees.
#     godot --headless --path . --fixed-fps 60 res://tests/orchard.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;
var world:World;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    Weather.drought_enabled = false;
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    Weather._day_offset = 0.0;
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON * 1 + 2) * GameClock.HOURS_PER_DAY + 12.0;      # early summer
    Weather._update_temperature();
    var o:Vector2i = world.town_hall.origin + Vector2i(8, -10);
    for rn in world.nodes.duplicate():
        if Rect2i(o - Vector2i(3, 3), Vector2i(26, 14)).has_point(rn.cell):
            world.remove_node(rn);
    world.terrain.flatten_rect(Rect2i(o - Vector2i(2, 2), Vector2i(28, 16)));
    var orch:Field = world.place_building(&"orchard", o, Vector2i(4, 4), true) as Field;
    var field:Field = world.place_building(&"field", o + Vector2i(8, 0), Vector2i(4, 4), true) as Field;
    _expect("an orchard is a field of tree crops", orch.is_orchard() and not field.is_orchard());
    _expect("a new orchard has no saplings for a start (apple saplings are not in the starting seeds)", not world.seeds.has(&"apple"));
    _expect("so it cannot be set to apples yet", not orch.set_crop(&"apple"));
    _expect("and no new orchard can be placed yet", world.can_place(&"orchard", o + Vector2i(0, 8), Vector2i(4, 4)) != "");
    world.seeds.unlock(&"apple");
    world.seeds.unlock(&"pear");
    _expect("with the saplings found it can", orch.set_crop(&"apple") and world.can_place(&"orchard", o + Vector2i(0, 8), Vector2i(4, 4)) == "");
    _expect("an orchard refuses a field crop", not orch.set_crop(&"wheat"));
    _expect("and a field refuses a tree", not field.set_crop(&"apple"));
    _expect("the orchard's ground is its own", world.terrain.get_overlay(o) == Terrain.Overlay.ORCHARD and world.terrain.get_overlay(o + Vector2i(8, 0)) == Terrain.Overlay.TILLED);
    _expect("it can be planted in summer", orch.can_plant());
    # plant, grow, harvest, regrow
    var farmer:Pawn = world.pawns[0];
    orch.apply(5, &"plant", farmer);
    _expect("planting makes a sapling", orch.plot_state[5] == Field.Plot.PLANTED and orch.plot_crop[5] == &"apple");
    orch.growth[5] = 1.0;
    orch.plot_state[5] = Field.Plot.RIPE;
    farmer.clear_carry();
    orch.apply(5, &"harvest", farmer);
    _expect("the first fruit comes in (%d %s)" % [farmer.carry_amount, farmer.carry_item], farmer.carry_item == &"apples" and farmer.carry_amount >= 3);
    _expect("the tree stays and fruits again later", orch.plot_state[5] == Field.Plot.PLANTED and orch.growth[5] < 1.0 and orch.growth[5] > 0.0);
    # a hard winter does not kill it
    orch.growth[5] = 0.8;
    GameClock.total_hours = (GameClock.DAYS_PER_SEASON * 3 + 4) * GameClock.HOURS_PER_DAY;
    Weather._update_temperature();
    for i in 24:
        orch.on_hour();
    _expect("trees survive the winter (temp %.0f)" % Weather.temperature, orch.plot_state[5] == Field.Plot.PLANTED);
    # ripe fruit left in the cold is not lost either
    orch.plot_state[5] = Field.Plot.RIPE;
    orch.on_hour();
    _expect("and unpicked fruit stays on the tree", orch.plot_state[5] == Field.Plot.RIPE);
    # many harvests do not wrap the count into a replant
    orch.cuts[5] = 255;
    orch.apply(5, &"harvest", farmer);
    _expect("the harvest count never runs the tree out", orch.plot_state[5] == Field.Plot.PLANTED);
    # the crop menu and saving
    var d:Dictionary = orch.to_dict();
    _expect("the orchard saves its tree", d["crop_id"] == &"apple");
    var trees:Array = Defs.CROPS.keys().filter(func(id:StringName) -> bool: return Defs.CROPS[id].get("tree", false));
    _expect("two tree crops exist and are food", trees.size() == 2 and Defs.is_food(&"apples") and Defs.is_food(&"pears"));
    print("ORCHARD %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
