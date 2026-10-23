# ----------------------------------------------------------------
# Building
#     A placed structure. Goes through construction (materials hauled
#     in, then labor) before it starts functioning.
# ----------------------------------------------------------------
class_name Building extends Node3D;

enum State { CONSTRUCTION, COMPLETE };

var def_id      :StringName;
var def         :Dictionary;
var origin      :Vector2i;
var size        :Vector2i;
var state       :int = State.CONSTRUCTION;
var delivered   :Dictionary = {};   # item -> int already on site
var incoming    :Dictionary = {};   # item -> int being carried here
var work_done   :float = 0.0;
var builders    :int = 0;
var residents   :Array[Pawn] = [];
var removed     :bool = false;
var world       :World;

var _body       :MeshInstance3D;
var _roof       :MeshInstance3D;
var _body_mat   :StandardMaterial3D;

func setup(w:World, id:StringName, o:Vector2i, s:Vector2i) -> void:
    world = w;
    def_id = id;
    def = Defs.BUILDINGS[id];
    origin = o;
    size = s;
    name = "%s_%d_%d" % [id, o.x, o.y];
    var center:Vector2 = Vector2(origin.x + size.x * 0.5, origin.y + size.y * 0.5);
    position = Vector3(center.x, w.terrain.height_at(center.x, center.y), center.y);
    _build_visual();
    _update_visual();

func rect() -> Rect2i:
    return Rect2i(origin, size);

func display_name() -> String:
    return def["name"];

func is_complete() -> bool:
    return state == State.COMPLETE;

func is_walkable() -> bool:
    return def.get("walkable", false);

# --------------------------------
# Construction

func cost() -> Dictionary:
    return def["cost"];

# Units of item still needed that nobody is bringing yet.
func remaining(item:StringName) -> int:
    return cost().get(item, 0) - delivered.get(item, 0) - incoming.get(item, 0);

func has_all_materials() -> bool:
    for item in cost():
        if delivered.get(item, 0) < cost()[item]:
            return false;
    return true;

func work_required() -> float:
    return def["work"];

func progress() -> float:
    if work_required() <= 0.0:
        return 1.0;
    return clampf(work_done / work_required(), 0.0, 1.0);

func ready_for_work() -> bool:
    return state == State.CONSTRUCTION and has_all_materials() and world.is_site_clear(self);

func receive(item:StringName, n:int) -> void:
    incoming[item] = maxi(0, incoming.get(item, 0) - n);
    delivered[item] = delivered.get(item, 0) + n;

func cancel_incoming(item:StringName, n:int) -> void:
    incoming[item] = maxi(0, incoming.get(item, 0) - n);

# Adds labor; returns true once construction is finished.
func add_work(hours:float) -> bool:
    if state != State.CONSTRUCTION:
        return true;
    work_done += hours;
    _update_visual();
    if work_done >= work_required():
        complete();
        return true;
    return false;

func complete() -> void:
    state = State.COMPLETE;
    work_done = work_required();
    _update_visual();
    world.on_building_completed(self);

# --------------------------------
# Simulation hooks (called by World)

func on_hour() -> void:
    pass;

func on_day() -> void:
    pass;

func on_terrain_changed() -> void:
    pass;

# --------------------------------
# Info

func info_text() -> String:
    var s:String = "";
    if state == State.CONSTRUCTION:
        s += "Under construction (%d%%)\n" % roundi(progress() * 100.0);
        if not world.is_site_clear(self):
            s += "Waiting for the site to be cleared\n";
        for item in cost():
            s += "  %s: %d / %d\n" % [Defs.item_name(item), delivered.get(item, 0), cost()[item]];
        if not has_all_materials():
            s += "Waiting for materials\n";
        s += "Builders: %d\n" % builders;
    else:
        s += def.get("desc", "") + "\n";
    if def.has("beds"):
        var names:PackedStringArray = [];
        for p in residents:
            names.append(p.first_name);
        s += "Residents (%d/%d): %s\n" % [residents.size(), def["beds"], ", ".join(names)];
    return s;

# --------------------------------
# Visuals

func _build_visual() -> void:
    var shape:String = def.get("shape", "house");
    var h:float = def.get("height", 2.0);
    _body_mat = StandardMaterial3D.new();
    _body_mat.albedo_color = def.get("color", Color.GRAY);
    _body_mat.roughness = 0.9;
    match shape:
        "house":
            var box:BoxMesh = BoxMesh.new();
            box.size = Vector3(size.x - 0.5, h, size.y - 0.5);
            _body = _add_mesh(box, _body_mat, Vector3(0, h * 0.5, 0));
            var prism:PrismMesh = PrismMesh.new();
            prism.size = Vector3(size.x - 0.1, h * 0.6, size.y - 0.2);
            _roof = _add_mesh(prism, _flat_mat(def.get("roof", Color.DARK_RED)), Vector3(0, h + h * 0.3, 0));
        "well":
            var cyl:CylinderMesh = CylinderMesh.new();
            cyl.top_radius = 0.7;
            cyl.bottom_radius = 0.75;
            cyl.height = h;
            _body = _add_mesh(cyl, _body_mat, Vector3(0, h * 0.5, 0));
            var cap:PrismMesh = PrismMesh.new();
            cap.size = Vector3(1.6, 0.5, 1.2);
            _roof = _add_mesh(cap, _flat_mat(def.get("roof", Color.BROWN)), Vector3(0, h + 0.9, 0));
        "pile":
            var pad:BoxMesh = BoxMesh.new();
            pad.size = Vector3(size.x - 0.3, h, size.y - 0.3);
            _body = _add_mesh(pad, _body_mat, Vector3(0, h * 0.5, 0));
            var crate:BoxMesh = BoxMesh.new();
            crate.size = Vector3(0.7, 0.6, 0.7);
            _roof = _add_mesh(crate, _flat_mat(Color(0.6, 0.45, 0.28)), Vector3(-0.8, h + 0.3, -0.8));
        _:
            pass;

func _update_visual() -> void:
    if _body == null:
        return;
    var building:bool = state == State.CONSTRUCTION;
    _body_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if building else BaseMaterial3D.TRANSPARENCY_DISABLED;
    var col:Color = def.get("color", Color.GRAY);
    col.a = 0.45 if building else 1.0;
    _body_mat.albedo_color = col;
    var sy:float = lerpf(0.15, 1.0, progress()) if building else 1.0;
    _body.scale = Vector3(1.0, sy, 1.0);
    var h:float = def.get("height", 2.0);
    _body.position.y = h * 0.5 * sy;
    if _roof != null:
        _roof.visible = not building;

func _add_mesh(mesh:Mesh, mat:Material, at:Vector3) -> MeshInstance3D:
    var mi:MeshInstance3D = MeshInstance3D.new();
    mi.mesh = mesh;
    mi.material_override = mat;
    mi.position = at;
    add_child(mi);
    return mi;

func _flat_mat(c:Color) -> StandardMaterial3D:
    var m:StandardMaterial3D = StandardMaterial3D.new();
    m.albedo_color = c;
    m.roughness = 0.9;
    return m;
