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

var _mesh       :MultiMeshInstance3D;
var _shown      :int = -1;
var _spoil_acc  :float = 0.0;

const SPOIL_MULT:float = 10.0;
const MAX_SHOWN :int = 8;
# Where the goods of a heap sit (x, y level, z): four on the ground, three on those, one on top.
const SLOTS:Array[Vector3] = [
    Vector3(-0.2, 0, -0.18), Vector3(0.2, 0, -0.14), Vector3(-0.16, 0, 0.22), Vector3(0.22, 0, 0.2),
    Vector3(0.0, 1, -0.1), Vector3(-0.17, 1, 0.1), Vector3(0.17, 1, 0.08), Vector3(0.0, 2, 0.0),
];

func setup(w:World, it:StringName, n:int, c:Vector2i) -> void:
    item = it;
    amount = n;
    cell = c;
    name = "pile_%s_%d_%d" % [it, c.x, c.y];
    position = w.terrain.cell_center(c);
    var mm:MultiMesh = MultiMesh.new();
    mm.transform_format = MultiMesh.TRANSFORM_3D;
    mm.use_colors = true;                 # kept white (the Compatibility renderer needs it): the item's colour is the custom data
    mm.use_custom_data = true;
    mm.mesh = PileGoods.mesh_for(PileGoods.form_of(it));
    _mesh = MultiMeshInstance3D.new();
    _mesh.multimesh = mm;
    _mesh.material_override = PileGoods._mat();
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

# One good for every three units, up to eight, heaped in the cell.
func _update_visual() -> void:
    var n:int = clampi(ceili(amount / 3.0), 1 if amount > 0 else 0, MAX_SHOWN);
    if n == _shown:
        return;
    _shown = n;
    var mm:MultiMesh = _mesh.multimesh;
    mm.instance_count = n;
    var col:Color = Defs.ITEMS[item].get("color", Color.GRAY) if Defs.ITEMS.has(item) else Color.GRAY;
    var crosswise:bool = PileGoods.form_of(item) in PileGoods.STACKED_CROSSWISE;
    for i in n:
        var slot:Vector3 = SLOTS[i];
        var jitter:float = float(hash(Vector3i(cell.x, cell.y, i)) & 0xff) / 255.0;
        var yaw:float = (jitter - 0.5) * 0.9 + (PI * 0.5 if crosswise and int(slot.y) % 2 == 1 else 0.0);
        mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, yaw), Vector3(slot.x, 0.04 + PileGoods.LEVEL * slot.y, slot.z)));
        mm.set_instance_color(i, Color.WHITE);
        mm.set_instance_custom_data(i, col.lerp(Color.WHITE, 0.04 + jitter * 0.1));
