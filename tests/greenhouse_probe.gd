# ----------------------------------------------------------------
# Greenhouse probe (not pass/fail): how far the herbalist's meshes reach
# past its footprint, without and with the herb greenhouse, per facing.
#     godot --headless --path . --fixed-fps 60 res://tests/greenhouse_probe.tscn
# ----------------------------------------------------------------
extends Node;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    for facing in 4:
        for green in [false, true]:
            var def:Dictionary = Defs.BUILDINGS[&"herbalist"];
            var b:Herbalist = Herbalist.new();
            b.facing = facing;
            b.setup(world, &"herbalist", Vector2i(10, 10), def["size"]);
            b.state = Building.State.COMPLETE;
            if green:
                b.upgrades_done[&"greenhouse"] = true;
            b._update_visual();
            world.add_child(b);
            if green:
                b.on_upgrade_done(&"greenhouse");
            print("facing %d greenhouse %s  size %s vsize %s scale %s shift %s  overflow %s" % [facing, green, b.size, b.vsize, b.scale, b.fit_shift, _overflow(b)]);
            b.queue_free();
    get_tree().quit();

func _overflow(b:Building) -> Dictionary:
    var half:Vector2 = Vector2(b.size) * 0.5;
    var lo:Vector2 = Vector2(INF, INF);
    var hi:Vector2 = Vector2(-INF, -INF);
    for mi in b.find_children("*", "MeshInstance3D", true, false):
        if mi.mesh == null or not mi.visible:
            continue;
        var box:AABB = (mi as MeshInstance3D).mesh.get_aabb();
        var tf:Transform3D = b.global_transform.affine_inverse() * mi.global_transform;
        for cx in [0, 1]:
            for cy in [0, 1]:
                for cz in [0, 1]:
                    var corner:Vector3 = box.position + box.size * Vector3(cx, cy, cz);
                    var p:Vector3 = b.global_transform.basis * (tf * corner) + b.fit_shift;
                    lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z));
                    hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z));
    return {"left": snappedf(maxf(0.0, -half.x - lo.x), 0.01), "right": snappedf(maxf(0.0, hi.x - half.x), 0.01), "back": snappedf(maxf(0.0, -half.y - lo.y), 0.01), "front": snappedf(maxf(0.0, hi.y - half.y), 0.01)};
