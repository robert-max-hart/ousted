# ----------------------------------------------------------------
# PlayerTools
#     Turns mouse/keyboard input into world actions: selecting,
#     placing buildings, painting roads, marking harvests, demolishing
#     and terraforming. Draws the placement ghosts.
# ----------------------------------------------------------------
class_name PlayerTools extends Node3D;

signal mode_changed(mode:int);
signal selection_changed(obj:Variant);

enum Mode { SELECT, BUILD, HARVEST, ROAD, DEMOLISH, RAISE, LOWER, FLATTEN };

const MODE_HINTS:Dictionary = {
    Mode.SELECT:   "Click a citizen, building or resource to inspect it.",
    Mode.BUILD:    "Click to place. R rotates. Right-click to stop building.",
    Mode.HARVEST:  "Drag over trees and rocks to mark them for harvest.",
    Mode.ROAD:     "Drag to lay a road. Roads speed up walking.",
    Mode.DEMOLISH: "Drag to remove buildings and roads and to cancel harvest marks.",
    Mode.RAISE:    "Hold the left mouse button to raise the ground.",
    Mode.LOWER:    "Hold the left mouse button to lower the ground.",
    Mode.FLATTEN:  "Hold the left mouse button to level the ground to where you clicked.",
};
const BRUSH_RADIUS  :float = 2.5;
const BRUSH_RATE    :float = 3.0;      # metres per second
const PICK_PIXELS   :float = 22.0;

var mode        :int = Mode.SELECT;
var build_id    :StringName = &"";
var build_size  :Vector2i = Vector2i.ONE;
var selected    :Variant = null;
var hint        :String = MODE_HINTS[Mode.SELECT];
var error       :String = "";

var _hover_ok   :bool = false;
var _hover_pt   :Vector3;
var _hover_cell :Vector2i;
var _dragging   :bool = false;
var _drag_start :Vector2i;
var _brushing   :bool = false;
var _flatten_h  :float = 0.0;

var _ghosts     :Array[MeshInstance3D] = [];
var _mat_ok     :StandardMaterial3D;
var _mat_bad    :StandardMaterial3D;
var _mat_area   :StandardMaterial3D;
var _ring       :MeshInstance3D;

func _ready() -> void:
    _mat_ok = _ghost_material(Color(0.3, 0.9, 0.4, 0.4));
    _mat_bad = _ghost_material(Color(0.95, 0.25, 0.2, 0.4));
    _mat_area = _ghost_material(Color(1.0, 0.8, 0.3, 0.3));
    for i in 2:
        var g:MeshInstance3D = MeshInstance3D.new();
        g.mesh = BoxMesh.new();
        g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
        g.visible = false;
        add_child(g);
        _ghosts.append(g);
    _ring = MeshInstance3D.new();
    var torus:TorusMesh = TorusMesh.new();
    torus.inner_radius = 0.45;
    torus.outer_radius = 0.6;
    _ring.mesh = torus;
    _ring.material_override = _ghost_material(Color(1.0, 0.95, 0.5, 0.9));
    _ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
    _ring.visible = false;
    add_child(_ring);

func set_mode(m:int, id:StringName = &"") -> void:
    mode = m;
    build_id = id;
    if m == Mode.BUILD:
        build_size = Defs.BUILDINGS[id]["size"];
        hint = "%s (%s). %s" % [Defs.BUILDINGS[id]["name"], Defs.cost_string(Defs.BUILDINGS[id]["cost"]), MODE_HINTS[m]];
    else:
        hint = MODE_HINTS[m];
    error = "";
    _dragging = false;
    _brushing = false;
    mode_changed.emit(mode);

func select(obj:Variant) -> void:
    selected = obj;
    selection_changed.emit(obj);

# --------------------------------
# Input

func _unhandled_input(event:InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        match (event as InputEventKey).keycode:
            KEY_SPACE:
                GameClock.toggle_pause();
            KEY_1:
                GameClock.set_speed(1);
            KEY_2:
                GameClock.set_speed(2);
            KEY_3:
                GameClock.set_speed(3);
            KEY_R:
                build_size = Vector2i(build_size.y, build_size.x);
            KEY_ESCAPE:
                _cancel();
        return;
    if not (event is InputEventMouseButton):
        return;
    var mb:InputEventMouseButton = event;
    if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
        _cancel();
    elif mb.button_index == MOUSE_BUTTON_LEFT:
        _update_hover();
        if mb.pressed:
            _on_press();
        else:
            _on_release();

func _cancel() -> void:
    if mode != Mode.SELECT:
        set_mode(Mode.SELECT);
    else:
        select(null);

func _on_press() -> void:
    if not _hover_ok:
        return;
    match mode:
        Mode.SELECT:
            select(_pick());
        Mode.BUILD:
            var origin:Vector2i = _build_origin();
            error = World.instance.can_place(build_id, origin, build_size);
            if error == "":
                World.instance.place_building(build_id, origin, build_size);
        Mode.HARVEST, Mode.ROAD, Mode.DEMOLISH:
            _dragging = true;
            _drag_start = _hover_cell;
        Mode.RAISE, Mode.LOWER, Mode.FLATTEN:
            _brushing = true;
            _flatten_h = _hover_pt.y;

func _on_release() -> void:
    _brushing = false;
    if not _dragging:
        return;
    _dragging = false;
    var w:World = World.instance;
    match mode:
        Mode.HARVEST:
            var n:int = 0;
            for rn in w.nodes:
                if _drag_rect().has_point(rn.cell) and not rn.is_auto() and not rn.designated:
                    w.set_designated(rn, true);
                    n += 1;
            error = "" if n > 0 else "No trees or rocks there.";
        Mode.ROAD:
            for c in _road_cells():
                w.set_road(c, true);
        Mode.DEMOLISH:
            var r:Rect2i = _drag_rect();
            for b in w.buildings.duplicate():
                if b.rect().intersects(r):
                    w.remove_building(b, true);
            for z in range(r.position.y, r.end.y):
                for x in range(r.position.x, r.end.x):
                    w.set_road(Vector2i(x, z), false);
            for rn in w.nodes:
                if r.has_point(rn.cell) and w.occupant[w.idx(rn.cell)] == null:
                    w.set_designated(rn, false);

# --------------------------------
# Per-frame

func _process(delta:float) -> void:
    _update_hover();
    if _brushing and _hover_ok:
        var w:World = World.instance;
        var amount:float = BRUSH_RATE * delta;
        var locked:Callable = w.is_corner_locked;
        match mode:
            Mode.RAISE:
                w.terrain.apply_brush(_hover_pt, BRUSH_RADIUS, amount, NAN, locked);
            Mode.LOWER:
                w.terrain.apply_brush(_hover_pt, BRUSH_RADIUS, -amount, NAN, locked);
            Mode.FLATTEN:
                w.terrain.apply_brush(_hover_pt, BRUSH_RADIUS, amount, _flatten_h, locked);
    _update_ghosts();
    _update_ring();

func _update_hover() -> void:
    var cam:Camera3D = get_viewport().get_camera_3d();
    if cam == null:
        _hover_ok = false;
        return;
    var mp:Vector2 = get_viewport().get_mouse_position();
    var hit:Variant = World.instance.terrain.raycast(cam.project_ray_origin(mp), cam.project_ray_normal(mp));
    _hover_ok = hit != null;
    if _hover_ok:
        _hover_pt = hit;
        _hover_cell = World.instance.terrain.world_to_cell(_hover_pt);

func _build_origin() -> Vector2i:
    # center the footprint on the cursor
    return Vector2i(roundi(_hover_pt.x - build_size.x * 0.5), roundi(_hover_pt.z - build_size.y * 0.5));

func _drag_rect() -> Rect2i:
    var a:Vector2i = _drag_start;
    var b:Vector2i = _hover_cell;
    var lo:Vector2i = Vector2i(mini(a.x, b.x), mini(a.y, b.y));
    var hi:Vector2i = Vector2i(maxi(a.x, b.x), maxi(a.y, b.y));
    return Rect2i(lo, hi - lo + Vector2i.ONE);

# L-shaped path: along x first, then along z.
func _road_cells() -> Array[Vector2i]:
    var out:Array[Vector2i] = [];
    var a:Vector2i = _drag_start;
    var b:Vector2i = _hover_cell;
    var sx:int = 1 if b.x >= a.x else -1;
    for x in range(a.x, b.x + sx, sx):
        out.append(Vector2i(x, a.y));
    var sz:int = 1 if b.y >= a.y else -1;
    for z in range(a.y + sz, b.y + sz, sz):
        out.append(Vector2i(b.x, z));
    return out;

# Pawns win over the ground under them, picked in screen space.
func _pick() -> Variant:
    var w:World = World.instance;
    var cam:Camera3D = get_viewport().get_camera_3d();
    var mp:Vector2 = get_viewport().get_mouse_position();
    var best:Pawn = null;
    var best_d:float = PICK_PIXELS;
    for p in w.pawns:
        if not p.visible:
            continue;
        var at:Vector3 = p.position + Vector3(0, 0.7, 0);
        if cam.is_position_behind(at):
            continue;
        var d:float = cam.unproject_position(at).distance_to(mp);
        if d < best_d:
            best = p;
            best_d = d;
    if best != null:
        return best;
    if not w.terrain.in_bounds(_hover_cell):
        return null;
    var i:int = w.idx(_hover_cell);
    if w.occupant[i] != null:
        return w.occupant[i];
    return w.node_at[i];

# --------------------------------
# Visuals

func _update_ghosts() -> void:
    for g in _ghosts:
        g.visible = false;
    if not _hover_ok:
        return;
    var w:World = World.instance;
    match mode:
        Mode.BUILD:
            var origin:Vector2i = _build_origin();
            var ok:bool = w.can_place(build_id, origin, build_size) == "";
            var h:float = maxf(0.3, Defs.BUILDINGS[build_id]["height"]);
            _show_box(0, Rect2i(origin, build_size), h, _mat_ok if ok else _mat_bad);
        Mode.HARVEST, Mode.DEMOLISH:
            var r:Rect2i = _drag_rect() if _dragging else Rect2i(_hover_cell, Vector2i.ONE);
            _show_box(0, r, 0.4, _mat_area if mode == Mode.HARVEST else _mat_bad);
        Mode.ROAD:
            if _dragging:
                var cells:Array[Vector2i] = _road_cells();
                var a:Vector2i = _drag_start;
                var b:Vector2i = _hover_cell;
                _show_box(0, Rect2i(Vector2i(mini(a.x, b.x), a.y), Vector2i(absi(b.x - a.x) + 1, 1)), 0.2, _mat_ok);
                if cells.size() > absi(b.x - a.x) + 1:
                    _show_box(1, Rect2i(Vector2i(b.x, mini(a.y, b.y)), Vector2i(1, absi(b.y - a.y) + 1)), 0.2, _mat_ok);
            else:
                _show_box(0, Rect2i(_hover_cell, Vector2i.ONE), 0.2, _mat_ok);
        Mode.RAISE, Mode.LOWER, Mode.FLATTEN:
            var rr:int = ceili(BRUSH_RADIUS);
            _show_box(0, Rect2i(_hover_cell - Vector2i(rr, rr) + Vector2i.ONE, Vector2i(rr * 2 - 1, rr * 2 - 1)), 0.3, _mat_area);

func _show_box(i:int, r:Rect2i, height:float, mat:Material) -> void:
    var t:Terrain = World.instance.terrain;
    var clipped:Rect2i = r.intersection(Rect2i(0, 0, Terrain.SIZE, Terrain.SIZE));
    var hr:Vector2 = t.rect_height_range(clipped) if clipped.has_area() else Vector2.ZERO;
    var g:MeshInstance3D = _ghosts[i];
    var box:BoxMesh = g.mesh;
    box.size = Vector3(r.size.x, hr.y - hr.x + height, r.size.y);
    g.position = Vector3(r.position.x + r.size.x * 0.5, (hr.x + hr.y + height) * 0.5, r.position.y + r.size.y * 0.5);
    g.material_override = mat;
    g.visible = true;

func _update_ring() -> void:
    if selected != null and not World.alive(selected):
        select(null);
    _ring.visible = selected != null;
    if selected is Pawn:
        _ring.visible = (selected as Pawn).visible;
        _ring.scale = Vector3.ONE;
        _ring.position = (selected as Pawn).position + Vector3(0, 0.05, 0);
    elif selected is Building:
        var b:Building = selected;
        var c:Vector2 = Vector2(b.origin) + Vector2(b.size) * 0.5;
        _ring.scale = Vector3.ONE * maxf(b.size.x, b.size.y) * 0.85;
        _ring.position = Vector3(c.x, World.instance.terrain.height_at(c.x, c.y) + 0.1, c.y);
    elif selected is ResourceNode:
        var rn:ResourceNode = selected;
        _ring.scale = Vector3.ONE * 1.2;
        _ring.position = World.instance.terrain.cell_center(rn.cell) + Vector3(0, 0.05, 0);

func _ghost_material(c:Color) -> StandardMaterial3D:
    var m:StandardMaterial3D = StandardMaterial3D.new();
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED;
    m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA;
    m.albedo_color = c;
    m.cull_mode = BaseMaterial3D.CULL_DISABLED;
    return m;
