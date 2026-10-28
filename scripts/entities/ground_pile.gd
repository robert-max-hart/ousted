# ----------------------------------------------------------------
# GroundPile
#     Goods lying on the ground, dropped when no storage had room (or
#     left behind by a demolished building). Citizens haul them to
#     storage once there is space.
# ----------------------------------------------------------------
class_name GroundPile extends Node3D;

var item        :StringName;
var amount      :int = 0;
var cell        :Vector2i;
var reserved_by :Pawn = null;
var removed     :bool = false;

var _mesh       :MeshInstance3D;
var _spoil_acc  :float = 0.0;

const SPOIL_MULT:float = 10.0;

func setup(w:World, it:StringName, n:int, c:Vector2i) -> void:
    item = it;
    amount = n;
    cell = c;
    name = "pile_%s_%d_%d" % [it, c.x, c.y];
    position = w.terrain.cell_center(c);
    var box:BoxMesh = BoxMesh.new();
    var mat:StandardMaterial3D = StandardMaterial3D.new();
    mat.albedo_color = Defs.ITEMS[it]["color"] if Defs.ITEMS.has(it) else Color.GRAY;
    mat.roughness = 0.9;
    _mesh = MeshInstance3D.new();
    _mesh.mesh = box;
    _mesh.material_override = mat;
    add_child(_mesh);
    _update_visual();

func to_dict() -> Dictionary:
    return {"item": item, "amount": amount, "cell": cell, "spoil_acc": _spoil_acc};

func display_name() -> String:
    return "%s pile" % Defs.item_name(item);

func info_text() -> String:
    var s:String = "%d %s lying on the ground.\nCitizens will haul it to storage when there is room.\n" % [amount, Defs.item_name(item)];
    if Defs.spoil_per_hour(item) > 0.0:
        s += "It spoils %dx faster out here.\n" % int(SPOIL_MULT);
    return s;

func add(n:int) -> void:
    amount += n;
    _update_visual();

func take(n:int) -> int:
    var t:int = mini(n, amount);
    amount -= t;
    _update_visual();
    return t;

# Food left on the ground is a penalty for missing storage: it spoils this many times faster than
# in ordinary storage. Returns units lost.
func spoil_tick(hours:float, tally:Dictionary = {}) -> int:
    var rate:float = Defs.spoil_per_hour(item);
    if rate <= 0.0 or amount <= 0:
        return 0;
    _spoil_acc += amount * rate * SPOIL_MULT * Defs.spoil_temp_factor(Weather.temperature) * hours;
    var whole:int = mini(floori(_spoil_acc), amount);
    if whole > 0:
        _spoil_acc -= whole;
        take(whole);
        tally[item] = tally.get(item, 0) + whole;
    return whole;

func _update_visual() -> void:
    var s:float = lerpf(0.35, 0.9, clampf(amount / 12.0, 0.0, 1.0));
    (_mesh.mesh as BoxMesh).size = Vector3(s, s * 0.7, s);
    _mesh.position.y = s * 0.35;
