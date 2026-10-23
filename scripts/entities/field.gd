# ----------------------------------------------------------------
# Field
#     A crop field. Each cell is a plot that farmers plant, which grows
#     hourly based on temperature and moisture, and is harvested when
#     ripe. Harvests change soil fertility (crop rotation matters).
# ----------------------------------------------------------------
class_name Field extends Building;

enum Plot { FALLOW, PLANTED, RIPE, DEAD };

const ACTION_HOURS      :Dictionary = {&"plant": 0.4, &"harvest": 0.5, &"clear": 0.25};
const NEAR_WATER_RANGE  :int = 4;
const FALLOW_RECOVERY   :float = 0.01;     # fertility per day when unplanted

var crop_id     :StringName = &"wheat";
var plot_state  :PackedByteArray;
var plot_crop   :Array[StringName] = [];    # what was planted (crop may change mid-season)
var growth      :PackedFloat32Array;
var moisture    :PackedFloat32Array;
var near_water  :PackedByteArray;
var reserved    :Array = [];                # Pawn or null per plot
var _crops_mmi  :MultiMeshInstance3D;
var _visual_dirty:bool = true;

func setup(w:World, id:StringName, o:Vector2i, s:Vector2i) -> void:
    super.setup(w, id, o, s);
    # crops are placed in world space, so keep the node at the origin
    position = Vector3.ZERO;
    var n:int = plot_count();
    plot_state.resize(n);
    growth.resize(n);
    moisture.resize(n);
    near_water.resize(n);
    reserved.resize(n);
    plot_crop.resize(n);
    for i in n:
        moisture[i] = 0.5;
        near_water[i] = 1 if _is_near_water(plot_cell(i)) else 0;
    var mm:MultiMesh = MultiMesh.new();
    mm.transform_format = MultiMesh.TRANSFORM_3D;
    mm.use_colors = true;
    var box:BoxMesh = BoxMesh.new();
    box.size = Vector3(0.75, 1.0, 0.75);
    mm.mesh = box;
    var mat:StandardMaterial3D = StandardMaterial3D.new();
    mat.vertex_color_use_as_albedo = true;
    mat.vertex_color_is_srgb = true;
    mat.roughness = 1.0;
    _crops_mmi = MultiMeshInstance3D.new();
    _crops_mmi.multimesh = mm;
    _crops_mmi.material_override = mat;
    add_child(_crops_mmi);

func _process(_delta:float) -> void:
    if _visual_dirty:
        _visual_dirty = false;
        _rebuild_crops();

func plot_count() -> int:
    return size.x * size.y;

@warning_ignore("integer_division")
func plot_cell(i:int) -> Vector2i:
    return origin + Vector2i(i % size.x, i / size.x);

func crop() -> Dictionary:
    return Defs.CROPS[crop_id];

func cycle_crop() -> void:
    var keys:Array = Defs.CROPS.keys();
    crop_id = keys[(keys.find(crop_id) + 1) % keys.size()];

func fertility(i:int) -> float:
    return world.soil_fertility[world.terrain.index(plot_cell(i))];

func _set_fertility(i:int, v:float) -> void:
    world.soil_fertility[world.terrain.index(plot_cell(i))] = clampf(v, 0.0, 1.0);

func can_plant() -> bool:
    var s:int = GameClock.season();
    if s != GameClock.Season.SPRING and s != GameClock.Season.SUMMER:
        return false;
    return Weather.mean_temperature() >= crop()["min_temp"];

# --------------------------------
# Work for farmers

# Returns {"index": int, "action": StringName} for the closest open plot, or {}.
func find_work(from:Vector2i, only_action:StringName = &"") -> Dictionary:
    if state != State.COMPLETE:
        return {};
    var plantable:bool = can_plant();
    var best:int = -1;
    var best_action:StringName = &"";
    var best_d:float = INF;
    for i in plot_count():
        if reserved[i] != null:
            continue;
        var action:StringName = &"";
        match plot_state[i]:
            Plot.RIPE:
                action = &"harvest";
            Plot.DEAD:
                action = &"clear";
            Plot.FALLOW:
                if plantable:
                    action = &"plant";
        if action == &"" or (only_action != &"" and action != only_action):
            continue;
        var d:float = Vector2(plot_cell(i) - from).length_squared();
        if d < best_d:
            best_d = d;
            best = i;
            best_action = action;
    if best < 0:
        return {};
    return {"index": best, "action": best_action};

# Carries out a farming action; harvest output goes into the pawn's hands.
func apply(i:int, action:StringName, pawn:Pawn) -> void:
    match action:
        &"plant":
            if plot_state[i] == Plot.FALLOW:
                plot_state[i] = Plot.PLANTED;
                plot_crop[i] = crop_id;
                growth[i] = 0.0;
        &"harvest":
            if plot_state[i] == Plot.RIPE:
                var c:Dictionary = Defs.CROPS[plot_crop[i]];
                var amount:int = maxi(1, roundi(c["yield"] * lerpf(0.4, 1.3, fertility(i))));
                pawn.add_carry(c["item"], amount);
                _set_fertility(i, fertility(i) + c["fertility"]);
                plot_state[i] = Plot.FALLOW;
                growth[i] = 0.0;
        &"clear":
            plot_state[i] = Plot.FALLOW;
            growth[i] = 0.0;
    _visual_dirty = true;

# --------------------------------
# Simulation

func on_hour() -> void:
    if state != State.COMPLETE:
        return;
    var temp:float = Weather.temperature;
    var killed:int = 0;
    for i in plot_count():
        # soil moisture: rain wets, warmth dries, nearby water keeps it up
        var m:float = moisture[i];
        if Weather.is_raining:
            m += 0.04;
        else:
            m -= 0.003 + maxf(0.0, temp) * 0.0006;
        if near_water[i] == 1:
            m = maxf(m, 0.45);
        moisture[i] = clampf(m, 0.0, 1.0);

        match plot_state[i]:
            Plot.PLANTED:
                var c:Dictionary = Defs.CROPS[plot_crop[i]];
                if temp < c["frost_temp"]:
                    plot_state[i] = Plot.DEAD;
                    killed += 1;
                    continue;
                growth[i] += _growth_rate(c, temp, moisture[i]);
                if growth[i] >= 1.0:
                    plot_state[i] = Plot.RIPE;
            Plot.RIPE:
                # ripe crops left out in a hard freeze rot
                if temp < Defs.CROPS[plot_crop[i]]["frost_temp"] - 4.0:
                    plot_state[i] = Plot.DEAD;
                    killed += 1;
    if killed > 0:
        world.notify("Frost killed %d crop plots in a field." % killed);
    _visual_dirty = true;

func on_day() -> void:
    for i in plot_count():
        if plot_state[i] == Plot.FALLOW:
            _set_fertility(i, fertility(i) + FALLOW_RECOVERY);

func on_terrain_changed() -> void:
    _visual_dirty = true;

# Growth per hour (1.0 = ripe).
func _growth_rate(c:Dictionary, temp:float, m:float) -> float:
    if temp < c["min_temp"]:
        return 0.0;
    var temp_f:float = clampf((temp - c["min_temp"]) / 8.0, 0.3, 1.0);
    var water_f:float = clampf(0.3 + m * 1.2, 0.3, 1.0);
    return temp_f * water_f / (c["grow_days"] * GameClock.HOURS_PER_DAY);

func _is_near_water(c:Vector2i) -> bool:
    for dz in range(-NEAR_WATER_RANGE, NEAR_WATER_RANGE + 1):
        for dx in range(-NEAR_WATER_RANGE, NEAR_WATER_RANGE + 1):
            var n:Vector2i = c + Vector2i(dx, dz);
            if world.terrain.in_bounds(n) and world.terrain.is_water(n):
                return true;
    return false;

# --------------------------------
# Info / visuals

func info_text() -> String:
    if state != State.COMPLETE:
        return super.info_text();
    var counts:Array[int] = [0, 0, 0, 0];
    var fert:float = 0.0;
    var moist:float = 0.0;
    for i in plot_count():
        counts[plot_state[i]] += 1;
        fert += fertility(i);
        moist += moisture[i];
    var n:float = plot_count();
    var c:Dictionary = crop();
    var s:String = "Crop: %s\n" % c["name"];
    s += "Fallow %d, Growing %d, Ripe %d, Dead %d\n" % counts;
    s += "Soil fertility: %d%%\n" % roundi(fert / n * 100.0);
    s += "Soil moisture: %d%%\n" % roundi(moist / n * 100.0);
    s += "Plants above %d C in spring/summer; frost below %d C kills it.\n" % [c["min_temp"], c["frost_temp"]];
    if not can_plant() and counts[Plot.FALLOW] > 0:
        s += "Not planting season or too cold.\n";
    return s;

func _rebuild_crops() -> void:
    var mm:MultiMesh = _crops_mmi.multimesh;
    var list:Array[int] = [];
    for i in plot_count():
        if plot_state[i] != Plot.FALLOW:
            list.append(i);
    mm.instance_count = list.size();
    for j in list.size():
        var i:int = list[j];
        var c:Dictionary = Defs.CROPS[plot_crop[i]];
        var h:float;
        var col:Color;
        match plot_state[i]:
            Plot.PLANTED:
                h = 0.08 + growth[i] * 0.6;
                col = Color(0.3, 0.6, 0.2).lerp(c["color"], growth[i] * growth[i]);
            Plot.RIPE:
                h = 0.75;
                col = c["color"];
            _:
                h = 0.15;
                col = Color(0.35, 0.28, 0.2);
        var p:Vector3 = world.terrain.cell_center(plot_cell(i));
        p.y += h * 0.5;
        mm.set_instance_transform(j, Transform3D(Basis().scaled(Vector3(1.0, h, 1.0)), p));
        mm.set_instance_color(j, col);
