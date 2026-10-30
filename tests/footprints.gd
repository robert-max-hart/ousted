# ----------------------------------------------------------------
# Footprints
#     Builds every ordinary building (not the drag-sized ones) and checks
#     that its meshes stay inside its footprint, so a road or another
#     building next to it is never overlapped by an anvil, a rack or a
#     stoop. Prints each overflow in cells and fails if any is over
#     TOLERANCE.
#     godot --headless --path . --fixed-fps 60 res://tests/footprints.tscn
# ----------------------------------------------------------------
extends Node;

const TOLERANCE:float = 0.06;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    var bad:int = 0;
    for id in Defs.BUILD_MENU:
        var def:Dictionary = Defs.BUILDINGS[id];
        if def.get("drag_size", false) or def.get("bridge", false):
            continue;
        for facing in [0, 1]:
            var b:Building = Building.new();
            b.facing = facing;
            b.setup(world, id, Vector2i(10, 10), def["size"]);
            b.state = Building.State.COMPLETE;
            b._update_visual();
            world.add_child(b);
            var over:Dictionary = _overflow(b);
            var worst:float = 0.0;
            for k in over:
                worst = maxf(worst, over[k]);
            if worst > TOLERANCE:
                bad += 1;
                print("OVER %-12s facing %d  %s" % [id, facing, ", ".join(over.keys().filter(func(k:String) -> bool: return over[k] > TOLERANCE).map(func(k:String) -> String: return "%s +%.2f" % [k, over[k]]))]);
            b.queue_free();
    print("FOOTPRINTS %s (%d outside)" % ["PASS" if bad == 0 else "FAIL", bad]);
    get_tree().quit(1 if bad > 0 else 0);

# How far (cells) the building's meshes reach past each side of its footprint, in its own frame (front is +z).
func _overflow(b:Building) -> Dictionary:
    var half:Vector2 = Vector2(b.size) * 0.5;       # the footprint in the world frame, centred on the building
    var lo:Vector2 = Vector2(INF, INF);
    var hi:Vector2 = Vector2(-INF, -INF);
    for mi in b.find_children("*", "MeshInstance3D", true, false):
        if mi.mesh == null or not mi.visible or mi.get_parent() is Fence or mi.get_parent() is PileGoods:
            continue;
        var box:AABB = (mi as MeshInstance3D).mesh.get_aabb();
        var tf:Transform3D = b.global_transform.affine_inverse() * mi.global_transform;
        # corners in the building's frame, then rotated back to the world frame (the footprint is axis-aligned there)
        for cx in [0, 1]:
            for cy in [0, 1]:
                for cz in [0, 1]:
                    var corner:Vector3 = box.position + box.size * Vector3(cx, cy, cz);
                    var p:Vector3 = b.global_transform.basis * (tf * corner) + b.fit_shift;       # world frame offset from the footprint's centre (the building may sit shifted off it, see Building.fit_shift)
                    lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z));
                    hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z));
    return {"left": maxf(0.0, -half.x - lo.x), "right": maxf(0.0, hi.x - half.x), "back": maxf(0.0, -half.y - lo.y), "front": maxf(0.0, hi.y - half.y)};
