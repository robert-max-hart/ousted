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
var _workers_box:VBoxContainer;
var _workers_sig:String = "";
var _node       :ResourceNode;

func _init() -> void:
    _mark_btn = Button.new();
    _mark_btn.focus_mode = Control.FOCUS_NONE;
    _mark_btn.visible = false;
    _mark_btn.pressed.connect(_on_mark);
    add_child(_mark_btn);
    _workers_box = VBoxContainer.new();
    _workers_box.visible = false;
    add_child(_workers_box);

func refresh(obj:Variant) -> void:
    _refresh_mark(obj);
    _refresh_workers(obj);

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
        head.text = "%ss (%d), click to find:" % [JobManager.PROFESSION_NAMES[prof], crew.size()] if not crew.is_empty() else "No %ss yet: raise the number with + in the Professions panel." % JobManager.PROFESSION_NAMES[prof].to_lower();
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

func _locate(p:Pawn) -> void:
    if not World.alive(p):
        return;
    var w:World = World.instance;
    w.tools.select(p);
    w.camera_rig.focus_on(Vector3(p.position.x, 0.0, p.position.z));
