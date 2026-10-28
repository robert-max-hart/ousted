# ----------------------------------------------------------------
# PlayerTools
#     Turns mouse/keyboard input into world actions: selecting,
#     placing buildings, painting roads, marking harvests, demolishing
#     and terraforming. Draws the placement ghosts.
# ----------------------------------------------------------------
class_name PlayerTools extends Node3D;

signal mode_changed(mode:int);
signal selection_changed(obj:Variant);

enum Mode { SELECT, BUILD, HARVEST, ROAD, DEMOLISH, RAISE, LOWER, FLATTEN, FORAGE, CANCEL, EXPAND };

const MODE_HINTS:Dictionary = {
    Mode.SELECT:   "Click a citizen, building or resource to inspect it.",
    Mode.BUILD:    "Click to place. R rotates. Right-click to stop building.",
    Mode.HARVEST:  "Drag over trees and rocks to mark them for harvest.",
    Mode.FORAGE:   "Drag over berries, mushrooms and hazel groves to mark them for picking. Foragers and idle laborers pick marked ones when they are in season.",
    Mode.ROAD:     "Drag to lay a road. Roads speed up walking and take work, no materials. Trees and rocks in the way are marked for clearing first.",
    Mode.DEMOLISH: "Drag to demolish buildings and roads.",
    Mode.EXPAND:   "Click on the ground beside it to grow it there. Right-click to stop.",
    Mode.CANCEL:   "Drag to cancel what is still planned: buildings not yet built (materials come back in full), harvest and forage marks, and roads waiting to be laid.",
    Mode.RAISE:    "Hold the left mouse button to raise the ground.",
    Mode.LOWER:    "Hold the left mouse button to lower the ground.",
    Mode.FLATTEN:  "Hold the left mouse button to level the ground to where you clicked.",
};
const BRUSH_RADIUS  :float = 2.5;
const BRUSH_RATE    :float = 3.0;      # metres per second
const PICK_PIXELS   :float = 22.0;
const FIELD_MAX_SIDE:int = 16;

var mode        :int = Mode.SELECT;
var build_id    :StringName = &"";
var build_size  :Vector2i = Vector2i.ONE;
var selected    :Variant = null;
var expanding   :Building = null;      # the field, stockpile or graveyard being grown (Mode.EXPAND)
var relocating  :Building = null;     # while placing a moved building: the one being moved
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
var _radius_line:MeshInstance3D;
var _radius_key :String = "";
var _mat_ok     :StandardMaterial3D;
var _mat_bad    :StandardMaterial3D;
var _mat_area   :StandardMaterial3D;
var _model_ghost:BuildGhost;                       # the real shape of the building being placed, tinted
var _mat_m_ok   :StandardMaterial3D;
var _mat_m_short:StandardMaterial3D;
var _mat_m_bad  :StandardMaterial3D;
var _ring       :MeshInstance3D;
var _frame      :Array[MeshInstance3D] = [];       # four bars outlining a selected building's footprint

func _ready() -> void:
    _mat_ok = _ghost_material(Color(0.3, 0.9, 0.4, 0.4));
    _mat_bad = _ghost_material(Color(0.95, 0.25, 0.2, 0.4));
    _mat_area = _ghost_material(Color(1.0, 0.8, 0.3, 0.3));
    _mat_m_ok = _model_material(Color(0.4, 1.0, 0.5, 0.55));
    _mat_m_short = _model_material(Color(1.0, 0.7, 0.2, 0.55));
    _mat_m_bad = _model_material(Color(1.0, 0.3, 0.25, 0.55));
    _model_ghost = BuildGhost.new();
    _model_ghost.visible = false;
    add_child(_model_ghost);
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
    torus.inner_radius = 0.5;
    torus.outer_radius = 0.58;
    var frame_mat:StandardMaterial3D = _ghost_material(Color(1.0, 0.95, 0.5, 0.8));
    _ring.material_override = frame_mat;
    for i in 4:
        var bar:MeshInstance3D = MeshInstance3D.new();
        bar.mesh = BoxMesh.new();
        bar.material_override = frame_mat;
        bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
        bar.visible = false;
        add_child(bar);
        _frame.append(bar);
    _ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
    _ring.visible = false;
    add_child(_ring);
    _radius_line = MeshInstance3D.new();
    _radius_line.mesh = ImmediateMesh.new();
    var lm:StandardMaterial3D = StandardMaterial3D.new();
    lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED;
    lm.albedo_color = Color(1.0, 0.95, 0.5, 0.95);
    lm.no_depth_test = true;
    _radius_line.material_override = lm;
    _radius_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
    _radius_line.visible = false;
    add_child(_radius_line);

func set_mode(m:int, id:StringName = &"") -> void:
    mode = m;
    build_id = id;
    relocating = null;
    expanding = null;
    if m == Mode.BUILD:
        build_size = Defs.BUILDINGS[id]["size"];
        if _is_field_mode():
            build_size = Vector2i(_min_side(), _min_side());       # a click places the smallest size; drag to make it bigger
        hint = "%s (%s). %s" % [Defs.BUILDINGS[id]["name"], Defs.cost_string(Defs.BUILDINGS[id]["cost"]), MODE_HINTS[m]];
        if _is_field_mode():
            hint = "%s. Click for the smallest size (%dx%d), or press and drag to size it (up to %d cells a side)." % [
                Defs.BUILDINGS[id]["name"], _min_side(), _min_side(), FIELD_MAX_SIDE];
    else:
        hint = MODE_HINTS[m];
    error = "";
    _dragging = false;
    _brushing = false;
    mode_changed.emit(mode);

# Grows a finished field, stockpile or graveyard: click the ground beside it and it stretches to take in that cell.
func start_expand(b:Building) -> void:
    if not b.is_complete() or not b.def.get("drag_size", false):
        return;
    set_mode(Mode.EXPAND);
    expanding = b;
    hint = "Expanding the %s. Click the ground beside it to grow it there (up to %d cells a side). Right-click to stop." % [b.display_name().to_lower(), FIELD_MAX_SIDE];

# Picks a new spot for an existing building (see World.relocate): same footprint, a share of the cost.
func start_relocate(b:Building) -> void:
    if World.instance.relocation_block_reason(b) != "":
        return;
    set_mode(Mode.BUILD, b.def_id);
    relocating = b;
    build_size = b.size;
    hint = "Moving the %s (costs %s). Click the new spot. R rotates. Right-click to cancel." % [b.display_name(), Defs.cost_string(_relocation_cost(b))];

func _relocation_cost(b:Building) -> Dictionary:
    var c:Dictionary = {};
    for item in b.def["cost"]:
        c[item] = maxi(1, ceili(b.def["cost"][item] * Defs.RELOCATE_COST_MULT));
    return c;

func select(obj:Variant) -> void:
    var before:Variant = selected;
    selected = obj;
    for o in [before, obj]:
        if World.alive(o) and o is Building:
            (o as Building).update_site_label();       # a site spells out what it is missing only while selected
    selection_changed.emit(obj);

# --------------------------------
# Input

func _unhandled_input(event:InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        var hud:HUD = World.instance.hud;
        if (event as InputEventKey).keycode == KEY_ESCAPE and (hud.menu_open() or (mode == Mode.SELECT and selected == null)):
            hud.toggle_menu();       # nothing to cancel: Esc opens or closes the menu
            return;
        if hud.menu_open():
            return;
        match (event as InputEventKey).keycode:
            KEY_SPACE:
                GameClock.toggle_pause();
            KEY_1:
                GameClock.set_speed(1);
            KEY_2:
                GameClock.set_speed(2);
            KEY_3:
                GameClock.set_speed(3);
            KEY_F5:
                SaveGame.save(World.instance);
            KEY_F9:
                SaveGame.load_slot(World.instance);
            KEY_R:
                build_size = Vector2i(build_size.y, build_size.x);
            KEY_ESCAPE:
                _cancel();
        return;
    if not (event is InputEventMouseButton):
        return;
    var mb:InputEventMouseButton = event;
    if mb.button_index == MOUSE_BUTTON_RIGHT:
        # right-drag pans the camera, so only a plain click (on release) cancels
        if not mb.pressed and not World.instance.camera_rig.right_dragged:
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
            if _is_field_mode():
                _dragging = true;
                _drag_start = _hover_cell;
                return;
            var origin:Vector2i = _build_origin();
            error = World.instance.can_place(build_id, origin, build_size, relocating != null);
            if error == "" and relocating != null:
                var moved:Building = relocating;
                World.instance.relocate(moved, origin, build_size);
                set_mode(Mode.SELECT);
                select(moved);
            elif error == "":
                World.instance.place_building(build_id, origin, build_size);
        Mode.EXPAND:
            if World.alive(expanding):
                var grown:Rect2i = Expansion.target_rect(expanding, _hover_cell);
                error = Expansion.block_reason(World.instance, expanding, grown);
                if error == "" and Expansion.start(World.instance, expanding, grown):
                    var done:Building = expanding;
                    set_mode(Mode.SELECT);
                    select(done);
        Mode.HARVEST, Mode.FORAGE, Mode.ROAD, Mode.DEMOLISH, Mode.CANCEL:
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
        Mode.BUILD:
            # a plain click (no drag) keeps the default footprint
            var fr:Rect2i = _field_rect();
            error = World.instance.can_place(build_id, fr.position, fr.size) if _field_rect_valid(fr) else "%s must be at least %dx%d." % [Defs.BUILDINGS[build_id]["name"], _min_side(), _min_side()];
            if error == "":
                World.instance.place_building(build_id, fr.position, fr.size);
        Mode.HARVEST:
            var n:int = 0;
            for rn in w.nodes:
                if _drag_rect().has_point(rn.cell) and not rn.is_auto() and not rn.is_forageable() and not rn.designated:
                    w.set_designated(rn, true);
                    n += 1;
            error = "" if n > 0 else "No trees or rocks there.";
        Mode.FORAGE:
            var picked:int = 0;
            for rn in w.nodes:
                if _drag_rect().has_point(rn.cell) and rn.is_forageable() and not rn.designated:
                    w.set_designated(rn, true);
                    picked += 1;
            error = "" if picked > 0 else "Nothing to forage there.";
        Mode.ROAD:
            for c in _road_cells():
                w.plan_road(c);
        Mode.DEMOLISH:
            var r:Rect2i = _drag_rect();
            for b in w.buildings.duplicate():
                if b.rect().intersects(r):
                    w.remove_building(b, true);
            for z in range(r.position.y, r.end.y):
                for x in range(r.position.x, r.end.x):
                    w.set_road(Vector2i(x, z), false);
        Mode.CANCEL:
            var cr:Rect2i = _drag_rect();
            for b in w.buildings.duplicate():
                if b.state == Building.State.CONSTRUCTION and b.rect().intersects(cr):
                    w.remove_building(b, true);
            for rn in w.nodes:
                if cr.has_point(rn.cell) and w.occupant[w.idx(rn.cell)] == null:
                    w.set_designated(rn, false);
            for c in w.pending_roads.keys() + w.road_work.keys():
                if cr.has_point(c):
                    w.cancel_road(c);

# --------------------------------
# Per-frame

func _process(delta:float) -> void:
    _drop_gone_selection();
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
    _update_radius();

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

func _is_field_mode() -> bool:
    return mode == Mode.BUILD and Defs.BUILDINGS[build_id].get("drag_size", false);

# The field footprint for the current drag, or the default footprint for a click without a drag.
func _field_rect() -> Rect2i:
    if _drag_start == _hover_cell:
        return Rect2i(_build_origin(), build_size);
    # the corner under the start stays put; the far edge follows the cursor up to the size limit
    var d:Vector2i = _hover_cell - _drag_start;
    var far:Vector2i = _drag_start + Vector2i(clampi(d.x, -(FIELD_MAX_SIDE - 1), FIELD_MAX_SIDE - 1), clampi(d.y, -(FIELD_MAX_SIDE - 1), FIELD_MAX_SIDE - 1));
    var lo:Vector2i = Vector2i(mini(_drag_start.x, far.x), mini(_drag_start.y, far.y));
    var hi:Vector2i = Vector2i(maxi(_drag_start.x, far.x), maxi(_drag_start.y, far.y));
    var size:Vector2i = hi - lo + Vector2i.ONE;
    return Rect2i(lo, Vector2i(maxi(size.x, _min_side()), maxi(size.y, _min_side())));       # a thin drag grows to the minimum

# The smallest side of a variable-sized building (min_side in its def, default 1).
func _min_side() -> int:
    return Defs.BUILDINGS[build_id].get("min_side", 1);

func _field_rect_valid(r:Rect2i) -> bool:
    return r.size.x >= _min_side() and r.size.y >= _min_side();

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
    _model_ghost.hide_ghost();
    _update_preview();
    if not _hover_ok:
        return;
    var w:World = World.instance;
    match mode:
        Mode.BUILD:
            if _is_field_mode() and _dragging:
                var fr:Rect2i = _field_rect();
                var fok:bool = _field_rect_valid(fr) and w.can_place(build_id, fr.position, fr.size) == "";
                _show_box(0, fr, 0.3, _mat_ok if fok else _mat_bad);
                return;
            var origin:Vector2i = _build_origin();
            var ok:bool = w.can_place(build_id, origin, build_size, relocating != null) == "";
            var short:bool = ok and not _can_afford();
            _show_box(0, Rect2i(origin, build_size), 0.05, _mat_bad if not ok else _mat_area if short else _mat_ok);
            _model_ghost.show_at(w, build_id, origin, build_size, _mat_m_bad if not ok else _mat_m_short if short else _mat_m_ok);
        Mode.EXPAND:
            if World.alive(expanding):
                var grown:Rect2i = Expansion.target_rect(expanding, _hover_cell);
                var why:String = Expansion.block_reason(w, expanding, grown);
                _show_box(0, grown, 0.15, _mat_ok if why == "" else _mat_bad);
                error = "" if why == "" or grown == expanding.rect() else why;
        Mode.HARVEST, Mode.FORAGE, Mode.DEMOLISH, Mode.CANCEL:
            var r:Rect2i = _drag_rect() if _dragging else Rect2i(_hover_cell, Vector2i.ONE);
            _show_box(0, r, 0.4, _mat_bad if mode == Mode.DEMOLISH else _mat_area);
        Mode.ROAD:
            if _dragging:
                var cells:Array[Vector2i] = _road_cells();
                var a:Vector2i = _drag_start;
                var b:Vector2i = _hover_cell;
                var road_mat:StandardMaterial3D = _mat_ok if cells.all(w.can_plan_road) else _mat_bad;      # red: part of it can't be laid
                _show_box(0, Rect2i(Vector2i(mini(a.x, b.x), a.y), Vector2i(absi(b.x - a.x) + 1, 1)), 0.2, road_mat);
                if cells.size() > absi(b.x - a.x) + 1:
                    _show_box(1, Rect2i(Vector2i(b.x, mini(a.y, b.y)), Vector2i(1, absi(b.y - a.y) + 1)), 0.2, road_mat);
            else:
                _show_box(0, Rect2i(_hover_cell, Vector2i.ONE), 0.2, _mat_ok if w.can_plan_road(_hover_cell) else _mat_bad);
        Mode.RAISE, Mode.LOWER, Mode.FLATTEN:
            var rr:int = ceili(BRUSH_RADIUS);
            _show_box(0, Rect2i(_hover_cell - Vector2i(rr, rr) + Vector2i.ONE, Vector2i(rr * 2 - 1, rr * 2 - 1)), 0.3, _mat_area);

# While marking trees, rocks or forage, the things the selection would mark change colour.
func _update_preview() -> void:
    var renderer:ResourceRenderer = World.instance.renderer;
    if not _hover_ok or (mode != Mode.HARVEST and mode != Mode.FORAGE):
        renderer.set_preview(Rect2i(), Callable());
        return;
    var r:Rect2i = _drag_rect() if _dragging else Rect2i(_hover_cell, Vector2i.ONE);
    renderer.set_preview(r, _harvest_filter if mode == Mode.HARVEST else _forage_filter);

func _harvest_filter(rn:ResourceNode) -> bool:
    return not rn.is_auto() and not rn.is_forageable() and not rn.designated;

func _forage_filter(rn:ResourceNode) -> bool:
    return rn.is_forageable() and not rn.designated;

# The footprint being placed by a variable-sized building tool, as text ("6x8 tiles, 48 total"), or "".
func size_text() -> String:
    if mode == Mode.EXPAND and _hover_ok and World.alive(expanding):
        var grown:Rect2i = Expansion.target_rect(expanding, _hover_cell);
        if grown == expanding.rect():
            return "";
        var extra:Dictionary = Expansion.plan(expanding, grown)["cost"];
        return "%dx%d tiles, %d total, +%d%s" % [grown.size.x, grown.size.y, grown.size.x * grown.size.y, grown.size.x * grown.size.y - expanding.size.x * expanding.size.y, ": " + Defs.cost_string(extra) if not extra.is_empty() else ""];
    if mode != Mode.BUILD or not _is_field_mode() or not _hover_ok:
        return "";
    var r:Rect2i = _field_rect() if _dragging else Rect2i(_build_origin(), build_size);
    if r.size == Vector2i.ONE:
        return "1x1 tile";
    return "%dx%d tiles, %d total" % [r.size.x, r.size.y, r.size.x * r.size.y];

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

# A ring on the ground showing a job building's work radius, while placing one or with one selected.
func _update_radius() -> void:
    var center:Vector2 = Vector2.ZERO;
    var r:float = 0.0;
    if mode == Mode.BUILD and _hover_ok and Defs.BUILDINGS[build_id].has("radius"):
        center = Vector2(_build_origin()) + Vector2(build_size) * 0.5;
        r = Defs.BUILDINGS[build_id]["radius"];
    elif selected is Building and (selected as Building).radius() > 0.0:
        center = (selected as Building).center_cell();
        r = (selected as Building).radius();
    _radius_line.visible = r > 0.0;
    if r <= 0.0:
        _radius_key = "";
        return;
    var key:String = "%.1f,%.1f,%.1f" % [center.x, center.y, r];
    if key == _radius_key:
        return;
    _radius_key = key;
    var im:ImmediateMesh = _radius_line.mesh;
    im.clear_surfaces();
    im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP);
    var t:Terrain = World.instance.terrain;
    for i in 97:
        var a:float = TAU * i / 96.0;
        var x:float = clampf(center.x + cos(a) * r, 0.0, Terrain.SIZE - 0.01);
        var z:float = clampf(center.y + sin(a) * r, 0.0, Terrain.SIZE - 0.01);
        im.surface_add_vertex(Vector3(x, t.height_at(x, z) + 0.25, z));
    im.surface_end();

# Clears the selection once what it points at is removed or freed. A freed object compares equal to null, so
# `selected != null` can't be used for this: typeof and is_instance_valid can.
func _drop_gone_selection() -> void:
    if typeof(selected) == TYPE_OBJECT and not World.alive(selected):
        select(null);

func _update_ring() -> void:
    _drop_gone_selection();
    _ring.visible = selected != null;
    if selected is Pawn:
        _ring.visible = (selected as Pawn).visible;
        _ring.scale = Vector3.ONE;
        _ring.position = (selected as Pawn).position + Vector3(0, 0.05, 0);
    elif selected is Building:
        _ring.visible = false;
        _update_frame((selected as Building).rect());
        return;
    elif selected is ResourceNode:
        var rn:ResourceNode = selected;
        _ring.scale = Vector3.ONE * 1.0;
        _ring.position = World.instance.terrain.cell_center(rn.cell) + Vector3(0, 0.05, 0);
    for bar in _frame:
        bar.visible = false;

# A thin rectangular outline around the footprint, held just above the highest ground under it.
func _update_frame(r:Rect2i) -> void:
    const BAR:float = 0.12;
    var hr:Vector2 = World.instance.terrain.rect_height_range(r.intersection(Rect2i(0, 0, Terrain.SIZE, Terrain.SIZE)));
    var y:float = hr.y + 0.12;
    var x0:float = r.position.x;
    var z0:float = r.position.y;
    var w:float = r.size.x;
    var d:float = r.size.y;
    var parts:Array = [
        [Vector3(w, BAR, BAR), Vector3(x0 + w * 0.5, y, z0 + BAR * 0.5)],
        [Vector3(w, BAR, BAR), Vector3(x0 + w * 0.5, y, z0 + d - BAR * 0.5)],
        [Vector3(BAR, BAR, d), Vector3(x0 + BAR * 0.5, y, z0 + d * 0.5)],
        [Vector3(BAR, BAR, d), Vector3(x0 + w - BAR * 0.5, y, z0 + d * 0.5)],
    ];
    for i in 4:
        (_frame[i].mesh as BoxMesh).size = parts[i][0];
        _frame[i].position = parts[i][1];
        _frame[i].visible = true;

# Whether the colony's stores hold the materials for the building being placed right now.
func _can_afford() -> bool:
    var cost:Dictionary = _relocation_cost(relocating) if relocating != null else Defs.BUILDINGS[build_id]["cost"];
    for item in cost:
        if Stock.available(item) < cost[item]:
            return false;
    return true;

# Shaded and see-through, so the building's shape still reads.
func _model_material(c:Color) -> StandardMaterial3D:
    var m:StandardMaterial3D = StandardMaterial3D.new();
    m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA;
    m.albedo_color = c;
    return m;

func _ghost_material(c:Color) -> StandardMaterial3D:
    var m:StandardMaterial3D = StandardMaterial3D.new();
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED;
    m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA;
    m.albedo_color = c;
    m.cull_mode = BaseMaterial3D.CULL_DISABLED;
    return m;
