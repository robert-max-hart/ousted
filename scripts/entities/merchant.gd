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
var palette     :Array = [];         # the cart's two stripe colours and the trader's coat (see Traders.TYPES); empty: the old red and cream

func setup(w:World, from:Vector2i, route:Array[Vector2i], st:int) -> void:
    world = w;
    state = st;
    path = route;
    position = w.terrain.cell_center(from);
    _build_visual();
    name = "Merchant";

func _process(delta:float) -> void:
    if state == State.TRADING or path.is_empty():
        _rest();
        return;
    var time:float = delta * GameClock.speed();
    _animate(time * WALK_SPEED);
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

# Wheels roll by the distance walked, the donkey's legs swing and the trader bobs; standing still they settle.
func _animate(distance:float) -> void:
    _t += distance;
    for w in _wheels:
        w.rotation.x = _t / WHEEL_R;
    for i in _legs.size():
        _legs[i].rotation.x = sin(_t * 2.6 + (0.0 if i % 3 == 0 else PI)) * 0.45;
    _donkey.position.y = absf(sin(_t * 2.6)) * 0.03;
    _trader.position.y = absf(sin(_t * 2.6 + 0.8)) * 0.05;

func _rest() -> void:
    for l in _legs:
        l.rotation.x = lerpf(l.rotation.x, 0.0, 0.2);
    if _donkey != null:
        _donkey.position.y = lerpf(_donkey.position.y, 0.0, 0.2);
        _trader.position.y = lerpf(_trader.position.y, 0.0, 0.2);

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

# The caravan, built round the middle of the procession (cart behind, donkey ahead, trader at its head), facing +z.
const WHEEL_R:float = 0.36;

var _wheels:Array[Node3D] = [];
var _legs:Array[Node3D] = [];        # donkey legs, pivoting at the hip
var _trader:Node3D;
var _donkey:Node3D;
var _t:float = 0.0;                  # distance walked, drives the wheels and legs

func _build_visual() -> void:
    var wood:StandardMaterial3D = _tinted(Color(0.5, 0.36, 0.22));
    var dark_wood:StandardMaterial3D = _tinted(Color(0.34, 0.24, 0.15));
    var iron:StandardMaterial3D = _tinted(Color(0.2, 0.19, 0.19));
    var stripe_a:Color = palette[0] if palette.size() >= 3 else Color(0.72, 0.2, 0.16);
    var stripe_b:Color = palette[1] if palette.size() >= 3 else Color(0.93, 0.87, 0.7);
    var coat_color:Color = palette[2] if palette.size() >= 3 else Color(0.55, 0.2, 0.2);
    var red:StandardMaterial3D = _tinted(stripe_a);
    var cream:StandardMaterial3D = _tinted(stripe_b);
    var bed_y:float = 0.5;
    var cz:float = -1.0;                                    # the cart's middle
    # the bed, low side boards, a tailgate and the axle
    _part(_box(1.0, 0.14, 1.7), wood, Vector3(0, bed_y, cz));
    for sx in [-0.5, 0.5]:
        _part(_box(0.06, 0.28, 1.7), dark_wood, Vector3(sx, bed_y + 0.2, cz));
    _part(_box(1.0, 0.28, 0.06), dark_wood, Vector3(0, bed_y + 0.2, cz - 0.85));
    _part(_box(1.2, 0.07, 0.07), iron, Vector3(0, WHEEL_R, cz + 0.1));
    # wheels: a rim, crossed spokes and a hub, turning as the cart moves
    for sx in [-0.62, 0.62]:
        var wheel:Node3D = Node3D.new();
        wheel.position = Vector3(sx, WHEEL_R, cz + 0.1);
        add_child(wheel);
        var rim:TorusMesh = TorusMesh.new();
        rim.inner_radius = WHEEL_R - 0.06;
        rim.outer_radius = WHEEL_R;
        rim.rings = 16;
        rim.ring_segments = 5;
        var rim_mi:MeshInstance3D = _child(wheel, rim, dark_wood, Vector3.ZERO);
        rim_mi.rotation.z = PI * 0.5;
        for k in 3:
            var spoke:MeshInstance3D = _child(wheel, _box(0.05, WHEEL_R * 2.0 - 0.04, 0.05), wood, Vector3.ZERO);
            spoke.rotation.x = k * PI / 3.0;
        _child(wheel, _box(0.12, 0.1, 0.1), iron, Vector3.ZERO);
        _wheels.append(wheel);
    # the canvas hood over the load, open at both ends, in the stall's stripes
    var hood:PrismMesh = PrismMesh.new();
    hood.size = Vector3(1.06, 0.62, 1.35);
    _part(hood, BuildingShapes._awning(stripe_a, stripe_b), Vector3(0, bed_y + 0.38, cz + 0.12));
    # cargo behind the hood: a sack and a small crate, and a barrel strapped on the side
    _part(_ball(0.22, _tinted(Color(0.78, 0.7, 0.5)), 0.8), _tinted(Color(0.78, 0.7, 0.5)), Vector3(-0.15, bed_y + 0.2, cz - 0.62));
    _part(_box(0.34, 0.3, 0.3), _tinted(Color(0.78, 0.62, 0.38)), Vector3(0.22, bed_y + 0.22, cz - 0.62));
    var barrel:CylinderMesh = CylinderMesh.new();
    barrel.top_radius = 0.16;
    barrel.bottom_radius = 0.18;
    barrel.height = 0.4;
    barrel.radial_segments = 10;
    _part(barrel, dark_wood, Vector3(0.62, bed_y + 0.3, cz - 0.3));
    # a lantern on a short pole at the front corner
    _part(_box(0.05, 0.6, 0.05), dark_wood, Vector3(-0.46, bed_y + 0.45, cz + 0.8));
    _part(_ball(0.07, _tinted(Color(1.0, 0.82, 0.4)), 1.2), _tinted(Color(1.0, 0.82, 0.4)), Vector3(-0.46, bed_y + 0.8, cz + 0.8));
    # shafts running forward to the donkey
    for sx in [-0.32, 0.32]:
        var shaft:MeshInstance3D = _part(_box(0.05, 0.05, 1.5), dark_wood, Vector3(sx, 0.62, cz + 1.4));
        shaft.rotation.x = -0.05;
    # the donkey
    _donkey = Node3D.new();
    _donkey.position = Vector3(0, 0, 1.55);
    add_child(_donkey);
    var coat:StandardMaterial3D = _tinted(Color(0.55, 0.5, 0.45));
    var pale:StandardMaterial3D = _tinted(Color(0.82, 0.78, 0.7));
    _child(_donkey, _box(0.38, 0.4, 0.85), coat, Vector3(0, 0.82, 0));
    var neck:MeshInstance3D = _child(_donkey, _box(0.2, 0.5, 0.2), coat, Vector3(0, 1.02, 0.5));
    neck.rotation.x = 0.55;
    _child(_donkey, _box(0.2, 0.22, 0.34), coat, Vector3(0, 1.22, 0.75));
    _child(_donkey, _box(0.17, 0.14, 0.14), pale, Vector3(0, 1.17, 0.95));
    for ex in [-0.07, 0.07]:
        _child(_donkey, _box(0.05, 0.22, 0.07), coat, Vector3(ex, 1.42, 0.68));
    _child(_donkey, _box(0.05, 0.05, 0.4), coat, Vector3(0, 0.82, -0.58)).rotation.x = 0.6;       # tail
    _child(_donkey, _box(0.44, 0.06, 0.5), red, Vector3(0, 1.04, -0.02));                        # saddle cloth
    _child(_donkey, _ball(0.12, _tinted(Color(0.78, 0.7, 0.5)), 0.9), _tinted(Color(0.78, 0.7, 0.5)), Vector3(-0.24, 1.0, -0.02));
    _child(_donkey, _ball(0.12, _tinted(Color(0.78, 0.7, 0.5)), 0.9), _tinted(Color(0.78, 0.7, 0.5)), Vector3(0.24, 1.0, -0.02));
    for lx in [-0.12, 0.12]:
        for lz in [-0.3, 0.3]:
            var hip:Node3D = Node3D.new();
            hip.position = Vector3(lx, 0.62, lz);
            _donkey.add_child(hip);
            _child(hip, _box(0.08, 0.62, 0.08), coat, Vector3(0, -0.31, 0));
            _child(hip, _box(0.1, 0.08, 0.12), _tinted(Color(0.2, 0.17, 0.14)), Vector3(0, -0.64, 0.01));
            _legs.append(hip);
    # the trader, walking at the donkey's head with a stick
    _trader = Node3D.new();
    _trader.position = Vector3(0.62, 0, 2.15);
    add_child(_trader);
    var coat_red:StandardMaterial3D = _tinted(coat_color);
    var body:CapsuleMesh = CapsuleMesh.new();
    body.radius = 0.2;
    body.height = 1.1;
    _child(_trader, body, coat_red, Vector3(0, 0.55, 0));
    var head:SphereMesh = SphereMesh.new();
    head.radius = 0.15;
    head.height = 0.3;
    _child(_trader, head, _tinted(Color(0.9, 0.75, 0.6)), Vector3(0, 1.25, 0));
    var hat:CylinderMesh = CylinderMesh.new();
    hat.top_radius = 0.11;
    hat.bottom_radius = 0.24;
    hat.height = 0.13;
    _child(_trader, hat, dark_wood, Vector3(0, 1.42, 0));
    _child(_trader, _box(0.05, 1.3, 0.05), wood, Vector3(0.28, 0.65, 0.1));        # the stick
    _child(_trader, _box(0.3, 0.4, 0.14), cream, Vector3(0, 0.75, -0.2));            # a pack on the back

func _box(x:float, y:float, z:float) -> BoxMesh:
    var m:BoxMesh = BoxMesh.new();
    m.size = Vector3(x, y, z);
    return m;

func _ball(r:float, _mat:Material, squash:float = 1.0) -> SphereMesh:
    var m:SphereMesh = SphereMesh.new();
    m.radius = r;
    m.height = r * 2.0 * squash;
    m.radial_segments = 8;
    m.rings = 4;
    return m;

func _tinted(c:Color) -> StandardMaterial3D:
    var m:StandardMaterial3D = StandardMaterial3D.new();
    m.albedo_color = c;
    m.roughness = 0.9;
    return m;

func _part(mesh:Mesh, mat:Material, at:Vector3) -> MeshInstance3D:
    return _child(self, mesh, mat, at);

func _child(parent:Node3D, mesh:Mesh, mat:Material, at:Vector3) -> MeshInstance3D:
    var mi:MeshInstance3D = MeshInstance3D.new();
    mi.mesh = mesh;
    mi.material_override = mat;
    mi.position = at;
    parent.add_child(mi);
    return mi;
