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
const SLAUGHTER_PER_DAY:int = 2;       # most animals slaughtered a day when over the "keep at most" level
const EXTRA_COLLECT_AT:int = 2;        # meat or leather ready before a farmer is sent
const SPEED           :Dictionary = {&"chicken": 0.55, &"sheep": 0.38, &"cow": 0.3};      # metres a second at 1x
const GRAZE_FOR       :Vector2 = Vector2(3.0, 9.0);       # seconds an animal stands with its head down before wandering on
const YOUNG_OFFSET    :Dictionary = {&"chicken": 0.45, &"sheep": 0.8, &"cow": 1.15};       # how far from its mother a young one stands
const YOUNG_SIZE      :float = 0.45;                      # a newborn's size against a grown one
const CHICK_COLOUR    :Color = Color(1.0, 0.88, 0.4);
const STARVE_CHANCE   :float = 0.35;   # chance a day that each unfed animal dies
const FEED_DAYS       :float = 12.0;   # the grain buffer a herd is topped up to, in days of feed
const STOCK_UP_BELOW  :float = 12.0;   # C, daily mean: below this the buffer is kept stocked (autumn, winter, early spring)

var kind        :StringName = &"chicken";   # which animal this pasture keeps (Defs.ANIMALS); changeable only while it is empty
var animals     :int = 0;
var incoming_animals:int = 0;           # being led here now (not saved)
var product_acc :float = 0.0;
var manure_acc  :float = 0.0;
var feed_acc    :float = 0.0;
var ready_product:int = 0;
var ready_manure:int = 0;
var ready_extra :Dictionary = {};      # item -> units from slaughtered animals (meat, leather) waiting for a farmer
var claimed     :bool = false;         # a citizen is on the way to collect (not saved)
var _herd       :Node3D;                        # holds the herd's layers: body, head and legs (see Animals)
var _layers     :Dictionary = {};               # part -> MultiMeshInstance3D
var young_ages  :Array[float] = [];     # days old, oldest first, of the young in the herd (the last of its animals): drawn small until grown. Looks only; saved
var _t          :float = 0.0;
var _pos        :PackedVector2Array = PackedVector2Array();       # where each animal is, where it is heading, how long it waits there, and how it is moving
var _goal       :PackedVector2Array = PackedVector2Array();
var _wait       :PackedFloat32Array = PackedFloat32Array();
var _yaw        :PackedFloat32Array = PackedFloat32Array();
var _walk       :PackedFloat32Array = PackedFloat32Array();
var _graze      :PackedFloat32Array = PackedFloat32Array();
var _vis_rng    :RandomNumberGenerator = RandomNumberGenerator.new();      # (not the world's: the herd's looks must not change a game's random numbers)
var _drawn      :int = -1;

func setup(w:World, id:StringName, o:Vector2i, s:Vector2i) -> void:
    super.setup(w, id, o, s);
    _fence = Fence.new(self, &"wood", 1);
    add_child(_fence);
    _herd = Node3D.new();
    _herd.top_level = true;
    add_child(_herd);
    _make_layers();

# The multimesh layers for the current kind of animal (made again when the kind is changed).
func _make_layers() -> void:
    for part in _layers:
        (_layers[part] as Node).queue_free();
    _layers.clear();
    for part in Animals.PARTS:
        var layer:MultiMeshInstance3D = Animals.make_layer(kind, part);
        _herd.add_child(layer);
        _layers[part] = layer;
    _drawn = -1;

func display_name() -> String:
    return "%s Pasture" % String(animal()["one"]).capitalize();

func animal() -> Dictionary:
    return Defs.ANIMALS[kind];

# Whether the animal can be changed now: nothing in the pasture and nothing on the way.
func can_change_kind() -> bool:
    return animals <= 0 and incoming_animals <= 0;

# Chooses the animal. Returns false (and changes nothing) when it is not allowed.
func set_kind(k:StringName) -> bool:
    if not Defs.ANIMALS.has(k) or not can_change_kind():
        return false;
    kind = k;
    product_acc = 0.0;
    manure_acc = 0.0;
    feed_acc = 0.0;
    ready_product = 0;
    ready_manure = 0;
    ready_extra.clear();
    young_ages.clear();
    _make_layers();
    return true;

@warning_ignore("integer_division")
func capacity_animals() -> int:
    return capacity_for(kind);

# How many of an animal this pasture would hold.
func capacity_for(k:StringName) -> int:
    return maxi(1, floori(size.x * size.y / Defs.ANIMALS[k]["cells"]));

# Whether animals of this kind could be put in it: it keeps them already, or it is empty and could change to them.
func can_host(k:StringName) -> bool:
    return kind == k or can_change_kind();

# Room for this kind, counting what is on the way: an empty pasture has room for any kind.
func room_for(k:StringName) -> int:
    if kind == k:
        return free_room();
    return capacity_for(k) if can_change_kind() else 0;

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
    for i in young_ages.size():
        young_ages[i] += 1.0;
    while not young_ages.is_empty() and young_ages[0] >= a["mature"]:
        young_ages.pop_front();
    if animals >= 2 and animals < capacity_animals() and world.rng.randf() < a["breed"]:
        animals += 1;
        young_ages.append(0.0);
    _cull();

# A herd over its "keep at most" level has a few animals slaughtered a day for their meat and leather.
func _cull() -> void:
    var keep:int = settings.get("keep", 0);
    if keep <= 0 or animals <= keep:
        return;
    var n:int = mini(animals - keep, SLAUGHTER_PER_DAY);
    var a:Dictionary = animal();
    animals -= n;
    for item in [&"meat", &"leather"]:
        var got:int = n * a.get(String(item), 0);
        if got > 0:
            ready_extra[item] = mini(READY_CAP, ready_extra.get(item, 0) + got);

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
    for item in ready_extra:
        if ready_extra[item] >= EXTRA_COLLECT_AT:
            return {"item": item, "n": ready_extra[item]};
    return {};

func take_ready(item:StringName, n:int) -> int:
    if item == &"manure":
        var m:int = mini(n, ready_manure);
        ready_manure -= m;
        return m;
    if ready_extra.has(item):
        var e:int = mini(n, ready_extra[item]);
        ready_extra[item] -= e;
        if ready_extra[item] <= 0:
            ready_extra.erase(item);
        return e;
    var p:int = mini(n, ready_product);
    ready_product -= p;
    return p;

# --------------------------------
# Saving, info

func to_dict() -> Dictionary:
    var d:Dictionary = super.to_dict();
    d["kind"] = kind;
    d["animals"] = animals;
    d["product_acc"] = product_acc;
    d["manure_acc"] = manure_acc;
    d["feed_acc"] = feed_acc;
    d["ready_product"] = ready_product;
    d["ready_manure"] = ready_manure;
    d["ready_extra"] = ready_extra.duplicate();
    d["young"] = young_ages.duplicate();
    return d;

func restore_dict(d:Dictionary) -> void:
    super.restore_dict(d);
    kind = d.get("kind", &"chicken");
    _make_layers();
    animals = d.get("animals", 0);
    product_acc = d.get("product_acc", 0.0);
    manure_acc = d.get("manure_acc", 0.0);
    feed_acc = d.get("feed_acc", 0.0);
    ready_product = d.get("ready_product", 0);
    ready_manure = d.get("ready_manure", 0);
    ready_extra = d.get("ready_extra", {});
    young_ages.clear();
    for a in d.get("young", []):
        young_ages.append(float(a));

func info_text() -> String:
    if state != State.COMPLETE:
        return super.info_text();
    var a:Dictionary = animal();
    var s:String = "%s: %d of %d\n" % [a["name"], animals, capacity_animals()];
    if animals == 0:
        s += "Empty: buy %s from a merchant at the Trading Post.\n" % a["name"].to_lower();
    s += "%s ready: %d, manure ready: %d\n" % [Defs.item_name(a["product"]), ready_product, ready_manure];
    if not ready_extra.is_empty():
        var parts:PackedStringArray = [];
        for item in ready_extra:
            parts.append("%d %s" % [ready_extra[item], Defs.item_name(item).to_lower()]);
        s += "Slaughtered, waiting to be collected: %s\n" % ", ".join(parts);
    if settings.get("keep", 0) > 0:
        s += "Keeping at most %d: the surplus is slaughtered.\n" % settings["keep"];
    s += "Feed: %s\n" % ("grazing" if grazing() else "grain in store %d" % feed_units());
    if not grazing() and animals > 0 and feed_units() < ceili(animals * a["feed"] * 3.0):
        s += "Running short of grain!\n";
    return s;

func help_text() -> String:
    return super.help_text() + "\nAnimals graze when it is warm and eat grain (barley or wheat) in the cold months; ones with nothing to eat die. Laborers and farmers bring the grain and collect the product and manure.";

# --------------------------------
# The herd, wandering inside the fence

func young_count() -> int:
    return mini(young_ages.size(), animals);

func _process(delta:float) -> void:
    if animals != _drawn:
        _drawn = animals;
        for part in _layers:
            (_layers[part] as MultiMeshInstance3D).multimesh.instance_count = animals if is_complete() else 0;
    if animals <= 0 or not is_complete() or not _herd.visible:
        return;
    while young_ages.size() > animals:
        young_ages.pop_back();
    var dt:float = delta * minf(World.fx_speed(), 3.0);
    _t += dt;
    var r:Rect2 = Rect2(rect()).grow(-0.9);
    _sync_herd(r);
    var adults:int = animals - young_count();
    var warm:bool = grazing();
    var speed:float = SPEED[kind];
    var mature:float = animal()["mature"];
    for i in animals:
        var young:bool = i >= adults;
        var mother:int = (i - adults) % adults if young and adults > 0 else -1;
        var moving:bool = false;
        if mother >= 0:
            # a young one keeps close to its mother, running to catch up
            var near:Vector2 = _pos[mother] + Vector2(cos(i * 2.3), sin(i * 2.3)) * YOUNG_OFFSET[kind];
            _goal[i] = near;
            moving = _pos[i].distance_to(near) > 0.3;
            if moving:
                _step(i, speed * 1.5 * dt);
        elif _wait[i] > 0.0:
            _wait[i] -= dt;
        else:
            moving = _pos[i].distance_to(_goal[i]) > 0.08;
            if moving:
                _step(i, speed * dt);
            else:
                _wait[i] = _vis_rng.randf_range(GRAZE_FOR.x, GRAZE_FOR.y) * (1.0 if warm else 1.6);
                _goal[i] = _random_spot(r);
        _walk[i] = move_toward(_walk[i], 1.0 if moving else 0.0, dt * 2.5);
        _graze[i] = move_toward(_graze[i], 1.0 if (not moving and (warm or kind == &"chicken")) else 0.0, dt * 1.5);
        var ph:float = float(((i * 73856093) ^ (origin.x * 19349663)) & 255) / 255.0 * TAU;
        var bob:float = absf(sin(_t * 6.0 + ph)) * 0.012 * _walk[i];
        var size:float = 1.0;
        var coat:Color = Animals.coat(kind, i if mother < 0 else mother);
        if young:
            var grown:float = clampf(young_ages[i - adults] / mature, 0.0, 1.0);
            size = lerpf(YOUNG_SIZE, 1.0, grown);
            if kind == &"chicken":
                coat = CHICK_COLOUR.lerp(coat, grown);
        var xf:Transform3D = Transform3D(Basis(Vector3.UP, _yaw[i]).scaled(Vector3.ONE * size), Vector3(_pos[i].x, world.terrain.height_at(_pos[i].x, _pos[i].y) + bob * size, _pos[i].y));
        var timing:Color = Color(ph, _walk[i], _graze[i], 0.0);
        for part in _layers:
            var mm:MultiMesh = (_layers[part] as MultiMeshInstance3D).multimesh;
            mm.set_instance_transform(i, xf);
            mm.set_instance_color(i, Color.WHITE if (part == &"legs" and kind != &"cow") else coat);       # (a cow has legs of her own colour)
            mm.set_instance_custom_data(i, timing);

func _random_spot(r:Rect2) -> Vector2:
    return Vector2(r.position.x + _vis_rng.randf() * maxf(r.size.x, 0.1), r.position.y + _vis_rng.randf() * maxf(r.size.y, 0.1));

# Moves animal i up to `dist` metres toward its goal, turning to face the way it goes.
func _step(i:int, dist:float) -> void:
    var to:Vector2 = _goal[i] - _pos[i];
    var d:float = to.length();
    if d < 0.001:
        return;
    _pos[i] += to / d * minf(d, dist);
    _yaw[i] = lerp_angle(_yaw[i], atan2(-to.y, to.x), 0.12);          # (the models face +x)

# Keeps the per-animal state the size of the herd: a new one appears at a random spot (a newborn beside its mother).
func _sync_herd(r:Rect2) -> void:
    var adults:int = animals - young_count();
    while _pos.size() < animals:
        var i:int = _pos.size();
        var at:Vector2 = _random_spot(r);
        if i >= adults and adults > 0:
            at = _pos[(i - adults) % adults] + Vector2(0.3, 0.2) * YOUNG_OFFSET[kind] / 0.45;
        _pos.append(at);
        _goal.append(_random_spot(r));
        _wait.append(_vis_rng.randf_range(0.0, GRAZE_FOR.y));
        _yaw.append(_vis_rng.randf() * TAU);
        _walk.append(0.0);
        _graze.append(0.0);
    if _pos.size() > animals:
        _pos.resize(animals);
        _goal.resize(animals);
        _wait.resize(animals);
        _yaw.resize(animals);
        _walk.resize(animals);
        _graze.resize(animals);
