# ----------------------------------------------------------------
# Field
#     A crop field. Each cell is a plot that farmers plant, which grows
#     hourly based on temperature and moisture, and is harvested when
#     ripe. Harvests change soil fertility (crop rotation matters).
# ----------------------------------------------------------------
class_name Field extends Building;

# FROZEN: a growing crop that a frost has stopped. It can still be harvested for part of its yield for a day
# (SALVAGE_HOURS), then it is lost. Added last so saved plot states keep their numbers.
enum Plot { FALLOW, PLANTED, RIPE, DEAD, FROZEN };

const ACTION_HOURS      :Dictionary = {&"plant": 0.4, &"harvest": 0.5, &"clear": 0.25};
const ACTION_PRIORITY   :Dictionary = {&"harvest": 0, &"clear": 1, &"plant": 2};     # ripe crops are gathered before anything is sown
const SALVAGE_HOURS     :float = 24.0;     # a frozen crop can be harvested this long before it is lost
const SALVAGE_MIN_GROWTH:float = 0.25;     # a crop grown less than this is not worth harvesting (frozen ones are cleared)
const EARLY_SHARE       :float = 0.7;      # an early harvest gives the share grown, times this
const FROZEN_SHARE      :float = 0.7;      # a frost-damaged harvest gives the share grown, times this
const NEAR_WATER_RANGE  :int = 4;
const FALLOW_RECOVERY   :float = 0.01;     # fertility per day when unplanted

var crop_id     :StringName = &"wheat";
var plot_state  :PackedByteArray;
var plot_crop   :Array[StringName] = [];    # what was planted (crop may change mid-season)
var growth      :PackedFloat32Array;
var frozen_hours :PackedFloat32Array;       # hours each FROZEN plot has been frozen
var harvest_early:bool = false;             # the player ordered every growing plot harvested now (see Field.apply)
var cuts        :PackedByteArray;           # harvests taken from the current sowing (multi-harvest crops)
var moisture    :PackedFloat32Array;
var near_water  :PackedByteArray;
var reserved    :Array = [];                # Pawn or null per plot
var _layers     :Dictionary = {};           # plant shape -> MultiMeshInstance3D drawing those plots
var _visual_dirty:bool = true;

func setup(w:World, id:StringName, o:Vector2i, s:Vector2i) -> void:
    super.setup(w, id, o, s);
    if not w.seeds.has(crop_id):
        crop_id = w.seeds.first_known();       # a new field starts with a crop the colony has seeds for
    # crops are placed in world space, so keep the node at the origin
    position = Vector3.ZERO;
    var n:int = plot_count();
    plot_state.resize(n);
    growth.resize(n);
    cuts.resize(n);
    frozen_hours.resize(n);
    moisture.resize(n);
    near_water.resize(n);
    reserved.resize(n);
    plot_crop.resize(n);
    for i in n:
        moisture[i] = 0.5;
        near_water[i] = 1 if _is_near_water(plot_cell(i)) else 0;
    _fence = Fence.new(self, &"wood", 1);
    add_child(_fence);
    for shape in CropMeshes.SHAPES:
        var mm:MultiMesh = MultiMesh.new();
        mm.transform_format = MultiMesh.TRANSFORM_3D;
        mm.use_colors = true;
        mm.mesh = CropMeshes.mesh_for(shape);
        var mmi:MultiMeshInstance3D = MultiMeshInstance3D.new();
        mmi.multimesh = mm;
        add_child(mmi);
        _layers[shape] = mmi;

func _process(_delta:float) -> void:
    if _visual_dirty:
        _visual_dirty = false;
        _rebuild_crops();

# The def's work value is for the default 6x6 field; bigger fields take proportionally longer to till.
func work_required() -> float:
    return def["work"] * plot_count() / 36.0;

func plot_count() -> int:
    return size.x * size.y;

@warning_ignore("integer_division")
func plot_cell(i:int) -> Vector2i:
    return origin + Vector2i(i % size.x, i / size.x);

func crop() -> Dictionary:
    return Defs.CROPS[crop_id];

# Returns false (and changes nothing) for a crop the colony has no seeds for.
func set_crop(id:StringName) -> bool:
    if not Defs.CROPS.has(id) or not world.seeds.has(id):
        return false;
    crop_id = id;
    return true;

func fertility(i:int) -> float:
    return world.soil_fertility[world.terrain.index(plot_cell(i))];

func _set_fertility(i:int, v:float) -> void:
    world.soil_fertility[world.terrain.index(plot_cell(i))] = clampf(v, 0.0, 1.0);

func can_plant() -> bool:
    return Weather.can_sow(crop());

func to_dict() -> Dictionary:
    var d:Dictionary = super.to_dict();
    d["crop_id"] = crop_id;
    d["plot_state"] = plot_state;
    d["plot_crop"] = Array(plot_crop);
    d["growth"] = growth;
    d["cuts"] = cuts;
    d["frozen_hours"] = frozen_hours;
    d["harvest_early"] = harvest_early;
    d["moisture"] = moisture;
    return d;

func restore_dict(d:Dictionary) -> void:
    super.restore_dict(d);
    crop_id = d["crop_id"];
    plot_state = d["plot_state"];
    for i in plot_count():
        plot_crop[i] = d["plot_crop"][i];
    growth = d["growth"];
    cuts = d.get("cuts", PackedByteArray());
    cuts.resize(plot_count());
    frozen_hours = d.get("frozen_hours", PackedFloat32Array());
    frozen_hours.resize(plot_count());
    harvest_early = d.get("harvest_early", false);
    moisture = d["moisture"];
    _visual_dirty = true;

# --------------------------------
# Work for farmers

# Returns {"index": int, "action": StringName, "rank": float} for the most urgent open plot (harvest, then clearing,
# then planting, the closest first within each), or {}. A lower rank is more urgent, across fields too.
# has_room(item) -> bool, when given, stops harvesting crops that nothing could store.
func find_work(from:Vector2i, only_action:StringName = &"", has_room:Callable = Callable()) -> Dictionary:
    if state != State.COMPLETE:
        return {};
    var plantable:bool = can_plant() and not harvest_early;
    var best:int = -1;
    var best_action:StringName = &"";
    var best_d:float = INF;
    for i in plot_count():
        if reserved[i] != null:
            continue;
        var action:StringName = &"";
        match plot_state[i]:
            Plot.RIPE:
                if has_room.is_valid() and not has_room.call(Defs.CROPS[plot_crop[i]]["item"]):
                    continue;
                action = &"harvest";
            Plot.PLANTED:
                if harvest_early and growth[i] >= SALVAGE_MIN_GROWTH and (not has_room.is_valid() or has_room.call(Defs.CROPS[plot_crop[i]]["item"])):
                    action = &"harvest";
            Plot.FROZEN:
                if growth[i] < SALVAGE_MIN_GROWTH:
                    action = &"clear";
                elif not has_room.is_valid() or has_room.call(Defs.CROPS[plot_crop[i]]["item"]):
                    action = &"harvest";
            Plot.DEAD:
                action = &"clear";
            Plot.FALLOW:
                if plantable:
                    action = &"plant";
        if action == &"" or (only_action != &"" and action != only_action):
            continue;
        var d:float = ACTION_PRIORITY[action] * 1.0e6 + Vector2(plot_cell(i) - from).length_squared();
        if plot_state[i] == Plot.FROZEN:
            d -= 2.0e6;       # the clock is running on a frozen crop: before anything else
        if d < best_d:
            best_d = d;
            best = i;
            best_action = action;
    if best < 0:
        return {};
    return {"index": best, "action": best_action, "rank": best_d};

# Carries out a farming action; harvest output goes into the pawn's hands.
func apply(i:int, action:StringName, pawn:Pawn) -> void:
    match action:
        &"plant":
            if plot_state[i] == Plot.FALLOW:
                plot_state[i] = Plot.PLANTED;
                plot_crop[i] = crop_id;
                growth[i] = 0.0;
                cuts[i] = 0;
        &"harvest":
            var st:int = plot_state[i];
            if st == Plot.RIPE or st == Plot.FROZEN or (st == Plot.PLANTED and harvest_early and growth[i] >= SALVAGE_MIN_GROWTH):
                var c:Dictionary = Defs.CROPS[plot_crop[i]];
                # ripe: all of it; early or frost-damaged: the share that has grown, less a little
                var share:float = 1.0 if st == Plot.RIPE else minf(1.0, growth[i]) * (FROZEN_SHARE if st == Plot.FROZEN else EARLY_SHARE);
                var amount:int = maxi(1, roundi(c["yield"] * lerpf(0.4, 1.3, fertility(i)) * share));
                pawn.add_carry(c["item"], amount);
                _set_fertility(i, fertility(i) + c["fertility"] * share);
                cuts[i] += 1;
                if st == Plot.RIPE and cuts[i] < c.get("harvests", 1):
                    plot_state[i] = Plot.PLANTED;       # keeps producing: ripe again after regrow_days
                    growth[i] = 1.0 - c["regrow_days"] / c["grow_days"];
                else:
                    plot_state[i] = Plot.FALLOW;
                    growth[i] = 0.0;
                    cuts[i] = 0;
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
    var frozen:int = 0;
    for i in plot_count():
        # soil moisture: rain wets, warmth dries, nearby water keeps it up
        var m:float = moisture[i];
        var dry:float = 1.0 - Weather.intensity;
        m += 0.04 * Weather.intensity - (0.003 + maxf(0.0, temp) * 0.0006) * dry;
        if near_water[i] == 1:
            m = maxf(m, 0.45);
        moisture[i] = clampf(m, 0.0, 1.0);

        match plot_state[i]:
            Plot.PLANTED:
                var c:Dictionary = Defs.CROPS[plot_crop[i]];
                if temp < c["frost_temp"]:
                    plot_state[i] = Plot.FROZEN if growth[i] >= SALVAGE_MIN_GROWTH else Plot.DEAD;
                    frozen_hours[i] = 0.0;
                    if plot_state[i] == Plot.FROZEN:
                        frozen += 1;
                    else:
                        killed += 1;
                    continue;
                growth[i] += _growth_rate(c, temp, moisture[i]);
                if growth[i] >= 1.0:
                    plot_state[i] = Plot.RIPE;
            Plot.FROZEN:
                frozen_hours[i] += 1.0;
                if frozen_hours[i] >= SALVAGE_HOURS:
                    plot_state[i] = Plot.DEAD;
                    killed += 1;
            Plot.RIPE:
                # ripe crops left out in a hard freeze rot
                if temp < Defs.CROPS[plot_crop[i]]["frost_temp"] - 4.0:
                    plot_state[i] = Plot.DEAD;
                    killed += 1;
    if harvest_early and not _has_growing_plots():
        harvest_early = false;       # everything has been taken: sowing can start again
    if frozen > 0:
        world.notify("Frost has stopped %d crop plots in a field. Harvest them within a day to save part of the crop." % frozen);
    if killed > 0:
        world.notify("Frost killed %d crop plots in a field." % killed);
    _visual_dirty = true;

func _has_growing_plots() -> bool:
    for i in plot_count():
        if plot_state[i] == Plot.PLANTED and growth[i] >= SALVAGE_MIN_GROWTH:
            return true;
    return false;

func on_day() -> void:
    for i in plot_count():
        if plot_state[i] == Plot.FALLOW:
            _set_fertility(i, fertility(i) + FALLOW_RECOVERY);

func on_terrain_changed() -> void:
    super.on_terrain_changed();
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

# Farmer positions this field counts for in the Professions panel.
func farmer_positions() -> int:
    return ceili(float(plot_count()) / Defs.PLOTS_PER_FARMER);

func info_text() -> String:
    if state != State.COMPLETE:
        return super.info_text();
    var counts:Array[int] = [0, 0, 0, 0, 0];
    var fert:float = 0.0;
    var moist:float = 0.0;
    for i in plot_count():
        counts[plot_state[i]] += 1;
        fert += fertility(i);
        moist += moisture[i];
    var n:float = plot_count();
    var c:Dictionary = crop();
    var s:String = "Crop: %s\n" % c["name"];
    s += "Fallow %d, Growing %d, Ripe %d, Dead %d, Frozen %d\n" % counts;
    if harvest_early:
        s += "Harvesting early: growing plots are taken for part of the crop, and nothing is sown meanwhile.\n";
    if counts[Plot.FROZEN] > 0:
        s += "Frozen plots can be harvested for part of the crop for a day, then they are lost.\n";
    s += "Needs %d farmer%s (one per %d plots)\n" % [farmer_positions(), "" if farmer_positions() == 1 else "s", Defs.PLOTS_PER_FARMER];
    s += "Soil fertility: %d%%\n" % roundi(fert / n * 100.0);
    s += "Soil moisture: %d%%\n" % roundi(moist / n * 100.0);
    s += "Sows %s.\n" % Defs.sow_text(crop_id);
    var why:String = Weather.sow_block_reason(c);
    s += "Sowing now: %s\n" % ("yes" if why == "" else "no, " + why);
    if c.has("harvests"):
        s += "Gives up to %d cuttings from one sowing.\n" % c["harvests"];
    return s;

func _rebuild_crops() -> void:
    var by_shape:Dictionary = {};
    for shape in CropMeshes.SHAPES:
        by_shape[shape] = [];
    for i in plot_count():
        if plot_state[i] != Plot.FALLOW:
            by_shape[CropMeshes.shape_of(plot_crop[i])].append(i);
    for shape in CropMeshes.SHAPES:
        var list:Array = by_shape[shape];
        var mm:MultiMesh = (_layers[shape] as MultiMeshInstance3D).multimesh;
        mm.instance_count = list.size();
        for j in list.size():
            var i:int = list[j];
            var c:Dictionary = Defs.CROPS[plot_crop[i]];
            var h:float;           # height and width of the plant as a share of its full size
            var wide:float;
            var col:Color;
            match plot_state[i]:
                Plot.PLANTED:
                    h = 0.2 + growth[i] * 0.8;
                    wide = 0.45 + growth[i] * 0.55;
                    col = Color(0.3, 0.6, 0.2).lerp(c["color"], growth[i] * growth[i]);
                Plot.RIPE:
                    h = 1.0;
                    wide = 1.0;
                    col = c["color"];
                Plot.FROZEN:
                    h = 0.2 + growth[i] * 0.8;
                    wide = 0.45 + growth[i] * 0.55;
                    col = Color(0.72, 0.84, 0.9);       # white with frost
                _:
                    h = 0.3;
                    wide = 0.8;
                    col = Color(0.4, 0.32, 0.22);
            var cell:Vector2i = plot_cell(i);
            var yaw:float = float(((cell.x * 73856093) ^ (cell.y * 19349663)) & 1023) / 1023.0 * TAU;       # no two plots look alike
            var p:Vector3 = world.terrain.cell_center(cell);
            mm.set_instance_transform(j, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(wide, h, wide)), p));
            mm.set_instance_color(j, col);
