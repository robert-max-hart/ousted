# ----------------------------------------------------------------
# BuildingVisuals
#     Makes a building's look when it is created: the body, roof and
#     decor of its shape, the door and chimney of a house, a bridge
#     deck, and the scaling that keeps everything inside the
#     footprint. It fills in the building's own mesh fields; Building
#     keeps the updates (progress, windows, smoke).
# ----------------------------------------------------------------
class_name BuildingVisuals extends RefCounted;

static func _build_visual(b:Building) -> void:
    var shape:String = b.def.get("shape", "house");
    var h:float = b.def.get("height", 2.0);
    b._body_mat = SurfaceTextures.material(b.def.get("wall", &"planks"), b.def.get("color", Color.GRAY));
    b._body_h = h;
    match shape:
        "silo":
            BuildingShapes.silo(b);
        "market":
            BuildingShapes.market(b);
        "hall":
            BuildingShapes.hall(b);
            if b.def.has("fuel_capacity"):
                BuildingVisuals._build_chimney(b, h);
        "house":
            var box:BoxMesh = BoxMesh.new();
            box.size = Vector3(b.vsize.x - 0.5, h, b.vsize.y - 0.5);
            b._body = b._add_mesh(box, b._body_mat, Vector3(0, h * 0.5, 0));
            var pitch:float = b.def.get("roof_pitch", 0.55);
            var prism:PrismMesh = PrismMesh.new();
            prism.size = Vector3(b.vsize.x - 0.1, h * pitch, b.vsize.y - 0.2);
            b._roof = b._add_mesh(prism, SurfaceTextures.material(&"shingle", b.def.get("roof", Color.DARK_RED)), Vector3(0, h + h * pitch * 0.5, 0));
            BuildingVisuals._build_door(b, Vector2(b.vsize.x - 0.5, b.vsize.y - 0.5), h);
            if b.def.has("fuel_capacity"):
                BuildingVisuals._build_chimney(b, h);
        "well":
            var cyl:CylinderMesh = CylinderMesh.new();
            cyl.top_radius = 0.7;
            cyl.bottom_radius = 0.75;
            cyl.height = h;
            b._body = b._add_mesh(cyl, b._body_mat, Vector3(0, h * 0.5, 0));
            var cap:PrismMesh = PrismMesh.new();
            cap.size = Vector3(1.6, 0.5, 1.2);
            b._roof = b._add_mesh(cap, b._flat_mat(b.def.get("roof", Color.BROWN)), Vector3(0, h + 0.9, 0));
        "mine":
            var pit:BoxMesh = BoxMesh.new();
            pit.size = Vector3(b.vsize.x - 0.3, 0.2, b.vsize.y - 0.3);
            b._add_mesh(pit, b._flat_mat(Color(0.32, 0.28, 0.25)), Vector3(0, 0.1, 0));
            var shed:BoxMesh = BoxMesh.new();
            shed.size = Vector3(b.vsize.x * 0.5, h, b.vsize.y * 0.4);
            b._body = b._add_mesh(shed, b._body_mat, Vector3(-b.vsize.x * 0.2, h * 0.5, -b.vsize.y * 0.25));
            var cap:PrismMesh = PrismMesh.new();
            cap.size = Vector3(b.vsize.x * 0.55, h * 0.4, b.vsize.y * 0.45);
            b._roof = b._add_mesh(cap, SurfaceTextures.material(&"shingle", b.def.get("roof", Color.BROWN)), Vector3(-b.vsize.x * 0.2, h + h * 0.2, -b.vsize.y * 0.25));
            BuildingShapes.mine_extras(b);
        "graveyard":
            b._fence = Fence.new(b, &"stone", 1);       # the ground itself is a terrain overlay (Terrain.Overlay.GRAVE)
            b.add_child(b._fence);
        "cart":
            var bed:BoxMesh = BoxMesh.new();
            bed.size = Vector3(b.vsize.x - 0.3, h * 0.5, b.vsize.y * 0.8);
            b._body = b._add_mesh(bed, b._body_mat, Vector3(0, h * 0.55, 0));
            var load_mesh:BoxMesh = BoxMesh.new();
            load_mesh.size = Vector3(b.vsize.x - 0.7, h * 0.35, b.vsize.y * 0.55);
            b._roof = b._add_mesh(load_mesh, b._flat_mat(Color(0.75, 0.65, 0.4)), Vector3(0, h * 0.95, 0));
            var wheel:CylinderMesh = CylinderMesh.new();
            wheel.top_radius = 0.28;
            wheel.bottom_radius = 0.28;
            wheel.height = 0.1;
            for sx in [-0.55, 0.55]:
                var w:MeshInstance3D = b._add_mesh(wheel, b._flat_mat(Color(0.25, 0.18, 0.12)), Vector3(sx, 0.28, b.vsize.y * 0.42));
                w.rotation.z = PI * 0.5;
        "fishing":
            BuildingShapes.fishing(b);
        "bridge":
            BuildingVisuals._build_bridge(b, h);
        "pile":
            var pad:BoxMesh = BoxMesh.new();
            pad.size = Vector3(b.vsize.x - 0.3, h, b.vsize.y - 0.3);
            b._body = b._add_mesh(pad, b._body_mat, Vector3(0, h * 0.5, 0));
            b._fence = Fence.new(b, &"rope", 2);
            b.add_child(b._fence);
            b.add_child(PileGoods.new(b));
        _:
            pass;
    if b.def.has("decor"):
        BuildingShapes.decorate(b, b.def["decor"]);
    if not b.def.get("drag_size", false):
        BuildingVisuals._fit_to_footprint(b);

static func _fit_to_footprint(b:Building) -> void:
    var lo:Vector2 = Vector2(INF, INF);
    var hi:Vector2 = Vector2(-INF, -INF);
    for mi in b.find_children("*", "MeshInstance3D", true, false):
        var m:MeshInstance3D = mi;
        if m.mesh == null or m.get_parent() is Fence or m.get_parent() is PileGoods:
            continue;
        var tf:Transform3D = m.transform;
        var up:Node = m.get_parent();
        while up != b and up is Node3D:
            tf = (up as Node3D).transform * tf;
            up = up.get_parent();
        var box:AABB = m.mesh.get_aabb();
        for cx in [0, 1]:
            for cy in [0, 1]:
                for cz in [0, 1]:
                    var p:Vector3 = tf * (box.position + box.size * Vector3(cx, cy, cz));
                    lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z));
                    hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z));
    if lo.x == INF:
        return;
    var half:Vector2 = Vector2(b.vsize) * 0.5 - Vector2(b.FIT_MARGIN, b.FIT_MARGIN);
    if lo.x >= -half.x and hi.x <= half.x and lo.y >= -half.y and hi.y <= half.y:
        return;
    var fit:float = minf(1.0, minf(2.0 * half.x / maxf(0.01, hi.x - lo.x), 2.0 * half.y / maxf(0.01, hi.y - lo.y)));
    var mid:Vector2 = (lo + hi) * 0.5;
    b.scale = Vector3(fit, 1.0, fit);
    b.fit_shift = Vector3(-mid.x * fit, 0.0, -mid.y * fit).rotated(Vector3.UP, b.rotation.y);
    b.position += b.fit_shift;

# A plank deck with a low rail along each long side, standing on posts down to the water.
static func _build_bridge(b:Building, h:float) -> void:
    var deck:BoxMesh = BoxMesh.new();
    deck.size = Vector3(b.vsize.x, h, b.vsize.y);
    var top:float = b.DECK_HEIGHT;
    b._body = b._add_mesh(deck, b._body_mat, Vector3(0, top - h * 0.5, 0));
    b._body_y0 = top - h;
    b._body_h = h;
    var along_x:bool = b.vsize.x >= b.vsize.y;
    var rail_mat:StandardMaterial3D = b._flat_mat(Color(0.36, 0.26, 0.16));
    var post:BoxMesh = BoxMesh.new();
    post.size = Vector3(0.14, 0.5, 0.14);
    var rail:BoxMesh = BoxMesh.new();
    rail.size = Vector3(b.vsize.x if along_x else 0.08, 0.07, 0.08 if along_x else b.vsize.y);
    for side in [-1.0, 1.0]:
        var off:float = (b.vsize.y if along_x else b.vsize.x) * 0.5 - 0.08;
        b.add_decor(rail, rail_mat, Vector3(0.0 if along_x else side * off, top + 0.42, side * off if along_x else 0.0));
        var length:float = b.vsize.x if along_x else b.vsize.y;
        var n:int = maxi(2, int(length / 2.0) + 1);
        for k in n:
            var along:float = lerpf(-length * 0.5 + 0.1, length * 0.5 - 0.1, float(k) / float(n - 1));
            b.add_decor(post, rail_mat, Vector3(along if along_x else side * off, top + 0.25, side * off if along_x else along));

# A dark door on the south face of a house-shaped body, and for homes a pair of windows that light up while
# someone lives there. (Decoration only: citizens still walk to the building's edge.)
static func _build_door(b:Building, body:Vector2, h:float) -> void:
    var door_h:float = minf(1.3, h * 0.65);
    var door:BoxMesh = BoxMesh.new();
    door.size = Vector3(minf(0.8, body.x * 0.3), door_h, 0.1);
    b._door = b._add_mesh(door, b._flat_mat(Color(0.27, 0.17, 0.1)), Vector3(0, door_h * 0.5, body.y * 0.5 + 0.02));
    if not b.def.has("beds") or body.x < 1.9:
        return;
    b._window_mat = StandardMaterial3D.new();
    b._window_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED;
    var pane:BoxMesh = BoxMesh.new();
    pane.size = Vector3(0.42, 0.42, 0.08);
    for sx in [-1.0, 1.0]:
        var w:MeshInstance3D = b._add_mesh(pane, b._window_mat, Vector3(sx * (body.x * 0.5 - 0.5), h * 0.62, body.y * 0.5 + 0.02));
        w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
        b._windows.append(w);
    b.update_windows();

static func _build_chimney(b:Building, h:float) -> void:
    var box:BoxMesh = BoxMesh.new();
    var pitch:float = b.def.get("roof_pitch", 0.55);
    var top:float = h + h * pitch + 0.35;
    var base:float = h + h * pitch * 0.5;
    box.size = Vector3(0.4, top - base, 0.4);
    b._chimney = b._add_mesh(box, b._flat_mat(Color(0.45, 0.32, 0.28)), Vector3(b.vsize.x * 0.22, (top + base) * 0.5, b.vsize.y * 0.15));
    b._smoke = CPUParticles3D.new();
    var puff:SphereMesh = SphereMesh.new();
    puff.radius = 0.32;
    puff.height = 0.64;
    puff.radial_segments = 6;
    puff.rings = 3;
    var mat:StandardMaterial3D = StandardMaterial3D.new();
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA;
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED;
    mat.albedo_color = Color(0.7, 0.7, 0.72, 0.75);
    puff.material = mat;
    b._smoke.mesh = puff;
    b._smoke.amount = 14;
    b._smoke.lifetime = 4.0;
    b._smoke.direction = Vector3.UP;
    b._smoke.spread = 12.0;
    b._smoke.initial_velocity_min = 0.6;
    b._smoke.initial_velocity_max = 0.9;
    b._smoke.gravity = Vector3(0.25, 0.0, 0.0);       # a light breeze
    b._smoke.scale_amount_min = 0.7;
    b._smoke.scale_amount_max = 1.1;
    var grow:Curve = Curve.new();
    grow.add_point(Vector2(0.0, 0.5));
    grow.add_point(Vector2(1.0, 2.2));
    b._smoke.scale_amount_curve = grow;
    var fade:Gradient = Gradient.new();
    fade.set_color(0, Color(1, 1, 1, 1));
    fade.set_color(1, Color(1, 1, 1, 0));
    b._smoke.color_ramp = fade;
    b._smoke.emitting = false;
    b._smoke.speed_scale = World.fx_speed();
    GameClock.speed_changed.connect(b._on_clock_speed);
    b._smoke.position = b._chimney.position + Vector3(0, box.size.y * 0.5, 0);
    b._smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
    b.add_child(b._smoke);
