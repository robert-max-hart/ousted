# ----------------------------------------------------------------
# Terrain look test
#     Snow never lies under or at the water (the vertex colour's alpha, how well snow lies, is 0 there and rises
#     over the shore); the desert's ground is tan, not green, with sandstone rock and fewer grass tufts, flowers and
#     trees than temperate land; other climates keep the usual green.
#     godot --headless --path . --fixed-fps 60 res://tests/terrain_look.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    Weather.drought_enabled = false;
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    await get_tree().process_frame;
    await get_tree().process_frame;
    var t:Terrain = world.terrain;
    var under:int = 0;
    var under_snowy:int = 0;
    var high:int = 0;
    var high_snowy:int = 0;
    for chunk in t._chunks:
        var mesh:ArrayMesh = chunk.mesh as ArrayMesh;
        if mesh == null or mesh.get_surface_count() == 0:
            continue;
        var arrays:Array = mesh.surface_get_arrays(0);
        var verts:PackedVector3Array = arrays[Mesh.ARRAY_VERTEX];
        var cols:PackedColorArray = arrays[Mesh.ARRAY_COLOR];
        for i in verts.size():
            if verts[i].y <= Terrain.WATER_LEVEL + 0.001:
                under += 1;
                if cols[i].a > 0.001:
                    under_snowy += 1;
            elif verts[i].y > Terrain.WATER_LEVEL + Terrain.SNOW_SHORE + 0.5:
                high += 1;
                if cols[i].a > 0.1:
                    high_snowy += 1;
    print("corners at or under water %d (%d could hold snow), dry land %d (%d can)" % [under, under_snowy, high, high_snowy]);
    _expect("there is water to check", under > 100);
    _expect("no corner at or under the water can hold snow", under_snowy == 0);
    _expect("dry land still can", high_snowy > high * 0.5);
    # the colours of a climate
    Climate.current = Climate.Id.TEMPERATE;
    t.set_season(1);
    var green:Color = t._ground_colour();
    _expect("temperate ground is green (%s)" % green, green.g > green.r and green.g > green.b);
    Climate.current = Climate.Id.DESERT;
    var tan:Color = t._ground_colour();
    _expect("desert ground is tan, not green (%s)" % tan, tan.r > tan.g and tan.g > tan.b and tan.g - tan.b > 0.1 and tan.r > 0.6);
    _expect("its rock is sandstone and its beaches pale sand", t._rock_colour().r > t._rock_colour().b + 0.15 and t._sand_colour().get_luminance() > Terrain.COLOR_SAND.get_luminance());
    Climate.current = Climate.Id.TROPICAL;
    _expect("tropical ground stays green", t._ground_colour() == Terrain.GRASS_BY_SEASON[1] and t._sand_colour() == Terrain.COLOR_SAND);
    Climate.current = Climate.Id.TEMPERATE;
    _expect("the desert has fewer tufts and flowers", float(Climate.DEFS[Climate.Id.DESERT]["tufts"]) < 0.5 and float(Climate.DEFS[Climate.Id.DESERT]["flowers"]) < 0.3);
    _expect("and far fewer trees than before (0.04 of temperate)", float(Climate.DEFS[Climate.Id.DESERT]["trees"]) <= 0.05);
    var usual:Color = Climate.tuft_colour(1, Color.GREEN);
    Climate.current = Climate.Id.DESERT;
    var straw:Color = Climate.tuft_colour(1, Color.GREEN);
    Climate.current = Climate.Id.TEMPERATE;
    _expect("desert tufts are straw coloured, the others keep the usual green", usual == Color.GREEN and straw != Color.GREEN and straw.r > straw.g * 0.9);
    print("TERRAIN LOOK %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    if ok:
        print("PASS: ", what);
    else:
        print("FAIL: ", what);
        _fails += 1;
