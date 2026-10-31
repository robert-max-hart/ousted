# ----------------------------------------------------------------
# Slope overlay
#     The relief number agrees with what World.can_place accepts for a
#     house (green and orange ground take one, red ground refuses it as
#     too steep), the colours run green to red, the overlay toggles on
#     Terrain, and the top bar's three overlays exclude each other.
#     godot --headless --path . --fixed-fps 60 res://tests/slope_view.tscn
# ----------------------------------------------------------------
extends Node;

const STEEP_MESSAGE:String = "Ground is too steep (flatten it first)";
var _fails:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    var t:Terrain = world.terrain;
    _expect("level ground is green, the limit orange, past it red", Terrain.slope_color(0.0).g > Terrain.slope_color(0.0).r and Terrain.slope_color(Terrain.BUILD_SLOPE).r > 0.9 and Terrain.slope_color(Terrain.BUILD_SLOPE + 1.0).r > 0.8 and Terrain.slope_color(Terrain.BUILD_SLOPE + 1.0).g < 0.3);
    _expect("the limit is the one building uses", World.MAX_BUILD_SLOPE == Terrain.BUILD_SLOPE);
    var flat_ok:int = 0;
    var flat_n:int = 0;
    var steep_ok:int = 0;
    var steep_n:int = 0;
    var size:Vector2i = Defs.BUILDINGS[&"house"]["size"];
    for z in range(4, Terrain.SIZE - 4, 3):
        for x in range(4, Terrain.SIZE - 4, 3):
            var c:Vector2i = Vector2i(x, z);
            if t.is_water(c) or t.cell_height(c) < Terrain.WATER_LEVEL + 0.6:
                continue;
            var r:float = t.relief(c);
            var said:String = world.can_place(&"house", c - Vector2i.ONE, size);
            if r <= Terrain.BUILD_SLOPE and flat_n < 400:
                flat_n += 1;
                flat_ok += 1 if said != STEEP_MESSAGE else 0;
            elif r > Terrain.BUILD_SLOPE and steep_n < 400:
                steep_n += 1;
                steep_ok += 1 if said != "" else 0;       # (a spot next to water is refused for the water first)
    print("%d of %d green or orange spots are not refused as steep, %d of %d red ones are refused" % [flat_ok, flat_n, steep_ok, steep_n]);
    _expect("there is flat and steep ground to compare", flat_n > 20 and steep_n > 5);
    _expect("no green or orange spot is refused for its slope", flat_ok == flat_n);
    _expect("every red spot is refused", steep_ok == steep_n);
    t.set_slope_view(true);
    _expect("the overlay toggles", t.slope_view);
    t.set_slope_view(false);
    _expect("and turns off", not t.slope_view);
    var hud:HUD = world.hud;
    hud._soil_toggle.button_pressed = true;
    hud._slope_toggle.button_pressed = true;
    _expect("slope switches soil off", not hud._soil_toggle.button_pressed and t.slope_view and not t.soil_view);
    hud._water_toggle.button_pressed = true;
    _expect("water switches slope off", not hud._slope_toggle.button_pressed and not t.slope_view and t.water_view);
    hud._soil_toggle.button_pressed = true;
    _expect("soil switches water off", not hud._water_toggle.button_pressed and not t.water_view and t.soil_view);
    print("SLOPE VIEW %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    print("%s: %s" % ["PASS" if ok else "FAIL", what]);
    if not ok:
        _fails += 1;
