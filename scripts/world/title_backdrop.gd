# ----------------------------------------------------------------
# TitleBackdrop
#     The picture behind the title screen: a frozen mock town (a Town
#     Hall, houses with lit windows, stores, workshops, a school,
#     wells, fields and roads) on a random map in a random season, seen
#     from a low camera that drifts slowly (TitleCamera). No citizens
#     and nothing in the town moves: the clock is stopped and the
#     World runs without a HUD or tools. Called by World._ready when
#     World.backdrop is set. Static functions only.
# ----------------------------------------------------------------
class_name TitleBackdrop extends RefCounted;

const RADIUS        :int = 19;          # the town fills about this many cells around the middle
const TOWN          :Array[StringName] = [
    &"house", &"granary", &"house", &"well", &"woodcutter", &"house", &"stockpile", &"house", &"school", &"house",
    &"forager", &"house", &"blacksmith", &"house", &"well", &"house", &"graveyard",
    &"trading_post", &"apiary", &"tailor", &"still", &"pottery", &"house", &"pasture", &"orchard",
];
const CAMERA_DISTANCE:float = 38.0;
const CAMERA_ELEVATION:float = 26.0;    # degrees above the ground, low enough to see the fronts of the buildings

static func build(world:World, start:Vector2i) -> void:
    var rng:RandomNumberGenerator = world.rng;
    world._clear_nodes(start, RADIUS + 3);
    world.town_hall = world.place_building(&"town_hall", start - Vector2i(2, 2), Vector2i(4, 4), true);
    var placed:Array[Building] = [world.town_hall];
    for id in TOWN:
        var size:Vector2i = Vector2i(4, 3) if id == &"graveyard" else Defs.BUILDINGS[id]["size"];
        var spot:Vector2i = _spot(world, start, size, 0, RADIUS, rng);
        if spot.x >= 0:
            var b:Building = world.place_building(id, spot, size, true);
            placed.append(b);
            if b is Pasture:
                (b as Pasture).set_kind([&"sheep", &"cow", &"chicken"][rng.randi() % 3]);
                (b as Pasture).add_animals(4);
            elif b is Field:
                _plant(b as Field, rng);
    for i in 3:
        var size:Vector2i = Vector2i(rng.randi_range(6, 9), rng.randi_range(5, 7));
        var spot:Vector2i = _spot(world, start, size, 11, RADIUS + 8, rng);
        if spot.x >= 0:
            _plant(world.place_building(&"field", spot, size, true) as Field, rng);
    _water_features(world, start);
    var cold:bool = Weather.temperature < Defs.HEATING_BELOW + 3.0;
    for b in placed:
        if b.def.has("beds"):
            b.windows_lit_always = true;
            b.update_windows();
            if cold:       # chimneys smoke when it is cold enough to heat: grey from firewood, now and then black from coal
                b.smoke_always = true;
                b.fuel = 10;
                b.fuel_coal = 10 if rng.randf() < 0.2 else 0;
                b.update_smoke();
    for b in placed:
        _lay_road(world, _door(b), _door(world.town_hall));
    var season:int = GameClock.season();
    world.terrain.set_season(Climate.look(season));
    world.renderer.update_foliage();
    world.renderer.mark_dirty();
    _place_camera(world, start, rng);

# A fishing hut on the shore and a bridge over the river, if there is water near the town.
static func _water_features(world:World, start:Vector2i) -> void:
    var hut:Vector2i = Vector2i(-1, -1);
    var hut_size:Vector2i = Vector2i.ZERO;
    var hut_facing:int = 0;
    var best:float = INF;
    for facing in 4:
        var size:Vector2i = Vector2i(3, 4) if facing % 2 == 0 else Vector2i(4, 3);
        for z in range(start.y - 34, start.y + 34):
            for x in range(start.x - 34, start.x + 34):
                var o:Vector2i = Vector2i(x, z);
                var d:float = Vector2(o - start).length();
                if d < best and d > RADIUS - 6 and world.can_place(&"fishing_hut", o, size, false, facing) == "":
                    hut = o;
                    hut_size = size;
                    hut_facing = facing;
                    best = d;
    if hut.x >= 0:
        world.place_building(&"fishing_hut", hut, hut_size, true, false, hut_facing);
    var span:Rect2i = _bridge_span(world, start);
    if span.has_area():
        world.place_building(&"bridge", span.position, span.size, true);

# A 1-wide strip across the water (3 to 12 cells of it) with dry land at both ends, nearest the town, along either axis.
static func _bridge_span(world:World, start:Vector2i) -> Rect2i:
    var t:Terrain = world.terrain;
    var best:Rect2i = Rect2i();
    var best_d:float = INF;
    for flip in [false, true]:
        for z in range(maxi(4, start.y - 40), mini(Terrain.SIZE - 4, start.y + 40)):
            var x:int = maxi(4, start.x - 40);
            while x < mini(Terrain.SIZE - 6, start.x + 40):
                var a:Vector2i = Vector2i(z, x) if flip else Vector2i(x, z);
                var b:Vector2i = Vector2i(z, x + 1) if flip else Vector2i(x + 1, z);
                if not t.is_water(a) and t.is_water(b):
                    var e:int = x + 1;
                    while e < Terrain.SIZE - 4 and t.is_water(Vector2i(z, e) if flip else Vector2i(e, z)):
                        e += 1;
                    var run:int = e - x - 1;
                    var far:Vector2i = Vector2i(z, e) if flip else Vector2i(e, z);
                    if run >= 3 and run <= 12 and not t.is_water(far) and t.cell_slope(a) < 1.2 and t.cell_slope(far) < 1.2:
                        var r:Rect2i = Rect2i(Vector2i(z, x), Vector2i(1, e - x + 1)) if flip else Rect2i(Vector2i(x, z), Vector2i(e - x + 1, 1));
                        var d:float = Vector2(r.get_center() - start).length();
                        if d < best_d and world.can_place(&"bridge", r.position, r.size) == "":
                            best = r;
                            best_d = d;
                    x = e;
                else:
                    x += 1;
    return best;

# The cell just outside the south face of a building, where its door is.
static func _door(b:Building) -> Vector2i:
    return Vector2i(b.origin.x + b.size.x / 2, b.origin.y + b.size.y);

# A free spot for a footprint with a cell of space around it, between min_r and max_r cells from the middle, found
# among a few hundred random candidates and taken nearest-first so the town stays compact. (-1, -1) if none.
static func _spot(world:World, middle:Vector2i, size:Vector2i, min_r:int, max_r:int, rng:RandomNumberGenerator) -> Vector2i:
    var candidates:Array = [];
    for z in range(-max_r, max_r + 1):
        for x in range(-max_r, max_r + 1):
            var d:float = Vector2(x, z).length();
            if d >= min_r and d <= max_r:
                candidates.append([d + rng.randf_range(0.0, 5.0), middle + Vector2i(x, z)]);
    candidates.sort_custom(func(a:Array, b:Array) -> bool: return a[0] < b[0]);
    for c in candidates:
        var o:Vector2i = c[1];
        if world.can_place(&"house", o, size) == "" and _roomy(world, Rect2i(o, size)):
            return o;
    return Vector2i(-1, -1);

# No building within a cell of the rect (so there is room for a road between neighbours).
static func _roomy(world:World, r:Rect2i) -> bool:
    var g:Rect2i = r.grow(1).intersection(Rect2i(0, 0, Terrain.SIZE, Terrain.SIZE));
    for z in range(g.position.y, g.end.y):
        for x in range(g.position.x, g.end.x):
            if world.occupant[world.idx(Vector2i(x, z))] != null:
                return false;
    return true;

# A planted field: one crop, plots at every stage from just sown to ripe (bare ground in winter).
static func _plant(f:Field, rng:RandomNumberGenerator) -> void:
    if GameClock.season() == GameClock.Season.WINTER:
        return;
    var orchard:bool = f.is_orchard();
    var crops:Array = Defs.CROPS.keys().filter(func(id:StringName) -> bool: return Defs.CROPS[id].get("tree", false) == orchard);
    f.crop_id = crops[rng.randi() % crops.size()];
    for i in f.plot_count():
        if rng.randf() < 0.12:
            continue;       # a few bare plots
        f.plot_crop[i] = f.crop_id;
        if rng.randf() < 0.35:
            f.plot_state[i] = Field.Plot.RIPE;
        else:
            f.plot_state[i] = Field.Plot.PLANTED;
            f.growth[i] = rng.randf_range(0.3, 0.95);
    f._visual_dirty = true;

# An L-shaped dirt road (along x, then z) between two cells; cells that are taken are skipped.
static func _lay_road(world:World, from:Vector2i, to:Vector2i) -> void:
    var c:Vector2i = from;
    while c.x != to.x:
        world.set_road(c, true);
        c.x += 1 if to.x > c.x else -1;
    while c.y != to.y:
        world.set_road(c, true);
        c.y += 1 if to.y > c.y else -1;
    world.set_road(c, true);

# A low camera that drifts slowly back and forth around the town (TitleCamera), on a side where the map's edge stays
# out of the picture for the whole swing.
static func _place_camera(world:World, start:Vector2i, rng:RandomNumberGenerator) -> void:
    var target:Vector3 = world.terrain.cell_center(start) + Vector3(rng.randf_range(-3.0, 3.0), 1.5, rng.randf_range(-3.0, 3.0));
    var cam:TitleCamera = TitleCamera.new();
    var sides:Array[float] = [];
    for i in 8:
        var yaw:float = i * TAU / 8.0 + rng.randf_range(-0.2, 0.2);
        var ok:bool = true;
        for swing in [-cam.sweep, 0.0, cam.sweep]:
            var away:Vector3 = -Vector3(sin(yaw + swing), 0.0, cos(yaw + swing)) * 55.0;       # what the camera looks toward
            var far:Vector3 = target + away;
            ok = ok and far.x > 6.0 and far.x < Terrain.SIZE - 6.0 and far.z > 6.0 and far.z < Terrain.SIZE - 6.0;
        if ok:
            sides.append(yaw);
    if sides.is_empty():
        cam.sweep = 0.0;
    cam.base_yaw = sides[rng.randi() % sides.size()] if not sides.is_empty() else rng.randf() * TAU;
    cam.target = target;
    cam.distance = CAMERA_DISTANCE;
    cam.elevation = CAMERA_ELEVATION;
    cam.min_height = func(p:Vector3) -> float: return world.terrain.height_at(clampf(p.x, 0.0, Terrain.SIZE), clampf(p.z, 0.0, Terrain.SIZE)) + 4.0;
    cam.fov = 52.0;
    cam.far = 700.0;
    cam.h_offset = -7.0;        # slides the town to the right of the middle, clear of the menu
    world.add_child(cam);
    cam.apply();
    cam.make_current();
    var host:Node3D = Node3D.new();       # rain and snow fall over the town, not with the camera's tilt
    host.name = "WeatherHost";
    world.add_child(host);
    host.global_position = Vector3(target.x, 0.0, target.z);
    world.visuals.setup_weather_fx(host);
