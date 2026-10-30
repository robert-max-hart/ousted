# ----------------------------------------------------------------
# Clicking the merchant banner
#     With a merchant about, a real mouse click on the "Merchant ..."
#     banner under the top bar moves the camera to them.
#     godot --headless --path . --fixed-fps 60 res://tests/merchant_click.tscn
# ----------------------------------------------------------------
extends Node;

var world:World;
var _frame:int = 0;
var _fails:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    var o:Vector2i = TestSite.near(world, Vector2i(8, -10));
    var post:TradingPost = world.place_building(&"trading_post", o, Vector2i(4, 3), true) as TradingPost;
    world.traders.last_visit_day = -99;
    world.traders.start_visit();
    world.traders.merchant.state = Merchant.State.TRADING;
    world.traders.merchant.path = [];
    world.traders.merchant.position = Vector3(20.0, 0.0, 30.0);
    world.camera_rig.focus_on(Vector3(100.0, 0.0, 100.0));

func _process(_delta:float) -> void:
    _frame += 1;
    var label:Label = world.hud._merchant_label;
    if _frame == 6:
        _expect("the banner shows (%s)" % label.text, label.visible and label.text != "");
        var rect:Rect2 = label.get_global_rect();
        var at:Vector2 = rect.get_center();
        _expect("the banner has a size (%s)" % rect, rect.size.x > 20.0 and rect.size.y > 8.0);
        var press:InputEventMouseButton = InputEventMouseButton.new();
        press.position = at;
        press.global_position = at;
        press.button_index = MOUSE_BUTTON_LEFT;
        press.pressed = true;
        var move:InputEventMouseMotion = InputEventMouseMotion.new();
        move.position = at;
        move.global_position = at;
        if DisplayServer.get_name() == "headless":          # (a headless window has no mouse hover: call the handler)
            world.hud._on_merchant_label_input(press);
        else:
            get_viewport().push_input(move);
            get_viewport().push_input(press);
    if _frame == 10:
        var p:Vector3 = world.camera_rig.position;
        _expect("the camera went to the merchant (%s)" % p, absf(p.x - 20.0) < 1.0 and absf(p.z - 30.0) < 1.0);
        print("MERCHANT CLICK %s" % ("PASS" if _fails == 0 else "FAIL"));
        get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
