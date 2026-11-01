# ----------------------------------------------------------------
# CitizensPanel
#     Every citizen in a table: name (a button that selects them and
#     moves the camera to them), age, profession, what they are doing,
#     how happy they are and how sick. Click a column heading to sort by it
#     (again to reverse). Opened from the top bar's Citizens
#     button. Idle citizens are highlighted.
# ----------------------------------------------------------------
class_name CitizensPanel extends PanelContainer;

const COLUMNS:Array[String] = ["Name", "Age", "Job", "Doing", "Happy", "Sick"];
const REFRESH:float = 0.5;

var _grid       :GridContainer;
var _scroll     :ScrollContainer;
var _timer      :float = 0.0;
var _sig        :String = "";
var _sort_col   :int = 0;
var _sort_desc  :bool = false;
var _heads      :Array[Button] = [];       # the column headings: made once, so a click is never lost to a rebuild
var _cells      :Array = [];       # per citizen: [pawn, name button, age, job, doing, happy, sick]

func setup() -> void:
    visible = false;
    set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);
    offset_left = 256.0;
    offset_top = 48.0;
    custom_minimum_size = Vector2(530, 0);
    mouse_filter = Control.MOUSE_FILTER_STOP;
    add_theme_stylebox_override("panel", UITheme.panel_box(0.92, 6, 8));
    PanelMover.make_movable(self, &"citizens");
    var col:VBoxContainer = VBoxContainer.new();
    add_child(col);
    var title:Label = Label.new();
    title.text = "Citizens";
    col.add_child(title);
    _scroll = ScrollContainer.new();
    _scroll.custom_minimum_size = Vector2(510, 300);
    _scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED;
    col.add_child(_scroll);
    _grid = GridContainer.new();
    _grid.columns = COLUMNS.size();
    _grid.add_theme_constant_override("h_separation", 12);
    _grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
    _scroll.add_child(_grid);
    for i in COLUMNS.size():
        var head:Button = Button.new();
        head.flat = true;
        head.alignment = HORIZONTAL_ALIGNMENT_LEFT;
        head.focus_mode = Control.FOCUS_NONE;
        head.add_theme_color_override("font_color", Color(0.7, 0.7, 0.65));
        head.pressed.connect(_sort_by.bind(i));
        _grid.add_child(head);
        _heads.append(head);
    _set_heads();

func _process(delta:float) -> void:
    if not visible:
        return;
    _timer -= delta;
    if _timer > 0.0:
        return;
    _timer = REFRESH;
    _refresh();

func _refresh() -> void:
    var pawns:Array[Pawn] = World.instance.pawns.duplicate();
    pawns.sort_custom(_before);
    var ids:Array = pawns.map(func(p:Pawn) -> int: return p.get_instance_id());
    ids.sort();
    var sig:String = ",".join(ids.map(func(i:int) -> String: return str(i)));
    if sig != _sig:
        _sig = sig;
        _rebuild(pawns);
    else:
        _reorder(pawns);
    for row in _cells:
        var p:Pawn = row[0];
        if not World.alive(p):
            continue;
        (row[2] as Label).text = "%d" % int(p.age);
        (row[3] as Label).text = p.profession_name() if p.is_adult() else p.stage_name().capitalize();
        (row[4] as Label).text = p.status;
        (row[5] as Label).text = "-" if p.is_baby() else "%d%%" % roundi(p.happiness() * 100.0);
        (row[6] as Label).text = "-" if p.illness <= 0.0 else "%d%%" % roundi(p.illness * 100.0);
        (row[6] as Label).add_theme_color_override("font_color", Color(0.55, 0.85, 0.4) if p.illness > 0.0 else Color(0.6, 0.6, 0.6));
        (row[4] as Label).add_theme_color_override("font_color", Color(1.0, 0.85, 0.4) if p.is_idle() else Color.WHITE);

# Orders two citizens by the chosen column (name breaks ties), reversed when sorting down.
func _before(a:Pawn, b:Pawn) -> bool:
    var ka:Variant = _key(a);
    var kb:Variant = _key(b);
    if ka == kb:
        if a.first_name == b.first_name:
            return a.get_instance_id() < b.get_instance_id();
        return a.first_name < b.first_name;
    return (ka > kb) if _sort_desc else (ka < kb);

func _key(p:Pawn) -> Variant:
    match _sort_col:
        1:
            return p.age;
        2:
            return p.profession_name() if p.is_adult() else p.stage_name().capitalize();
        3:
            return p.status;
        4:
            return -1.0 if p.is_baby() else p.happiness();
        5:
            return p.illness;
    return p.first_name;

func _sort_by(col:int) -> void:
    _sort_desc = not _sort_desc if col == _sort_col else false;
    _sort_col = col;
    _set_heads();
    _timer = 0.0;

# The same citizens, maybe in a new order (a changed sort, or values that moved): the rows are moved, not made again,
# so a click on a heading or a name is never lost to a row being replaced under the cursor.
func _reorder(pawns:Array[Pawn]) -> void:
    var by_pawn:Dictionary = {};
    for row in _cells:
        by_pawn[row[0]] = row;
    var ordered:Array = [];
    for i in pawns.size():
        var row:Array = by_pawn[pawns[i]];
        ordered.append(row);
        for k in range(1, row.size()):
            (row[k] as Node).get_parent().move_child(row[k], COLUMNS.size() + i * COLUMNS.size() + (k - 1));
    _cells = ordered;

func _set_heads() -> void:
    for i in COLUMNS.size():
        _heads[i].text = COLUMNS[i] + ((" v" if _sort_desc else " ^") if i == _sort_col else "");

func _rebuild(pawns:Array[Pawn]) -> void:
    for c in _grid.get_children():
        if not _heads.has(c):
            _grid.remove_child(c);         # (out of the grid now, not at the end of the frame, so the new rows lay out cleanly)
            c.queue_free();
    _cells.clear();
    for p in pawns:
        var btn:Button = Button.new();
        btn.text = p.first_name;
        btn.flat = true;
        btn.alignment = HORIZONTAL_ALIGNMENT_LEFT;
        btn.focus_mode = Control.FOCUS_NONE;
        btn.pressed.connect(_locate.bind(p));
        _grid.add_child(btn);
        var row:Array = [p, btn];
        for i in 5:
            var l:Label = Label.new();
            l.clip_text = true;
            l.custom_minimum_size.x = [28, 80, 160, 40, 40][i];
            _grid.add_child(l);
            row.append(l);
        _cells.append(row);

func _locate(p:Pawn) -> void:
    if not World.alive(p):
        return;
    var w:World = World.instance;
    w.tools.select(p);
    w.camera_rig.focus_on(Vector3(p.position.x, 0.0, p.position.z));
