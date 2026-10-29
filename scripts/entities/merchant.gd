# ----------------------------------------------------------------
# Merchant
#     A travelling trader and their cart. Walks in from the map edge
#     to the Trading Post, waits there (trading is handled by Traders),
#     and later walks back out and is gone. Visual only: no needs, no
#     jobs, and citizens walk through it.
# ----------------------------------------------------------------
class_name Merchant extends Node3D;

enum State { ARRIVING, TRADING, LEAVING }

const WALK_SPEED:float = 2.4;        # metres per real second at 1x

var world       :World;
var state       :int = State.ARRIVING;
var path        :Array[Vector2i] = [];
var _path_i     :int = 0;
var arrived     :Callable;           # called once, when the cart reaches the post
var gone        :Callable;           # called once, when it has walked off

func setup(w:World, from:Vector2i, route:Array[Vector2i], st:int) -> void:
    world = w;
    state = st;
    path = route;
    position = w.terrain.cell_center(from);
    _build_visual();
    name = "Merchant";

func _process(delta:float) -> void:
    if state == State.TRADING or path.is_empty():
        return;
    var time:float = delta * GameClock.speed();
    while time > 0.0 and _path_i < path.size():
        var c:Vector2i = path[_path_i];
        var to:Vector2 = Vector2(c.x + 0.5 - position.x, c.y + 0.5 - position.z);
        var d:float = to.length();
        if d > 0.001:
            rotation.y = atan2(to.x, to.y);
        var reach:float = WALK_SPEED * time;
        if d <= reach:
            position.x = c.x + 0.5;
            position.z = c.y + 0.5;
            time -= d / WALK_SPEED;
            _path_i += 1;
        else:
            position.x += to.x / d * reach;
            position.z += to.y / d * reach;
            time = 0.0;
    position.y = world.terrain.height_at(position.x, position.z);
    if _path_i >= path.size():
        if state == State.ARRIVING:
            state = State.TRADING;
            if arrived.is_valid():
                arrived.call();
        elif state == State.LEAVING:
            if gone.is_valid():
                gone.call();
            queue_free();

# Turns the merchant round and sends them back along a route (to the edge they came from).
func leave(route:Array[Vector2i]) -> void:
    state = State.LEAVING;
    path = route;
    _path_i = 0;

# The cell the merchant is on, and what is left of the route (for saving).
func cell() -> Vector2i:
    return world.terrain.world_to_cell(position);

func remaining_route() -> Array[Vector2i]:
    var out:Array[Vector2i] = [];
    for i in range(_path_i, path.size()):
        out.append(path[i]);
    return out;

func _build_visual() -> void:
    var wood:StandardMaterial3D = StandardMaterial3D.new();
    wood.albedo_color = Color(0.5, 0.36, 0.22);
    var cloth:StandardMaterial3D = StandardMaterial3D.new();
    cloth.albedo_color = Color(0.78, 0.62, 0.3);
    var dark:StandardMaterial3D = StandardMaterial3D.new();
    dark.albedo_color = Color(0.22, 0.16, 0.1);
    var bed:BoxMesh = BoxMesh.new();
    bed.size = Vector3(0.9, 0.3, 1.5);
    _part(bed, wood, Vector3(0, 0.45, 0));
    var load_mesh:BoxMesh = BoxMesh.new();
    load_mesh.size = Vector3(0.8, 0.5, 1.2);
    _part(load_mesh, cloth, Vector3(0, 0.85, -0.05));
    var wheel:CylinderMesh = CylinderMesh.new();
    wheel.top_radius = 0.3;
    wheel.bottom_radius = 0.3;
    wheel.height = 0.1;
    for sx in [-0.5, 0.5]:
        for sz in [-0.5, 0.5]:
            var w:MeshInstance3D = _part(wheel, dark, Vector3(sx, 0.3, sz));
            w.rotation.z = PI * 0.5;
    var body:CapsuleMesh = CapsuleMesh.new();
    body.radius = 0.2;
    body.height = 1.1;
    var trader:MeshInstance3D = _part(body, cloth, Vector3(0, 0.55, 1.2));
    trader.material_override = _tinted(Color(0.55, 0.2, 0.2));
    var head:SphereMesh = SphereMesh.new();
    head.radius = 0.15;
    head.height = 0.3;
    var h:MeshInstance3D = _part(head, _tinted(Color(0.9, 0.75, 0.6)), Vector3(0, 1.25, 1.2));
    h.name = "Head";
    var hat:CylinderMesh = CylinderMesh.new();
    hat.top_radius = 0.12;
    hat.bottom_radius = 0.22;
    hat.height = 0.12;
    _part(hat, dark, Vector3(0, 1.43, 1.2));

func _tinted(c:Color) -> StandardMaterial3D:
    var m:StandardMaterial3D = StandardMaterial3D.new();
    m.albedo_color = c;
    return m;

func _part(mesh:Mesh, mat:Material, at:Vector3) -> MeshInstance3D:
    var mi:MeshInstance3D = MeshInstance3D.new();
    mi.mesh = mesh;
    mi.material_override = mat;
    mi.position = at;
    add_child(mi);
    return mi;
