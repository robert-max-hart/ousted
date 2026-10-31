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

const ACTION_HOURS      :Dictionary = {&"plant": 0.4, &"harvest": 0.5, &"clear": 0.25, &"water": 0.3, &"treat": 0.3, &"manure": 0.35};
const ACTION_PRIORITY   :Dictionary = {&"harvest": 0, &"clear": 1, &"treat": 2, &"water": 3, &"manure": 4, &"plant": 5};
const MANURE_BELOW      :float = 0.7;      # a fallow plot poorer than this gets manure before it is sown, when there is any
const MANURE_BOOST      :float = 0.3;      # what one load adds to the plot and the eight around it     # ripe crops are gathered before anything is watered or sown
const IRRIGATED_MOISTURE:float = 0.65;  # a plot beside a flowing channel never dries below this
const PEST_MIN_TEMP     :float = 6.0;      # pests are about only above this (a hard frost clears them)
const PEST_OUTBREAK     :float = 0.05;     # chance a day for a field with something growing, in the warm months
const PEST_SAME_CROP    :float = 0.5;      # outbreak chance grows this much for each other field growing the same crop nearby
const PEST_NEARBY       :float = 20.0;     # ... within this many cells
const PEST_GROWTH       :float = 0.12;     # an infested plot gets this much worse a day (at 1.0 the crop is eaten)
const PEST_SPREAD       :float = 0.25;     # chance a day an infested plot infects each neighbour
const PEST_GROWTH_COST  :float = 0.6;      # growth slows by this share at full infestation
const PEST_YIELD_COST   :float = 0.7;      # and so does the harvest
const PEST_TREAT_ABOVE  :float = 0.25;     # farmers pick pests off plots at least this infested
const SCARECROW_OUTBREAK:float = 0.25;     # what a scarecrow leaves of the outbreak chance, the spread and the growth
const SCARECROW_SPREAD  :float = 0.35;
const SCARECROW_GROWTH  :float = 0.5;
const WATER_BELOW       :float = 0.3;      # a growing plot drier than this wants a bucket
const BUCKET_MOISTURE   :float = 0.55;     # what a bucket sets a plot (and the plots around it) to, at least
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
var pests       :PackedFloat32Array;        # 0..1 infestation per plot
var irrigated   :PackedByteArray;          # 1 where a flowing channel is within reach (derived, not saved)
var _irrigation_seen:int = -1;
var reserved    :Array = [];                # Pawn or null per plot
var _crop_layers:Dictionary = {};           # model key (see CropMeshes.crop_key) -> MultiMeshInstance3D drawing those plots
var _layers_low :bool = false;              # which model set the layers were made from
var _tree_layers:Dictionary = {};           # orchard crop -> {part -> MultiMeshInstance3D}, made when a plot of that tree first shows
var _visual_dirty:bool = true;
var _scarecrows :Node3D;
var _scarecrows_for:Rect2i = Rect2i();      # the footprint they were built for

# One scarecrow for every 6x6 stretch of the field: a pole, a crossbar, a sack head and a hat.
func _build_scarecrows() -> void:
    _scarecrows_for = rect();
    if _scarecrows != null:
        _scarecrows.queue_free();
    _scarecrows = Node3D.new();
    add_child(_scarecrows);
    var wood:StandardMaterial3D = StandardMaterial3D.new();
    wood.albedo_color = Color(0.4, 0.29, 0.18);
    var sack:StandardMaterial3D = StandardMaterial3D.new();
    sack.albedo_color = Color(0.75, 0.66, 0.45);
    var hat:StandardMaterial3D = StandardMaterial3D.new();
    hat.albedo_color = Color(0.3, 0.22, 0.14);
    for bz in range(0, size.y, 6):
        for bx in range(0, size.x, 6):
            var c:Vector2i = origin + Vector2i(clampi(bx + 3, 1, size.x - 1), clampi(bz + 3, 1, size.y - 1));      # a grid corner: between the plots, not on one
            var base:Vector3 = Vector3(c.x, world.terrain.height_at(c.x, c.y), c.y);
            var pole:BoxMesh = BoxMesh.new();
            pole.size = Vector3(0.07, 1.5, 0.07);
            _scarecrow_part(pole, wood, base + Vector3(0, 0.75, 0));
            var arms:BoxMesh = BoxMesh.new();
            arms.size = Vector3(0.9, 0.06, 0.06);
            _scarecrow_part(arms, wood, base + Vector3(0, 1.15, 0));
            var head:SphereMesh = SphereMesh.new();
            head.radius = 0.12;
            head.height = 0.24;
            _scarecrow_part(head, sack, base + Vector3(0, 1.58, 0));
            var brim:CylinderMesh = CylinderMesh.new();
            brim.top_radius = 0.2;
            brim.bottom_radius = 0.2;
            brim.height = 0.03;
            _scarecrow_part(brim, hat, base + Vector3(0, 1.7, 0));
            var crown:CylinderMesh = CylinderMesh.new();
            crown.top_radius = 0.09;
            crown.bottom_radius = 0.11;
            crown.height = 0.14;
            _scarecrow_part(crown, hat, base + Vector3(0, 1.78, 0));

func _scarecrow_part(mesh:Mesh, mat:Material, at:Vector3) -> void:
    var mi:MeshInstance3D = MeshInstance3D.new();
    mi.mesh = mesh;
    mi.material_override = mat;
    mi.position = at;
    _scarecrows.add_child(mi);

func setup(w:World, id:StringName, o:Vector2i, s:Vector2i) -> void:
    super.setup(w, id, o, s);
    if is_orchard() != crop().get("tree", false):
        crop_id = &"apple" if is_orchard() else &"wheat";
    if not w.seeds.has(crop_id):
        crop_id = w.seeds.first_known(is_orchard());       # a new field starts with a crop the colony has seeds for
    # crops are placed in world space, so keep the node at the origin
    position = Vector3.ZERO;
    var n:int = plot_count();
    plot_state.resize(n);
    growth.resize(n);
    cuts.resize(n);
    frozen_hours.resize(n);
    moisture.resize(n);
    near_water.resize(n);
    irrigated.resize(n);
    pests.resize(n);
    reserved.resize(n);
    plot_crop.resize(n);
    for i in n:
        moisture[i] = 0.5;
        near_water[i] = 1 if _is_near_water(plot_cell(i)) else 0;
    _fence = Fence.new(self, &"field", 1);
    add_child(_fence);

func _process(_delta:float) -> void:
    if has_upgrade(&"scarecrow") and _scarecrows_for != rect():
        _build_scarecrows();
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
    if not Defs.CROPS.has(id) or not world.seeds.has(id) or Defs.CROPS[id].get("tree", false) != is_orchard():
        return false;
    crop_id = id;
    return true;

func is_orchard() -> bool:
    return def.get("orchard", false);

func fertility(i:int) -> float:
    return world.soil_fertility[world.terrain.index(plot_cell(i))];

func _set_fertility(i:int, v:float) -> void:
    world.soil_fertility[world.terrain.index(plot_cell(i))] = clampf(v, 0.0, 1.0);
    world.terrain.refresh_rect(Rect2i(plot_cell(i), Vector2i.ONE));

func mean_fertility() -> float:
    var sum:float = 0.0;
    for i in plot_count():
        sum += fertility(i);
    return sum / maxf(1.0, plot_count());

# Per-plot soil percentages floating over the plots while the soil view is on and this field is selected.
var _soil_labels:Array[Label3D] = [];

func show_soil_numbers(on:bool) -> void:
    if not on:
        for l in _soil_labels:
            l.visible = false;
        return;
    while _soil_labels.size() < plot_count():
        var l:Label3D = Label3D.new();
        l.billboard = BaseMaterial3D.BILLBOARD_ENABLED;
        l.pixel_size = 0.008;
        l.font_size = 32;
        l.outline_size = 8;
        l.no_depth_test = true;
        l.modulate = Color(1, 1, 1);
        add_child(l);
        l.top_level = true;
        _soil_labels.append(l);
    for i in _soil_labels.size():
        var l:Label3D = _soil_labels[i];
        l.visible = i < plot_count();
        if not l.visible:
            continue;
        var c:Vector2i = plot_cell(i);
        l.global_position = world.terrain.cell_center(c) + Vector3(0, 0.6, 0);
        var text:String = "%d" % roundi(fertility(i) * 100.0);
        if l.text != text:
            l.text = text;

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
    d["pests"] = pests;
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
    pests = d.get("pests", PackedFloat32Array());
    pests.resize(plot_count());
    _visual_dirty = true;

# --------------------------------
# Work for farmers

# Returns {"index": int, "action": StringName, "rank": float} for the most urgent open plot (harvest, then clearing,
# then planting, the closest first within each), or {}. A lower rank is more urgent, across fields too.
# has_room(item) -> bool, when given, stops harvesting crops that nothing could store.
# can_water: there is a well to fetch buckets from.
func find_work(from:Vector2i, only_action:StringName = &"", has_room:Callable = Callable(), can_water:bool = true, has_manure:bool = false) -> Dictionary:
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
        if action == &"plant" and has_manure and fertility(i) < MANURE_BELOW:
            action = &"manure";       # enrich the plot first
        if action == &"" and plot_state[i] == Plot.PLANTED and pests[i] >= PEST_TREAT_ABOVE:
            action = &"treat";
        if action == &"" and can_water and plot_state[i] == Plot.PLANTED and moisture[i] < WATER_BELOW:
            action = &"water";
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
                pests[i] = 0.0;
        &"harvest":
            var st:int = plot_state[i];
            if st == Plot.RIPE or st == Plot.FROZEN or (st == Plot.PLANTED and harvest_early and growth[i] >= SALVAGE_MIN_GROWTH):
                var c:Dictionary = Defs.CROPS[plot_crop[i]];
                # ripe: all of it; early or frost-damaged: the share that has grown, less a little
                var share:float = 1.0 if st == Plot.RIPE else minf(1.0, growth[i]) * (FROZEN_SHARE if st == Plot.FROZEN else EARLY_SHARE);
                var amount:int = maxi(1, roundi(c["yield"] * lerpf(0.4, 1.3, fertility(i)) * share * (1.0 - PEST_YIELD_COST * pests[i])));
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
                    pests[i] = 0.0;
        &"clear":
            plot_state[i] = Plot.FALLOW;
            growth[i] = 0.0;
            pests[i] = 0.0;
        &"manure":
            for dz in range(-1, 2):       # one load enriches the plot and the eight around it
                for dx in range(-1, 2):
                    var mx:int = i % size.x + dx;
                    var mz:int = i / size.x + dz;
                    if mx >= 0 and mz >= 0 and mx < size.x and mz < size.y:
                        var k:int = mz * size.x + mx;
                        _set_fertility(k, fertility(k) + MANURE_BOOST);
        &"treat":
            for dz in range(-1, 2):       # pests are picked off the plot and the ones around it
                for dx in range(-1, 2):
                    var tx:int = i % size.x + dx;
                    var tz:int = i / size.x + dz;
                    if tx >= 0 and tz >= 0 and tx < size.x and tz < size.y:
                        pests[tz * size.x + tx] = 0.0;
        &"water":
            for dz in range(-1, 2):       # one bucket wets the plot and the eight around it
                for dx in range(-1, 2):
                    var cx:int = i % size.x + dx;
                    var cz:int = i / size.x + dz;
                    if cx >= 0 and cz >= 0 and cx < size.x and cz < size.y:
                        var j:int = cz * size.x + cx;
                        moisture[j] = maxf(moisture[j], BUCKET_MOISTURE);
    _visual_dirty = true;

# --------------------------------
# Simulation

func on_hour() -> void:
    if state != State.COMPLETE:
        return;
    if _irrigation_seen != world.irrigation_version:
        _update_irrigated();
    var temp:float = Weather.temperature;
    var killed:int = 0;
    var frozen:int = 0;
    for i in plot_count():
        # soil moisture: rain wets, warmth dries, nearby water keeps it up
        var m:float = moisture[i];
        var dry:float = 1.0 - Weather.intensity;
        m += 0.04 * Weather.intensity - (0.003 + maxf(0.0, temp) * 0.0006) * dry * Weather.drying();
        if near_water[i] == 1:
            m = maxf(m, 0.45);
        if irrigated[i] == 1:
            m = maxf(m, IRRIGATED_MOISTURE);
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
                growth[i] += _growth_rate(c, temp, moisture[i]) * (1.0 - PEST_GROWTH_COST * pests[i]);
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
    if is_orchard():
        _visual_dirty = true;            # the leaves change colour through the year
    for i in plot_count():
        if plot_state[i] == Plot.FALLOW:
            _set_fertility(i, fertility(i) + FALLOW_RECOVERY);
    if state == State.COMPLETE:
        _pests_day();

# Pests: a warm day may bring an outbreak to a plot with a crop growing (likelier where the same crop grows in
# other fields nearby), an infested plot gets worse and spreads to its neighbours, and a frost clears them.
func _pests_day() -> void:
    var guard:float = SCARECROW_OUTBREAK if has_upgrade(&"scarecrow") else 1.0;
    if Weather.mean_temperature() < PEST_MIN_TEMP:
        for i in plot_count():
            pests[i] = 0.0;
        _visual_dirty = true;
        return;
    var growing:Array[int] = [];
    for i in plot_count():
        if plot_state[i] == Plot.PLANTED:
            growing.append(i);
    if growing.is_empty():
        return;
    var chance:float = PEST_OUTBREAK * guard * (1.0 + PEST_SAME_CROP * _same_crop_fields_near());
    if world.rng.randf() < chance:
        var pick:int = growing[world.rng.randi_range(0, growing.size() - 1)];
        if pests[pick] <= 0.0:
            pests[pick] = 0.1;
            world.notify("Pests have got into a field of %s." % crop()["name"].to_lower());
    var spread:float = PEST_SPREAD * (SCARECROW_SPREAD if has_upgrade(&"scarecrow") else 1.0);
    var worse:float = PEST_GROWTH * (SCARECROW_GROWTH if has_upgrade(&"scarecrow") else 1.0);
    var infect:Array[int] = [];
    for i in growing:
        if pests[i] <= 0.0:
            continue;
        pests[i] += worse;
        for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
            var x:int = i % size.x + d.x;
            var z:int = i / size.x + d.y;
            if x >= 0 and z >= 0 and x < size.x and z < size.y and plot_state[z * size.x + x] == Plot.PLANTED and pests[z * size.x + x] <= 0.0 and world.rng.randf() < spread:
                infect.append(z * size.x + x);
    for j in infect:
        pests[j] = 0.1;
    for i in growing:
        if pests[i] >= 1.0:
            plot_state[i] = Plot.DEAD;
            pests[i] = 0.0;
    _visual_dirty = true;

func _same_crop_fields_near() -> int:
    var n:int = 0;
    for b in world.buildings:
        if b is Field and b != self and (b as Field).crop_id == crop_id and (b as Field).state == State.COMPLETE and Vector2(b.origin).distance_to(Vector2(origin)) <= PEST_NEARBY:
            n += 1;
    return n;

func infested_count() -> int:
    var n:int = 0;
    for i in plot_count():
        if pests[i] > 0.0 and plot_state[i] == Plot.PLANTED:
            n += 1;
    return n;

# After an expansion: every plot keeps its crop and growth, new ones start fallow. The plot numbers change with the width.
func on_resized(old:Rect2i) -> void:
    var n:int = plot_count();
    var st:PackedByteArray = PackedByteArray();
    var gr:PackedFloat32Array = PackedFloat32Array();
    var ct:PackedByteArray = PackedByteArray();
    var fh:PackedFloat32Array = PackedFloat32Array();
    var mo:PackedFloat32Array = PackedFloat32Array();
    var nw:PackedByteArray = PackedByteArray();
    var pe:PackedFloat32Array = PackedFloat32Array();
    var pc:Array[StringName] = [];
    pe.resize(n);
    st.resize(n);
    ct.resize(n);
    nw.resize(n);
    gr.resize(n);
    fh.resize(n);
    mo.resize(n);
    pc.resize(n);
    for i in n:
        var c:Vector2i = plot_cell(i);
        if old.has_point(c):
            var oi:int = (c.x - old.position.x) + (c.y - old.position.y) * old.size.x;
            st[i] = plot_state[oi];
            pc[i] = plot_crop[oi];
            gr[i] = growth[oi];
            ct[i] = cuts[oi];
            fh[i] = frozen_hours[oi];
            mo[i] = moisture[oi];
            nw[i] = near_water[oi];
            pe[i] = pests[oi];
        else:
            st[i] = Plot.FALLOW;
            pc[i] = crop_id;
            mo[i] = 0.5;
            nw[i] = 1 if _is_near_water(c) else 0;
    plot_state = st;
    plot_crop = pc;
    growth = gr;
    cuts = ct;
    frozen_hours = fh;
    moisture = mo;
    near_water = nw;
    pests = pe;
    irrigated.resize(n);
    _irrigation_seen = -1;
    reserved.clear();
    reserved.resize(n);
    super.on_resized(old);
    position = Vector3.ZERO;       # crops are drawn in world space
    _visual_dirty = true;

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

# Plots within CHANNEL_RANGE of a channel with water in it.
func _update_irrigated() -> void:
    _irrigation_seen = world.irrigation_version;
    irrigated.resize(plot_count());
    for i in plot_count():
        irrigated[i] = 0;
        var c:Vector2i = plot_cell(i);
        for dz in range(-Defs.CHANNEL_RANGE, Defs.CHANNEL_RANGE + 1):
            for dx in range(-Defs.CHANNEL_RANGE, Defs.CHANNEL_RANGE + 1):
                if world.terrain.in_bounds(c + Vector2i(dx, dz)) and world.terrain.get_overlay(c + Vector2i(dx, dz)) == Terrain.Overlay.CHANNEL_WET:
                    irrigated[i] = 1;

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
        s += "Harvesting early\n";
    if counts[Plot.FROZEN] > 0:
        s += "Frozen plots: harvest them now\n";
    s += "Needs %d farmer%s (one per %d plots)\n" % [farmer_positions(), "" if farmer_positions() == 1 else "s", Defs.PLOTS_PER_FARMER];
    var lo:float = 1.0;
    var hi:float = 0.0;
    for i in plot_count():
        lo = minf(lo, fertility(i));
        hi = maxf(hi, fertility(i));
    s += "Soil fertility: %d%% (%d to %d)\n" % [roundi(fert / n * 100.0), roundi(lo * 100.0), roundi(hi * 100.0)];
    s += "Soil moisture: %d%%\n" % roundi(moist / n * 100.0);
    if infested_count() > 0:
        s += "Pests in %d plot%s\n" % [infested_count(), "" if infested_count() == 1 else "s"];
    var why:String = Weather.sow_block_reason(c);
    s += "Sowing now: %s\n" % ("yes" if why == "" else "no, " + why);
    return s;

func help_text() -> String:
    var s:String = super.help_text();
    var c:Dictionary = crop();
    s += "\nSows %s." % Defs.sow_text(crop_id);
    if c.has("harvests"):
        s += "\nGives up to %d cuttings from one sowing." % c["harvests"];
    s += "\nHarvesting early: growing plots are taken for part of the crop, and nothing is sown meanwhile.";
    s += "\nFrozen plots can be harvested for part of the crop for a day, then they are lost.";
    return s;

# Draws the orchard trees: per species a trunk, a crown (bare in winter, blossom or leaves otherwise) and, on ripe plots, the fruit.
func _rebuild_orchard(trees:Dictionary) -> void:
    for crop in _tree_layers:
        if not trees.has(crop):
            trees[crop] = [];                    # a species that is no longer here: empty its layers
    for crop in trees:
        var list:Array = trees[crop];
        var layers:Dictionary = _tree_layer(crop);
        var leaf:Color = CropMeshes.leaf_colour(crop);
        var trunks:Array = [];
        var crowns:Array = [];
        var fruits:Array = [];
        for i in list:
            var h:float;
            var col:Color = leaf;
            match plot_state[i]:
                Plot.PLANTED:
                    h = 0.25 + growth[i] * 0.75;
                Plot.RIPE:
                    h = 1.0;
                Plot.FROZEN:
                    h = 0.25 + growth[i] * 0.75;
                    col = Color(0.72, 0.84, 0.9);       # white with frost
                _:
                    h = 0.5;
                    col = Color(0, 0, 0, 0);             # dead: the trunk stands bare
            var cell:Vector2i = plot_cell(i);
            var yaw:float = float(((cell.x * 73856093) ^ (cell.y * 19349663)) & 1023) / 1023.0 * TAU;
            var xf:Transform3D = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(h, h, h)), world.terrain.cell_center(cell));
            trunks.append([xf, Color.WHITE]);
            if col.a > 0.0 and (growth[i] >= 0.15 or plot_state[i] == Plot.RIPE):
                if pests[i] > 0.0:
                    col = col.lerp(Color(0.5, 0.33, 0.16), pests[i] * 0.8);       # nibbled and browning
                crowns.append([xf, col]);
                if plot_state[i] == Plot.RIPE:
                    fruits.append([xf, Defs.CROPS[crop]["color"]]);
        _fill_layer(layers[&"trunk"], trunks);
        _fill_layer(layers[&"crown"], crowns);
        _fill_layer(layers[&"fruit"], fruits);

func _fill_layer(mmi:MultiMeshInstance3D, list:Array) -> void:
    var mm:MultiMesh = mmi.multimesh;
    mm.instance_count = list.size();
    for j in list.size():
        mm.set_instance_transform(j, list[j][0]);
        mm.set_instance_color(j, list[j][1]);

# The layers (trunk, crown, fruit) for an orchard crop, made the first time they are needed.
func _tree_layer(crop:StringName) -> Dictionary:
    if not _tree_layers.has(crop):
        var d:Dictionary = {};
        for part in CropMeshes.ORCHARD_PARTS:
            var mm:MultiMesh = MultiMesh.new();
            mm.transform_format = MultiMesh.TRANSFORM_3D;
            mm.use_colors = true;
            mm.mesh = CropMeshes.orchard_mesh(crop, part);
            var mmi:MultiMeshInstance3D = MultiMeshInstance3D.new();
            mmi.multimesh = mm;
            mmi.material_override = CropMeshes.orchard_material(part);
            _apply_distance(mmi);
            add_child(mmi);
            d[part] = mmi;
        _tree_layers[crop] = d;
    return _tree_layers[crop];

func _rebuild_crops() -> void:
    var by_key:Dictionary = {};          # model key -> [plot index, ...]
    var trees:Dictionary = {};           # orchard crop -> plots drawn as that tree
    for i in plot_count():
        if plot_state[i] == Plot.FALLOW:
            continue;
        if CropMeshes.shape_of(plot_crop[i]) == &"tree":
            if not trees.has(plot_crop[i]):
                trees[plot_crop[i]] = [];
            trees[plot_crop[i]].append(i);
            continue;
        var key:String = CropMeshes.crop_key(plot_crop[i], plot_state[i], growth[i]);
        if not by_key.has(key):
            by_key[key] = [];
        by_key[key].append(i);
    _rebuild_orchard(trees);
    for key in _crop_layers:
        if not by_key.has(key):
            by_key[key] = [];            # a model no plot uses now: empty its layer
    for key in by_key:
        var list:Array = by_key[key];
        var mm:MultiMesh = _crop_layer(key).multimesh;
        mm.instance_count = list.size();
        for j in list.size():
            var i:int = list[j];
            var size:float = lerpf(0.85, 1.0, CropMeshes.stage_progress(plot_state[i], growth[i]));
            var col:Color = Color.WHITE;
            if plot_state[i] == Plot.FROZEN:
                col = Color(0.72, 0.84, 0.9);          # white with frost
            if pests[i] > 0.0 and (plot_state[i] == Plot.PLANTED or plot_state[i] == Plot.RIPE):
                col = col.lerp(Color(0.5, 0.33, 0.16), pests[i] * 0.8);       # nibbled and browning
            var cell:Vector2i = plot_cell(i);
            var yaw:float = float(((cell.x * 73856093) ^ (cell.y * 19349663)) & 1023) / 1023.0 * TAU;       # no two plots look alike
            mm.set_instance_transform(j, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(size, size, size)), world.terrain.cell_center(cell)));
            mm.set_instance_color(j, col);

# Plants and trees past the draw distance (Settings) are not drawn: measured to the middle of the field, so a margin for its size.
func _apply_distance(mmi:MultiMeshInstance3D) -> void:
    var d:float = Settings.draw_distance();
    mmi.visibility_range_end = d + maxf(size.x, size.y) * 0.75 + 4.0 if d > 0.0 else 0.0;
    mmi.visibility_range_end_margin = 4.0 if d > 0.0 else 0.0;

# Follows the Settings: the draw distance, and the model set (the plants are loaded again when it changes).
func apply_settings() -> void:
    var low:bool = Settings.models_reduced();
    if low != _layers_low:
        _layers_low = low;
        for key in _crop_layers:
            (_crop_layers[key] as Node).queue_free();
        _crop_layers.clear();
        for crop in _tree_layers:
            for part in _tree_layers[crop]:
                (_tree_layers[crop][part] as Node).queue_free();
        _tree_layers.clear();
        _visual_dirty = true;
    for key in _crop_layers:
        _apply_distance(_crop_layers[key]);
    for crop in _tree_layers:
        for part in _tree_layers[crop]:
            _apply_distance(_tree_layers[crop][part]);

# The layer for a crop model, made the first time a plot needs it.
func _crop_layer(key:String) -> MultiMeshInstance3D:
    if not _crop_layers.has(key):
        var mm:MultiMesh = MultiMesh.new();
        mm.transform_format = MultiMesh.TRANSFORM_3D;
        mm.use_colors = true;
        mm.mesh = CropMeshes.crop_model(key);
        var mmi:MultiMeshInstance3D = MultiMeshInstance3D.new();
        mmi.multimesh = mm;
        mmi.material_override = CropMeshes.crop_material();
        _apply_distance(mmi);
        add_child(mmi);
        _crop_layers[key] = mmi;
    return _crop_layers[key];
