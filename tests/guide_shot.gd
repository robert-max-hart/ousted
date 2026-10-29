# ----------------------------------------------------------------
# Trade goods screenshots (M6 step 3): the window with seeds and
# animals on offer, then a citizen leading bought chickens and a cow
# from the Trading Post to their pastures.
#     godot --path . res://tests/guide_shot.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

var world:World;
var _out:String = "user://";
var _frame:int = 0;
var _post:TradingPost;
var _shots:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Weather.drought_enabled = false;
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0:
        _out = args[0];
    Defs.difficulty = &"normal";
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    var o:Vector2i = world.town_hall.origin + Vector2i(8, -10);
    for rn in world.nodes.duplicate():
        if Rect2i(o - Vector2i(3, 3), Vector2i(28, 14)).has_point(rn.cell):
            world.remove_node(rn);
    world.terrain.flatten_rect(Rect2i(o - Vector2i(2, 2), Vector2i(30, 16)));
    _post = world.place_building(&"trading_post", o, Vector2i(4, 3), true) as TradingPost;
    world.place_building(&"coop", o + Vector2i(8, 0), Vector2i(4, 4), true);
    world.place_building(&"pasture", o + Vector2i(15, 0), Vector2i(6, 6), true);
    world.traders.last_visit_day = -99;
    world.traders.start_visit();
    world.traders.merchant.state = Merchant.State.TRADING;
    world.traders.merchant.path = [];
    world.traders.visit = {"stock": {&"iron": 4, Defs.seed_key(&"pumpkin"): 1, Defs.seed_key(&"apple"): 1, Defs.animal_key(&"chicken"): 5, Defs.animal_key(&"cow"): 2}, "wants": {&"wheat": 1.2, &"barley": 1.5}, "days_left": 3, "arrived": true};
    world.town_hall.store(&"wheat", 60);
    world.camera_rig.focus_on(Vector3(o.x + 8, 0, o.y + 3));
    world.camera_rig._distance = 22.0;
    world.camera_rig._target_distance = 22.0;
    world.tools.select(_post);

func _process(_delta:float) -> void:
    _frame += 1;
    if _frame == 10:
        world.hud._trade_btn.pressed.emit();
        var p:TradePanel = world.hud._trade_panel;
        p._change(Defs.seed_key(&"apple"), true, 1);
        p._change(Defs.animal_key(&"chicken"), true, 4);
        p._change(&"wheat", false, 70);
    if _frame == 40:
        get_viewport().get_texture().get_image().save_png(_out.path_join("guide_a.png"));
        world.hud._trade_panel._on_place();
        world.hud._trade_panel.visible = false;
        _post.animals_waiting[&"cow"] = 1;
        GameClock.set_speed(3);
        Engine.time_scale = 1.0;
    if _frame > 60 and _shots < 4 and _frame % 70 == 0:
        _shots += 1;
        for p in world.pawns:
            if p.task != null and p.task.kind == &"guide":
                world.camera_rig.focus_on(Vector3(p.position.x, 0, p.position.z));
                world.camera_rig._distance = 11.0;
                world.camera_rig._target_distance = 11.0;
        get_viewport().get_texture().get_image().save_png(_out.path_join("guide_%d.png" % (_shots + 1)));
    if _frame > 700:
        get_tree().quit();
