# ----------------------------------------------------------------
# InspectorExtras
#     Two additions to the inspector panel:
#       - for a tree, rock or wild food: a button to mark it for
#         harvest (or pick it) or to take the mark off
#       - for a finished job building: the citizens who hold its
#         profession, each a button that selects them and moves the
#         camera to where they are
#     HUD owns one and calls refresh() with the selected object.
# ----------------------------------------------------------------
class_name InspectorExtras extends VBoxContainer;

var _mark_btn   :Button;
var _early_btn  :Button;
var _field      :Field;
var _grow_btn   :Button;       # expand a field, stockpile or graveyard, or cancel the expansion
var _grow_for   :Building;
var _workers_box:VBoxContainer;
var _workers_sig:String = "";
var _pupils_box :VBoxContainer;
var _pupils_sig :String = "";
var _order_btn  :Button;       # cancel a marked single tree
var _order      :TreeOrder;
var _node       :ResourceNode;

func _init() -> void:
    _mark_btn = Button.new();
    _mark_btn.focus_mode = Control.FOCUS_NONE;
    _mark_btn.visible = false;
    _mark_btn.pressed.connect(_on_mark);
    add_child(_mark_btn);
    _order_btn = Button.new();
    _order_btn.text = "Cancel this planting";
    _order_btn.focus_mode = Control.FOCUS_NONE;
    _order_btn.visible = false;
    _order_btn.pressed.connect(func() -> void:
        if _order != null and not _order.removed:
            World.instance.cancel_tree_order(_order.cell);
            World.instance.tools.select(null));
    add_child(_order_btn);
    _grow_btn = Button.new();
    _grow_btn.focus_mode = Control.FOCUS_NONE;
    _grow_btn.visible = false;
    _grow_btn.pressed.connect(_on_grow);
    add_child(_grow_btn);
    _early_btn = Button.new();
    _early_btn.focus_mode = Control.FOCUS_NONE;
    _early_btn.visible = false;
    _early_btn.pressed.connect(_on_early);
    add_child(_early_btn);
    _workers_box = VBoxContainer.new();
    _workers_box.visible = false;
    add_child(_workers_box);
    _pupils_box = VBoxContainer.new();
    _pupils_box.visible = false;
    add_child(_pupils_box);

func refresh(obj:Variant) -> void:
    _order = obj as TreeOrder if obj is TreeOrder else null;
    _order_btn.visible = _order != null;
    _refresh_mark(obj);
    _refresh_grow(obj);
    _refresh_early(obj);
    _refresh_workers(obj);
    _refresh_pupils(obj);

func _refresh_mark(obj:Variant) -> void:
    _node = obj as ResourceNode if obj is ResourceNode else null;
    _mark_btn.visible = _node != null and not _node.removed;
    if not _mark_btn.visible:
        return;
    var verb:String = "picking" if _node.is_forageable() else "harvest";
    _mark_btn.text = "Cancel the mark for %s" % verb if _node.designated else "Mark for %s" % verb;

func _on_mark() -> void:
    if _node != null and World.alive(_node):
        World.instance.set_designated(_node, not _node.designated);
        _refresh_mark(_node);

# Expand: for a finished building the player drags out (fields, stockpiles, graveyards).
func _refresh_grow(obj:Variant) -> void:
    _grow_for = obj as Building if obj is Building and obj.def.get("drag_size", false) else null;
    _grow_btn.visible = _grow_for != null and _grow_for.is_complete() and _grow_for.relocating_from == null;
    if not _grow_btn.visible:
        return;
    if _grow_for.upgrading == Expansion.ID:
        _grow_btn.text = "Cancel the expansion";
        _grow_btn.disabled = false;
        _grow_btn.tooltip_text = "Stop and take back the materials delivered so far";
        return;
    _grow_btn.text = "Expand";
    _grow_btn.disabled = _grow_for.upgrading != &"";
    _grow_btn.tooltip_text = "Grow it on the side you click. The extra area costs the difference, and builders do the work." if not _grow_btn.disabled else "Another project is in progress";

func _on_grow() -> void:
    if _grow_for == null or not World.alive(_grow_for):
        return;
    if _grow_for.upgrading == Expansion.ID:
        _grow_for.cancel_upgrade();
        _refresh_grow(_grow_for);
    else:
        World.instance.tools.start_expand(_grow_for);

# A field's "harvest now": a cold snap is coming, or the season is ending, so take what has grown.
func _refresh_early(obj:Variant) -> void:
    _field = obj as Field if obj is Field else null;
    _early_btn.visible = _field != null and _field.is_complete();
    if not _early_btn.visible:
        return;
    _early_btn.text = "Stop harvesting early" if _field.harvest_early else "Harvest everything now";
    _early_btn.tooltip_text = "Farmers take every growing plot for 70% of the share that has grown, and nothing is sown until they are done. Use it when a frost is coming: a frozen crop gives the same 70% but is lost after a day.";

func _on_early() -> void:
    if _field != null and World.alive(_field):
        _field.harvest_early = not _field.harvest_early;
        _refresh_early(_field);

func _refresh_workers(obj:Variant) -> void:
    var b:Building = obj as Building if obj is Building else null;
    var prof:int = -1;
    if b != null and b.is_complete() and b.def.has("profession"):
        prof = JobManager.PROFESSION_NAMES.find(String(b.def["profession"]).capitalize());
    if prof < 0:
        _workers_box.visible = false;
        _workers_sig = "";
        return;
    var crew:Array[Pawn] = [];
    for p in World.instance.pawns:
        if p.profession == prof:
            crew.append(p);
    var sig:String = "%d:%s" % [prof, ",".join(crew.map(func(p:Pawn) -> String: return p.first_name))];
    _workers_box.visible = true;
    if sig != _workers_sig:
        _workers_sig = sig;
        for c in _workers_box.get_children():
            c.queue_free();
        var head:Label = Label.new();
        var plural:String = _plural(JobManager.PROFESSION_NAMES[prof]);
        head.text = "%s (%d), click to find:" % [plural, crew.size()] if not crew.is_empty() else "No %s yet: raise the number with + in the Professions panel." % plural.to_lower();
        head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;
        head.custom_minimum_size.x = 280;
        _workers_box.add_child(head);
        for p in crew:
            var btn:Button = Button.new();
            btn.focus_mode = Control.FOCUS_NONE;
            btn.alignment = HORIZONTAL_ALIGNMENT_LEFT;
            btn.set_meta("pawn", p);
            btn.pressed.connect(_locate.bind(p));
            _workers_box.add_child(btn);
    for btn in _workers_box.get_children():       # their status changes every few seconds: update in place
        if btn is Button:
            var p:Pawn = btn.get_meta("pawn");
            if World.alive(p):
                btn.text = "%s: %s" % [p.first_name, p.status];

# A school lists the children studying there right now, each a button that finds them.
func _refresh_pupils(obj:Variant) -> void:
    var b:Building = obj as Building if obj is Building else null;
    if b == null or not b.is_complete() or not b.def.has("school_capacity"):
        _pupils_box.visible = false;
        _pupils_sig = "";
        return;
    var pupils:Array[Pawn] = [];
    for p in World.instance.pawns:
        if p.task != null and p.task.kind == &"school" and is_same(p.task.target, b):
            pupils.append(p);
    var sig:String = ",".join(pupils.map(func(p:Pawn) -> String: return p.first_name));
    _pupils_box.visible = true;
    if sig == _pupils_sig and _pupils_box.get_child_count() > 0:
        return;
    _pupils_sig = sig;
    for c in _pupils_box.get_children():
        c.queue_free();
    var head:Label = Label.new();
    head.text = "Students (%d / %d), click to find:" % [pupils.size(), b.def["school_capacity"]] if not pupils.is_empty() else "No students at the school right now (classes are 8:00 to 16:00).";
    head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;
    head.custom_minimum_size.x = 280;
    _pupils_box.add_child(head);
    for p in pupils:
        var btn:Button = Button.new();
        btn.focus_mode = Control.FOCUS_NONE;
        btn.alignment = HORIZONTAL_ALIGNMENT_LEFT;
        btn.text = "%s (age %d)" % [p.first_name, int(p.age)];
        btn.pressed.connect(_locate.bind(p));
        _pupils_box.add_child(btn);

func _plural(name:String) -> String:
    return name.trim_suffix("man") + "men" if name.ends_with("man") else name + "s";

func _locate(p:Pawn) -> void:
    if not World.alive(p):
        return;
    var w:World = World.instance;
    w.tools.select(p);
    w.camera_rig.focus_on(Vector3(p.position.x, 0.0, p.position.z));
