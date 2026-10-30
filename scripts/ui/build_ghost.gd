# ----------------------------------------------------------------
# BuildGhost
#     A see-through copy of the building being placed, so the player
#     sees its real shape instead of a solid block. It is a real
#     Building that is never added to the world's lists: it is only
#     drawn, tinted green (fits), orange (fits, but the colony lacks
#     the materials right now) or red (can't go there).
#     PlayerTools keeps one and moves it to the cursor.
# ----------------------------------------------------------------
class_name BuildGhost extends Node3D;

var _model      :Building;
var _key        :String = "";
var _mat        :Material;
var _front      :Node3D;            # a flat arrow on the ground showing which side is the front (the door)

# Shows the ghost for def_id at origin with the given tint, rebuilding the model when the building or its size changes.
func show_at(world:World, def_id:StringName, origin:Vector2i, size:Vector2i, tint:Material, facing:int = 0) -> void:
    var key:String = "%s %s %d" % [def_id, size, facing];
    if key != _key or _model == null:
        _clear();
        _key = key;
        _model = Building.new();
        _model.facing = facing;
        _model.setup(world, def_id, origin, size);
        _model.state = Building.State.COMPLETE;
        _model._update_visual();
        add_child(_model);
        _mat = null;
        _hide_extras(_model);
        _make_front();
    var center:Vector2 = Vector2(origin.x + size.x * 0.5, origin.y + size.y * 0.5);
    _model.position = Vector3(center.x, maxf(world.terrain.height_at(center.x, center.y), Terrain.WATER_LEVEL) if _model.def.get("bridge", false) or _model.def.get("fishing", false) else world.terrain.height_at(center.x, center.y), center.y);
    if tint != _mat:
        _mat = tint;
        _tint(_model, tint);
    if _front != null:
        _front.visible = not (_model.def.get("drag_size", false) or _model.def.get("field", false));
        _front.position = _model.position;
        _front.rotation.y = _model.rotation.y;
        _front.get_child(0).position = Vector3(0, 0.25, _model.vsize.y * 0.5 + 0.9);
    visible = true;

func hide_ghost() -> void:
    visible = false;

func _make_front() -> void:
    if _front != null:
        _front.queue_free();
    _front = Node3D.new();
    var arrow:MeshInstance3D = MeshInstance3D.new();
    var prism:PrismMesh = PrismMesh.new();
    prism.size = Vector3(0.9, 0.9, 0.06);
    arrow.mesh = prism;
    arrow.basis = Basis(Vector3.RIGHT, PI * 0.5);       # lie flat, the point towards the front
    var mat:StandardMaterial3D = StandardMaterial3D.new();
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED;
    mat.albedo_color = Color(1.0, 0.9, 0.4);
    arrow.material_override = mat;
    arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
    _front.add_child(arrow);
    add_child(_front);

func _clear() -> void:
    if _front != null:
        _front.queue_free();
        _front = null;
    if _model != null:
        _model.queue_free();
        _model = null;
    _key = "";

# No smoke, labels or goods on a ghost.
func _hide_extras(n:Node) -> void:
    for c in n.get_children():
        if c is CPUParticles3D or c is Label3D or c is PileGoods:
            (c as Node3D).visible = false;
            c.set_process(false);
        _hide_extras(c);

func _tint(n:Node, tint:Material) -> void:
    for c in n.get_children():
        if c is GeometryInstance3D and not (c is PileGoods):
            (c as GeometryInstance3D).material_override = tint;
            (c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
        _tint(c, tint);
