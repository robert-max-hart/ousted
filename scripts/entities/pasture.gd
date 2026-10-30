# ----------------------------------------------------------------
# Pasture
#     A fenced run for one kind of farm animal (Chicken Run, Cow
#     Pasture), sized by dragging. It starts empty: animals are bought
#     from a merchant and led here by a citizen (TradeTasks). Each day the animals graze (warm weather) or eat grain
#     from the building's input buffer (the cold months), give their
#     product and manure, and breed while there is room. Farmers
#     collect the product and the manure (HerdTasks); manure is spread
#     on poor fields (Field). Animals that go unfed die.
# ----------------------------------------------------------------
class_name Pasture extends Building;

const COLLECT_AT      :int = 4;        # units ready before a farmer is sent
const READY_CAP       :int = 60;       # what piles up uncollected (the rest is lost)
const STARVE_CHANCE   :float = 0.35;   # chance a day that each unfed animal dies
const FEED_DAYS       :float = 12.0;   # the grain buffer a herd is topped up to, in days of feed
const STOCK_UP_BELOW  :float = 12.0;   # C, daily mean: below this the buffer is kept stocked (autumn, winter, early spring)

var animals     :int = 0;
var arrived     :bool = false;         # (old saves: had its founding stock; unused now, animals are bought)
var incoming_animals:int = 0;           # being led here now (not saved)
var product_acc :float = 0.0;
var manure_acc  :float = 0.0;
var feed_acc    :float = 0.0;
var ready_product:int = 0;
var ready_manure:int = 0;
var claimed     :bool = false;         # a citizen is on the way to collect (not saved)
var _herd       :MultiMeshInstance3D;
var _t          :float = 0.0;
var _drawn      :int = -1;

static var _meshes:Dictionary = {};

func setup(w:World, id:StringName, o:Vector2i, s:Vector2i) -> void:
    super.setup(w, id, o, s);
    _fence = Fence.new(self, &"wood", 1);
    add_child(_fence);
    var mm:MultiMesh = MultiMesh.new();
    mm.transform_format = MultiMesh.TRANSFORM_3D;
    mm.use_colors = true;
    mm.mesh = _mesh_for(def["animal"]);
    _herd = MultiMeshInstance3D.new();
    _herd.multimesh = mm;
    _herd.material_override = CropMeshes.material();
    _herd.top_level = true;
    add_child(_herd);

func animal() -> Dictionary:
    return Defs.ANIMALS[def["animal"]];

@warning_ignore("integer_division")
func capacity_animals() -> int:
    return maxi(1, floori(size.x * size.y / animal()["cells"]));

func grazing() -> bool:
    return Weather.mean_temperature() >= Defs.GRAZING_ABOVE;

func feed_units() -> int:
    var n:int = 0;
    for item in def["inputs"]:
        n += input_amount(item);
    return n;

# --------------------------------
# Each day

func on_day() -> void:
    super.on_day();
    if not is_complete():
        return;
    if animals <= 0:
        return;
    _eat();
    var a:Dictionary = animal();
    product_acc += animals * a["rate"];
    manure_acc += animals * a["manure"];
    var p:int = floori(product_acc);
    var m:int = floori(manure_acc);
    product_acc -= p;
    manure_acc -= m;
    ready_product = mini(READY_CAP, ready_product + p);
    ready_manure = mini(READY_CAP, ready_manure + m);
    if animals >= 2 and animals < capacity_animals() and world.rng.randf() < a["breed"]:
        animals += 1;

# Room for more, counting animals already on the way.
func free_room() -> int:
    return maxi(0, capacity_animals() - animals - incoming_animals);

# Animals arrive (from a merchant, led by a citizen). Returns how many fitted.
func add_animals(n:int) -> int:
    var k:int = clampi(n, 0, maxi(0, capacity_animals() - animals));
    animals += k;
    return k;

# Grazing is free in warm weather; otherwise the herd eats grain from the buffer, and animals with nothing to eat die.
func _eat() -> void:
    if grazing():
        feed_acc = 0.0;
        return;
    feed_acc += animals * animal()["feed"];
    var need:int = floori(feed_acc);
    feed_acc -= need;
    for item in def["inputs"]:
        var take:int = mini(need, input_amount(item));
        take_input(item, take);
        need -= take;
    if need <= 0:
        return;
    var hungry:int = mini(animals, ceili(need / maxf(0.01, animal()["feed"])));
    var lost:int = 0;
    for i in hungry:
        if world.rng.randf() < STARVE_CHANCE:
            lost += 1;
    animals -= lost;
    if lost > 0:
        world.notify("%d %s starved at the %s: they need grain in the cold months." % [lost, animal()["name"].to_lower(), display_name().to_lower()]);

# Grain wanted for the buffer: kept stocked in the cold months, with whichever grain the colony has.
func inputs_wanted() -> Dictionary:
    var want:Dictionary = {};
    if not is_complete() or animals <= 0 or Weather.mean_temperature() >= STOCK_UP_BELOW:
        return want;
    var target:int = maxi(4, ceili(animals * animal()["feed"] * FEED_DAYS));
    var have:int = feed_units();
    for item in def["inputs"]:
        have += input_incoming.get(item, 0);
    if have >= target:
        return want;
    for item in def["inputs"]:
        if Stock.available(item) > 0:
            want[item] = target - have;
            return want;
    return want;

# --------------------------------
# What farmers collect

# {"item": the product or manure, "n": units ready}, or {} when there is not enough yet.
func collectable() -> Dictionary:
    if ready_product >= COLLECT_AT:
        return {"item": animal()["product"], "n": ready_product};
    if ready_manure >= COLLECT_AT:
        return {"item": &"manure", "n": ready_manure};
    return {};

func take_ready(item:StringName, n:int) -> int:
    if item == &"manure":
        var m:int = mini(n, ready_manure);
        ready_manure -= m;
        return m;
    var p:int = mini(n, ready_product);
    ready_product -= p;
    return p;

# --------------------------------
# Saving, info

func to_dict() -> Dictionary:
    var d:Dictionary = super.to_dict();
    d["animals"] = animals;
    d["arrived"] = arrived;
    d["product_acc"] = product_acc;
    d["manure_acc"] = manure_acc;
    d["feed_acc"] = feed_acc;
    d["ready_product"] = ready_product;
    d["ready_manure"] = ready_manure;
    return d;

func restore_dict(d:Dictionary) -> void:
    super.restore_dict(d);
    animals = d.get("animals", 0);
    arrived = d.get("arrived", false);
    product_acc = d.get("product_acc", 0.0);
    manure_acc = d.get("manure_acc", 0.0);
    feed_acc = d.get("feed_acc", 0.0);
    ready_product = d.get("ready_product", 0);
    ready_manure = d.get("ready_manure", 0);

func info_text() -> String:
    if state != State.COMPLETE:
        return super.info_text();
    var a:Dictionary = animal();
    var s:String = "%s: %d of %d\n" % [a["name"], animals, capacity_animals()];
    if animals == 0:
        s += "Empty: buy %s from a merchant at the Trading Post.\n" % a["name"].to_lower();
    s += "%s ready: %d, manure ready: %d\n" % [Defs.item_name(a["product"]), ready_product, ready_manure];
    s += "Feed: %s\n" % ("grazing" if grazing() else "grain in store %d" % feed_units());
    if not grazing() and animals > 0 and feed_units() < ceili(animals * a["feed"] * 3.0):
        s += "Running short of grain!\n";
    return s;

func help_text() -> String:
    return super.help_text() + "\nAnimals graze when it is warm and eat grain (barley or wheat) in the cold months; ones with nothing to eat die. Laborers and farmers bring the grain and collect the product and manure.";

# --------------------------------
# The herd, wandering inside the fence

func _process(delta:float) -> void:
    if animals != _drawn:
        _drawn = animals;
        _herd.multimesh.instance_count = animals if is_complete() else 0;
    if animals <= 0 or not is_complete() or not _herd.visible:
        return;
    _t += delta * 0.6;
    var r:Rect2 = Rect2(rect()).grow(-0.9);
    for i in animals:
        var h:int = (i * 73856093) ^ (origin.x * 19349663) ^ (origin.y * 83492791);
        var fx:float = float(h & 1023) / 1023.0;
        var fz:float = float((h >> 10) & 1023) / 1023.0;
        var ph:float = float((h >> 20) & 255) / 255.0 * TAU;
        var x:float = r.position.x + fx * maxf(r.size.x, 0.1) + sin(_t * 0.7 + ph) * 0.5;
        var z:float = r.position.y + fz * maxf(r.size.y, 0.1) + cos(_t * 0.55 + ph * 1.3) * 0.5;
        var yaw:float = atan2(cos(_t * 0.7 + ph) * 0.35, -sin(_t * 0.55 + ph * 1.3) * 0.28) + PI * 0.5;
        var grow:float = 1.0;
        _herd.multimesh.set_instance_transform(i, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(grow, grow, grow)), Vector3(x, world.terrain.height_at(x, z), z)));
        _herd.multimesh.set_instance_color(i, _coat(i));

func _coat(i:int) -> Color:
    if def["animal"] == &"chicken":
        return [Color(1, 1, 1), Color(0.85, 0.65, 0.45), Color(0.95, 0.9, 0.8)][i % 3];
    if def["animal"] == &"sheep":
        return [Color(0.96, 0.94, 0.88), Color(0.9, 0.88, 0.82), Color(0.55, 0.5, 0.45)][i % 3];
    return [Color(0.8, 0.6, 0.4), Color(0.95, 0.95, 0.92), Color(0.55, 0.4, 0.3), Color(0.35, 0.3, 0.28)][i % 4];

static func _mesh_for(kind:StringName) -> ArrayMesh:
    if _meshes.has(kind):
        return _meshes[kind];
    var mesh:ArrayMesh = ArrayMesh.new();
    var mat:StandardMaterial3D = CropMeshes.material();
    if kind == &"chicken":
        var body:SphereMesh = SphereMesh.new();
        body.radius = 0.16;
        body.height = 0.26;
        body.radial_segments = 6;
        body.rings = 3;
        ResourceRenderer.add_part(mesh, body, Transform3D(Basis(), Vector3(0, 0.2, 0)), mat);
        var head:SphereMesh = SphereMesh.new();
        head.radius = 0.07;
        head.height = 0.14;
        head.radial_segments = 5;
        head.rings = 2;
        ResourceRenderer.add_part(mesh, head, Transform3D(Basis(), Vector3(0.14, 0.36, 0)), mat);
        var comb:BoxMesh = BoxMesh.new();
        comb.size = Vector3(0.04, 0.05, 0.02);
        ResourceRenderer.add_part(mesh, comb, Transform3D(Basis(), Vector3(0.15, 0.43, 0)), mat, Color(0.85, 0.15, 0.15));
        var tail:BoxMesh = BoxMesh.new();
        tail.size = Vector3(0.14, 0.14, 0.03);
        ResourceRenderer.add_part(mesh, tail, Transform3D(Basis(Vector3.BACK, 0.7), Vector3(-0.16, 0.3, 0)), mat);
    elif kind == &"sheep":
        var fleece:SphereMesh = SphereMesh.new();
        fleece.radius = 0.3;
        fleece.height = 0.5;
        fleece.radial_segments = 7;
        fleece.rings = 4;
        ResourceRenderer.add_part(mesh, fleece, Transform3D(Basis(), Vector3(0, 0.42, 0)), mat);
        var face:BoxMesh = BoxMesh.new();
        face.size = Vector3(0.2, 0.2, 0.18);
        ResourceRenderer.add_part(mesh, face, Transform3D(Basis(), Vector3(0.34, 0.5, 0)), mat, Color(0.35, 0.3, 0.28));
        for sx in [-0.14, 0.14]:
            for sz in [-0.1, 0.1]:
                var leg:BoxMesh = BoxMesh.new();
                leg.size = Vector3(0.06, 0.24, 0.06);
                ResourceRenderer.add_part(mesh, leg, Transform3D(Basis(), Vector3(sx, 0.12, sz)), mat, Color(0.3, 0.27, 0.25));
    else:
        var body:BoxMesh = BoxMesh.new();
        body.size = Vector3(0.95, 0.5, 0.45);
        ResourceRenderer.add_part(mesh, body, Transform3D(Basis(), Vector3(0, 0.7, 0)), mat);
        var head:BoxMesh = BoxMesh.new();
        head.size = Vector3(0.28, 0.28, 0.3);
        ResourceRenderer.add_part(mesh, head, Transform3D(Basis(), Vector3(0.58, 0.82, 0)), mat);
        for sx in [-0.32, 0.32]:
            for sz in [-0.15, 0.15]:
                var leg:BoxMesh = BoxMesh.new();
                leg.size = Vector3(0.1, 0.5, 0.1);
                ResourceRenderer.add_part(mesh, leg, Transform3D(Basis(), Vector3(sx, 0.25, sz)), mat, Color(0.7, 0.7, 0.7));
        for sz in [-0.1, 0.1]:
            var horn:BoxMesh = BoxMesh.new();
            horn.size = Vector3(0.04, 0.1, 0.04);
            ResourceRenderer.add_part(mesh, horn, Transform3D(Basis(), Vector3(0.58, 1.02, sz * 1.6)), mat, Color(0.9, 0.88, 0.8));
    _meshes[kind] = mesh;
    return mesh;
