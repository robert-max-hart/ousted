# ----------------------------------------------------------------
# Grass tufts test
#     Tufts fill open grass in blocks, keep off roads and buildings,
#     are rebuilt when the ground changes, and stay within a sensible
#     count (the frame rate budget).
#     godot --headless --path . --fixed-fps 60 res://tests/grass.tscn
# ----------------------------------------------------------------
extends Node;

var world:World;
var grass:GrassDetail;
var _frame:int = 0;
var _road:Vector2i;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    for child in world.get_children():
        if child is GrassDetail:
            grass = child;
    _expect("the world has grass", grass != null);

func _count() -> int:
    var n:int = 0;
    for mmi in grass._blocks.values():
        n += (mmi as MultiMeshInstance3D).multimesh.instance_count;
    return n;

func _process(_delta:float) -> void:
    _frame += 1;
    if _frame == 30:
        var total:int = _count();
        _expect("every block was built (%d blocks)" % grass._blocks.size(), grass._blocks.size() == (Terrain.SIZE / GrassDetail.BLOCK) * (Terrain.SIZE / GrassDetail.BLOCK) and grass._dirty.is_empty());
        _expect("a sensible number of tufts (%d)" % total, total > 5000 and total < 80000);
        var mmi:MultiMeshInstance3D = grass._blocks.values()[0];
        _expect("blocks are only drawn near the camera", mmi.visibility_range_end > 0.0 and mmi.visibility_range_end < 100.0);
        # find a grassy cell with tufts and turn it into a road
        var found:bool = false;
        for z in range(40, 90):
            for x in range(40, 90):
                var cell:Vector2i = Vector2i(x, z);
                if not found and grass._grassy(cell) and world.can_plan_road(cell) and world.node_at[world.idx(cell)] == null and grass.tufts_in_cell(cell) > 0:
                    _road = cell;
                    found = true;
        _expect("found a cell with grass to pave", found);
        world.set_road(_road, true);
    elif _frame == 50:
        _expect("a road cell has no tufts after the rebuild", grass.tufts_in_cell(_road) == 0);
        var bld:Building = world.town_hall;
        var cell:Vector2i = bld.origin + Vector2i(1, 1);
        _expect("nor does a building", grass.tufts_in_cell(cell) == 0);
        _expect("a new road gets its stones too", world.get_children().any(func(n:Node) -> bool: return n is RoadDetail and (n as RoadDetail)._mmi.multimesh.instance_count > 0));
        get_tree().quit();

func _expect(what:String, ok:bool) -> void:
    print(("PASS " if ok else "FAIL ") + what);
