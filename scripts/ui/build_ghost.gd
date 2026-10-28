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

# Shows the ghost for def_id at origin with the given tint, rebuilding the model when the building or its size changes.
func show_at(world:World, def_id:StringName, origin:Vector2i, size:Vector2i, tint:Material) -> void:
    var key:String = "%s %s" % [def_id, size];
    if key != _key or _model == null:
        _clear();
        _key = key;
        _model = Building.new();
        _model.setup(world, def_id, origin, size);
        _model.state = Building.State.COMPLETE;
        _model._update_visual();
        add_child(_model);
        _mat = null;
        _hide_extras(_model);
    var center:Vector2 = Vector2(origin.x + size.x * 0.5, origin.y + size.y * 0.5);
    _model.position = Vector3(center.x, world.terrain.height_at(center.x, center.y), center.y);
    if tint != _mat:
        _mat = tint;
        _tint(_model, tint);
    visible = true;

func hide_ghost() -> void:
    visible = false;

func _clear() -> void:
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
