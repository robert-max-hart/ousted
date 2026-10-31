# ----------------------------------------------------------------
# Crop models test
#     Every crop has a young, a grown and a ripe model and every plant class a seedling and a withered one;
#     a plot gets the model of its stage (seedling, young, grown, ripe, withered), a field draws one layer per
#     model in use and empties the ones it stops using, and frost and pests keep the model (they only tint it).
#     godot --headless --path . --fixed-fps 60 res://tests/crop_models.tscn
# ----------------------------------------------------------------
extends Node;

const CROPS:Array[StringName] = [&"wheat", &"barley", &"beans", &"potato", &"radish", &"lettuce", &"cabbage", &"pumpkin"];

var _fails:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Weather.drought_enabled = false;
    for crop in CROPS:
        for stage in ["young", "grown", "ripe"]:
            _expect("%s %s loads" % [crop, stage], CropMeshes.crop_model("%s_%s" % [crop, stage]) != null);
    for cls in ["grain", "leafy", "bush", "vine"]:
        _expect("%s seedling and withered load" % cls, CropMeshes.crop_model("sprout_%s" % cls) != null and CropMeshes.crop_model("dead_%s" % cls) != null);
    for crop in Defs.CROPS:
        if not Defs.CROPS[crop].get("tree", false):
            _expect("%s has a plant class" % crop, CropMeshes.shape_of(crop) in [&"grain", &"leafy", &"bush", &"vine"]);
    _expect("a young plot of wheat is a seedling", CropMeshes.crop_key(&"wheat", Field.Plot.PLANTED, 0.1) == "sprout_grain");
    _expect("then young", CropMeshes.crop_key(&"wheat", Field.Plot.PLANTED, 0.4) == "wheat_young");
    _expect("then grown", CropMeshes.crop_key(&"wheat", Field.Plot.PLANTED, 0.8) == "wheat_grown");
    _expect("ripe", CropMeshes.crop_key(&"wheat", Field.Plot.RIPE, 1.0) == "wheat_ripe");
    _expect("frozen plots keep their stage", CropMeshes.crop_key(&"pumpkin", Field.Plot.FROZEN, 0.8) == "pumpkin_grown");
    _expect("a dead cabbage is a withered leafy plot", CropMeshes.crop_key(&"cabbage", Field.Plot.DEAD, 0.5) == "dead_leafy");
    _expect("sizes grow within a stage", CropMeshes.stage_progress(Field.Plot.PLANTED, 0.1) < CropMeshes.stage_progress(Field.Plot.PLANTED, 0.2));

    Defs.difficulty = &"easy";
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    world.seeds.unlock_all();
    await get_tree().process_frame;
    var at:Vector2i = TestSite.spot(world, Vector2i(8, 2), Vector2i(-14, -14));
    var field:Field = world.place_building(&"field", at, Vector2i(8, 2), true) as Field;
    for i in field.plot_count():
        field.plot_crop[i] = CROPS[i % 8];
        field.plot_state[i] = Field.Plot.RIPE if i < 8 else Field.Plot.PLANTED;
        field.growth[i] = 1.0 if i < 8 else 0.1;
    field._rebuild_crops();
    _expect("the ripe row uses eight ripe models", field._crop_layers.has("wheat_ripe") and field._crop_layers.has("pumpkin_ripe"));
    _expect("the seedlings share class models", (field._crop_layers["sprout_grain"] as MultiMeshInstance3D).multimesh.instance_count == 2 and (field._crop_layers["sprout_leafy"] as MultiMeshInstance3D).multimesh.instance_count == 3);
    for i in 8:
        field.plot_state[i] = Field.Plot.FALLOW;
    field._rebuild_crops();
    _expect("a model no plot uses is emptied", (field._crop_layers["wheat_ripe"] as MultiMeshInstance3D).multimesh.instance_count == 0);
    field.plot_state[8] = Field.Plot.FROZEN;
    field.pests[9] = 0.5;
    field._rebuild_crops();
    _expect("a frozen plot keeps its model (the tint is looked at in crops_shot: a headless run keeps no instance data)", (field._crop_layers["sprout_grain"] as MultiMeshInstance3D).multimesh.instance_count == 2);
    print("CROP MODELS %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    if ok:
        print("PASS: ", what);
    else:
        _fails += 1;
        print("FAIL: ", what);
