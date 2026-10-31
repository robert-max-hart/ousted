# ----------------------------------------------------------------
# Model settings test
#     The tree, bush and rock layers are split into blocks of the map, each node is drawn in exactly one block, and the
#     blocks hide beyond the draw distance (Near, Normal, Far = no limit); the reduced model set swaps in simpler meshes
#     for the trees, plants and crops (layers made again, the same instances) and back; fields follow both settings.
#     godot --headless --path . --fixed-fps 60 res://tests/model_settings.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;

func _tris(mesh:Mesh) -> int:
    var n:int = 0;
    for s in mesh.get_surface_count():
        var arr:Array = mesh.surface_get_arrays(s);
        n += (arr[Mesh.ARRAY_INDEX].size() if arr[Mesh.ARRAY_INDEX] != null else arr[Mesh.ARRAY_VERTEX].size()) / 3;
    return n;

func _drawn(r:ResourceRenderer) -> int:
    var n:int = 0;
    for key in r._layers:
        n += (r._layers[key] as ChunkedLayer).total();
    return n;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Weather.drought_enabled = false;
    Defs.difficulty = &"easy";
    Settings.ensure_loaded();
    var keep:Array = [Settings.tree_distance, Settings.model_detail];
    Settings.set_value("tree_distance", 2);
    Settings.set_value("model_detail", 0);
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    world.seeds.unlock_all();
    await get_tree().process_frame;
    var r:ResourceRenderer = world.renderer;
    r._rebuild();
    var blocks:int = 0;
    for key in r._layers:
        blocks += (r._layers[key] as ChunkedLayer).chunk_count();
    var kinds:int = 0;
    for key in r._layers:
        if (r._layers[key] as ChunkedLayer).total() > 0:
            kinds += 1;
    _expect("the map's nature is split into blocks (%d blocks for %d kinds)" % [blocks, kinds], blocks > kinds * 2);
    _expect("and every node is drawn once: %d drawn" % _drawn(r), _drawn(r) == world.nodes.size());
    var pine:ChunkedLayer = null;
    for key in r._layers:
        if String(key).begins_with("tree:") and (r._layers[key] as ChunkedLayer).total() > 0:
            pine = r._layers[key];
            break;
    _expect("there are pines to look at", pine != null);
    var full_tris:int = _tris(pine.mesh);
    var pine_key:StringName = r._layers.find_key(pine);
    var any_mmi:MultiMeshInstance3D = null;
    for block in pine._chunks:
        any_mmi = pine._chunks[block];
        break;
    _expect("Far has no draw distance", any_mmi.visibility_range_end == 0.0);
    Settings.set_value("tree_distance", 0);
    _expect("Near hides blocks past %.0f m (and a block's reach)" % Settings.DISTANCES[0], any_mmi.visibility_range_end > Settings.DISTANCES[0] and any_mmi.visibility_range_end < Settings.DISTANCES[0] + 80.0);
    Settings.set_value("tree_distance", 1);
    _expect("Normal is farther than Near", any_mmi.visibility_range_end > Settings.DISTANCES[0] + ChunkedLayer.REACH);
    Settings.set_value("tree_distance", 2);
    _expect("and Far lifts it again", any_mmi.visibility_range_end == 0.0);

    # a field to follow the settings
    var at:Vector2i = TestSite.spot(world, Vector2i(6, 6), Vector2i(-14, -14));
    var field:Field = world.place_building(&"field", at, Vector2i(6, 6), true) as Field;
    for i in field.plot_count():
        field.plot_crop[i] = &"wheat";
        field.plot_state[i] = Field.Plot.RIPE;
        field.growth[i] = 1.0;
    field._rebuild_crops();
    var wheat_full:Mesh = (field._crop_layers["wheat_ripe"] as MultiMeshInstance3D).multimesh.mesh;
    var field_mmi:MultiMeshInstance3D = field._crop_layers["wheat_ripe"];
    Settings.set_value("tree_distance", 0);
    _expect("a field's plants are hidden past the draw distance too", field_mmi.visibility_range_end > 0.0);
    Settings.set_value("tree_distance", 2);

    Settings.set_value("model_detail", 1);
    _expect("the reduced set is the _low folder", Settings.model_dir(ResourceRenderer.TREE_DIR).ends_with("trees_low/"));
    r._rebuild();
    _expect("and every node is still drawn once", _drawn(r) == world.nodes.size());
    var pine_low:ChunkedLayer = r._layers.get(pine_key);
    var low_tris:int = _tris(pine_low.mesh);
    _expect("a reduced pine has fewer triangles than the full one (%d against %d)" % [low_tris, full_tris], low_tris < full_tris);
    _expect("the field's plants are made again from the reduced set", field._crop_layers.is_empty() or (field._crop_layers.values()[0] as MultiMeshInstance3D).multimesh.mesh != wheat_full);
    field._rebuild_crops();
    var wheat_low:Mesh = (field._crop_layers["wheat_ripe"] as MultiMeshInstance3D).multimesh.mesh;
    _expect("reduced wheat has fewer triangles (%d against %d)" % [_tris(wheat_low), _tris(wheat_full)], _tris(wheat_low) < _tris(wheat_full));
    Settings.set_value("model_detail", 0);
    r._rebuild();
    _expect("back to full: the pine is the full model again", _tris((r._layers.get(pine_key) as ChunkedLayer).mesh) == full_tris);
    Settings.set_value("tree_distance", keep[0]);
    Settings.set_value("model_detail", keep[1]);
    print("MODEL SETTINGS %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    if ok:
        print("PASS: ", what);
    else:
        _fails += 1;
        print("FAIL: ", what);
