# ----------------------------------------------------------------
# Herbalist
#     The Herbalist's Hut. It keeps a store of healing herbs for the
#     healer (8, or 16 with the Herb Greenhouse). The greenhouse
#     upgrade grows about a herb a day by itself, in any weather, up to
#     a few waiting, and the healer picks them between visits
#     (HealthTasks). It also shows: a glasshouse leans on the back wall.
# ----------------------------------------------------------------
class_name Herbalist extends Building;

const GREEN_RATE   :float = 1.0;        # herbs a day, whatever the weather
const GREEN_CAP    :int = 10;           # herbs waiting in the beds
const COLLECT_AT   :int = 3;            # herbs ready before the healer makes the trip
const STORE_BASE   :int = 8;
const STORE_GREEN  :int = 16;

var green_acc  :float = 0.0;
var ready_herbs:int = 0;
var claimed    :bool = false;           # the healer is on the way to pick (not saved)
var _glass_shown:bool = false;

func has_greenhouse() -> bool:
    return is_complete() and has_upgrade(&"greenhouse");

func input_cap(item:StringName) -> int:
    if item == &"herbs":
        return STORE_GREEN if has_greenhouse() else STORE_BASE;
    return super.input_cap(item);

# Room left in the hut's own store, counting nothing on the way.
func herb_room() -> int:
    return maxi(0, input_cap(&"herbs") - input_amount(&"herbs") - input_incoming.get(&"herbs", 0));

func on_day() -> void:
    super.on_day();
    if not has_greenhouse():
        return;
    green_acc += GREEN_RATE;
    var n:int = floori(green_acc);
    green_acc -= n;
    ready_herbs = mini(GREEN_CAP, ready_herbs + n);

# {"item": herbs, "n": ready} when enough are ready to be worth a trip, else {}.
func collectable() -> Dictionary:
    if has_greenhouse() and ready_herbs >= COLLECT_AT:
        return {"item": &"herbs", "n": ready_herbs};
    return {};

func take_ready(n:int) -> int:
    var k:int = mini(n, ready_herbs);
    ready_herbs -= k;
    return k;

# --------------------------------
# The glasshouse: a timber-framed lean-to on the back wall (the side away from the door), glass pitched down to a low front,
# a stone kerb and rows of green inside.

func on_upgrade_done(id:StringName) -> void:
    if id != &"greenhouse" or _glass_shown:
        return;
    _glass_shown = true;
    var back:float = -float(vsize.y) * 0.5 + 0.25;       # the back wall of the cottage body
    var depth:float = 0.85;
    var w:float = float(vsize.x) - 1.0;
    var cz:float = back - depth * 0.5;
    var wall_h:float = 1.05;
    var low_h:float = 0.45;
    var glass:StandardMaterial3D = StandardMaterial3D.new();
    glass.albedo_color = Color(0.72, 0.9, 0.92, 0.38);
    glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA;
    glass.roughness = 0.1;
    var wood:StandardMaterial3D = _flat_mat(Color(0.82, 0.8, 0.72));
    var stone:StandardMaterial3D = _flat_mat(Color(0.55, 0.53, 0.5));
    var kerb:BoxMesh = BoxMesh.new();
    kerb.size = Vector3(w, 0.14, depth);
    add_decor(kerb, stone, Vector3(0, 0.07, cz));
    var tilt:float = atan2(wall_h - low_h, depth);
    var roof:BoxMesh = BoxMesh.new();
    roof.size = Vector3(w, 0.04, depth / cos(tilt) + 0.06);
    add_decor(roof, glass, Vector3(0, (wall_h + low_h) * 0.5 + 0.02, cz), Vector3(-tilt, 0, 0));
    var front:BoxMesh = BoxMesh.new();
    front.size = Vector3(w, low_h - 0.14, 0.03);
    add_decor(front, glass, Vector3(0, 0.14 + (low_h - 0.14) * 0.5, back - depth));
    for sgn in [-1.0, 1.0]:
        var side:BoxMesh = BoxMesh.new();
        side.size = Vector3(0.03, wall_h - 0.14, depth);
        add_decor(side, glass, Vector3(sgn * w * 0.5, 0.14 + (wall_h - 0.14) * 0.5 - 0.2, cz));
        var post_hi:BoxMesh = BoxMesh.new();
        post_hi.size = Vector3(0.06, wall_h, 0.06);
        add_decor(post_hi, wood, Vector3(sgn * w * 0.5, wall_h * 0.5, back - 0.03));
        var post_lo:BoxMesh = BoxMesh.new();
        post_lo.size = Vector3(0.06, low_h, 0.06);
        add_decor(post_lo, wood, Vector3(sgn * w * 0.5, low_h * 0.5, back - depth));
    var rail:BoxMesh = BoxMesh.new();
    rail.size = Vector3(w, 0.05, 0.05);
    add_decor(rail, wood, Vector3(0, low_h + 0.02, back - depth));
    add_decor(rail, wood, Vector3(0, wall_h + 0.02, back - 0.03));
    var bed:BoxMesh = BoxMesh.new();
    bed.size = Vector3(w * 0.8, 0.12, 0.22);
    var leaf:SphereMesh = SphereMesh.new();
    leaf.radius = 0.1;
    leaf.height = 0.2;
    leaf.radial_segments = 6;
    leaf.rings = 3;
    var soil:StandardMaterial3D = _flat_mat(Color(0.3, 0.22, 0.15));
    var green:StandardMaterial3D = _flat_mat(Color(0.34, 0.6, 0.3));
    for row in 2:
        var rz:float = back - 0.28 - row * 0.3;
        add_decor(bed, soil, Vector3(0, 0.2, rz));
        for k in 5:
            add_decor(leaf, green, Vector3((k - 2) * w * 0.17, 0.32 + (0.03 if k % 2 == 0 else 0.0), rz));

func to_dict() -> Dictionary:
    var d:Dictionary = super.to_dict();
    d["green_acc"] = green_acc;
    d["ready_herbs"] = ready_herbs;
    return d;

func restore_dict(d:Dictionary) -> void:
    super.restore_dict(d);
    green_acc = d.get("green_acc", 0.0);
    ready_herbs = d.get("ready_herbs", 0);
    if has_upgrade(&"greenhouse"):
        on_upgrade_done(&"greenhouse");

func info_text() -> String:
    var s:String = super.info_text();
    if state == State.COMPLETE and has_greenhouse():
        s += "\nGreenhouse: %d herbs ready (about %.0f a day)\n" % [ready_herbs, GREEN_RATE];
    return s;
