# ----------------------------------------------------------------
# Graveyard
#     Sized by dragging like a crop field: every square is one grave.
#     A buried citizen gets a headstone and the square stays taken until
#     the grave decomposes (Defs.GRAVE_DECAY_YEARS).
# ----------------------------------------------------------------
class_name Graveyard extends Building;

var graves      :Array = [];       # per square: null, or {name, age, cause, buried_hour}
var reserved    :Array = [];       # Pawn or null per square, for someone on the way with a body
var _stones     :MultiMeshInstance3D;
var _visual_dirty:bool = true;

func setup(w:World, id:StringName, o:Vector2i, s:Vector2i) -> void:
    super.setup(w, id, o, s);
    graves.resize(plot_count());
    reserved.resize(plot_count());
    var mm:MultiMesh = MultiMesh.new();
    mm.transform_format = MultiMesh.TRANSFORM_3D;
    var box:BoxMesh = BoxMesh.new();
    box.size = Vector3(0.4, 0.7, 0.12);
    mm.mesh = box;
    var mat:StandardMaterial3D = StandardMaterial3D.new();
    mat.albedo_color = Color(0.62, 0.62, 0.64);
    mat.roughness = 1.0;
    _stones = MultiMeshInstance3D.new();
    _stones.multimesh = mm;
    _stones.material_override = mat;
    _stones.top_level = true;       # stones are placed in world space
    add_child(_stones);

func _process(_delta:float) -> void:
    if _visual_dirty:
        _visual_dirty = false;
        _rebuild_stones();

func plot_count() -> int:
    return size.x * size.y;

@warning_ignore("integer_division")
func plot_cell(i:int) -> Vector2i:
    return origin + Vector2i(i % size.x, i / size.x);

# The def's work value is for 36 squares, like a field (an upgrade's is fixed).
func work_required() -> float:
    if upgrading != &"":
        return super.work_required();
    return def["work"] * plot_count() / 36.0 * cost_mult;

func free_slots() -> int:
    var n:int = 0;
    for i in plot_count():
        if graves[i] == null and (reserved[i] == null or not World.alive(reserved[i])):
            n += 1;
    return n;

func used_slots() -> int:
    var n:int = 0;
    for g in graves:
        if g != null:
            n += 1;
    return n;

# Claims the free square nearest the given cell for p, or returns -1.
func reserve_slot(p:Pawn, near:Vector2i) -> int:
    if not is_complete():
        return -1;
    var best:int = -1;
    var best_d:float = INF;
    for i in plot_count():
        if graves[i] != null or (reserved[i] != null and World.alive(reserved[i])):
            continue;
        var d:float = Vector2(plot_cell(i) - near).length_squared();
        if d < best_d:
            best_d = d;
            best = i;
    if best >= 0:
        reserved[best] = p;
    return best;

func release_slot(i:int, p:Pawn) -> void:
    if reserved[i] == p:
        reserved[i] = null;

func bury(i:int, b:Body) -> void:
    graves[i] = {"name": b.person, "age": b.age, "cause": b.cause, "buried_hour": GameClock.total_hours};
    reserved[i] = null;
    _visual_dirty = true;

func decay_hours() -> float:
    return Defs.GRAVE_DECAY_YEARS * GameClock.DAYS_PER_YEAR * GameClock.HOURS_PER_DAY;

func on_day() -> void:
    for i in plot_count():
        var g:Variant = graves[i];
        if g != null and GameClock.total_hours - g["buried_hour"] >= decay_hours():
            graves[i] = null;
            _visual_dirty = true;
    _cremate();

# Coal is only fetched once the crematorium is built and a number of free squares is asked for.
func inputs_wanted() -> Dictionary:
    var want:Dictionary = {};
    if not is_complete() or not has_upgrade(&"crematorium") or settings.get("keep_free", 0) <= 0:
        return want;
    var n:int = def["inputs"][&"coal"] - input_amount(&"coal") - input_incoming.get(&"coal", 0);
    if n > 0:
        want[&"coal"] = n;
    return want;

# With the crematorium, the oldest graves are burned (one coal each) until `keep_free` squares are free.
func _cremate() -> void:
    if not is_complete() or not has_upgrade(&"crematorium"):
        return;
    var keep:int = settings.get("keep_free", 0);
    var burned:int = 0;
    while free_slots() < keep and input_amount(&"coal") > 0:
        var oldest:int = -1;
        for i in plot_count():
            if graves[i] != null and (oldest < 0 or graves[i]["buried_hour"] < graves[oldest]["buried_hour"]):
                oldest = i;
        if oldest < 0:
            break;
        graves[oldest] = null;
        take_input(&"coal", 1);
        burned += 1;
    if burned > 0:
        _visual_dirty = true;
        world.notify("%d old %s cremated to free graves." % [burned, "grave was" if burned == 1 else "graves were"]);

func on_terrain_changed() -> void:
    super.on_terrain_changed();
    _visual_dirty = true;

func to_dict() -> Dictionary:
    var d:Dictionary = super.to_dict();
    d["graves"] = graves.duplicate(true);
    return d;

func restore_dict(d:Dictionary) -> void:
    super.restore_dict(d);
    graves = d["graves"];
    graves.resize(plot_count());
    if state == State.COMPLETE:
        for i in plot_count():
            world.terrain.set_overlay(plot_cell(i), Terrain.Overlay.GRAVE);       # saves from before the ground was an overlay
    _visual_dirty = true;

func info_text() -> String:
    if state != State.COMPLETE:
        return super.info_text();
    var s:String = "Graves: %d of %d used, %d free\n" % [used_slots(), plot_count(), free_slots()];
    var oldest:float = INF;
    for g in graves:
        if g != null:
            oldest = minf(oldest, g["buried_hour"]);
    if oldest < INF:
        var days:float = (oldest + decay_hours() - GameClock.total_hours) / GameClock.HOURS_PER_DAY;
        s += "The oldest grave is freed in %d days.\n" % maxi(0, ceili(days));
    s += "Graves are freed after %d years.\n" % roundi(Defs.GRAVE_DECAY_YEARS);
    if has_upgrade(&"crematorium"):
        s += "Coal for cremation: %d / %d\n" % [input_amount(&"coal"), def["inputs"][&"coal"]];
    if used_slots() > 0:
        s += "Can't be demolished while graves are in use.\n";
    return s;

func _rebuild_stones() -> void:
    var list:Array[int] = [];
    for i in plot_count():
        if graves[i] != null:
            list.append(i);
    var mm:MultiMesh = _stones.multimesh;
    mm.instance_count = list.size();
    for j in list.size():
        var p:Vector3 = world.terrain.cell_center(plot_cell(list[j]));
        p.y += 0.35;
        mm.set_instance_transform(j, Transform3D(Basis(), p));
