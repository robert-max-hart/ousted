# ----------------------------------------------------------------
# CitizensPanel
#     Every citizen in a table: name (a button that selects them and
#     moves the camera to them), age, profession, what they are doing
#     and how happy they are. Click a column heading to sort by it
#     (again to reverse). Opened from the top bar's Citizens
#     button. Idle citizens are highlighted.
# ----------------------------------------------------------------
class_name CitizensPanel extends PanelContainer;

const COLUMNS:Array[String] = ["Name", "Age", "Job", "Doing", "Happy"];
const REFRESH:float = 0.5;

var _grid       :GridContainer;
var _scroll     :ScrollContainer;
var _timer      :float = 0.0;
var _sig        :String = "";
var _sort_col   :int = 0;
var _sort_desc  :bool = false;
var _cells      :Array = [];       # per citizen: [pawn, name button, age, job, doing, happy]

func setup() -> void:
    visible = false;
    set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);
    offset_left = 256.0;
    offset_top = 48.0;
    custom_minimum_size = Vector2(470, 0);
    mouse_filter = Control.MOUSE_FILTER_STOP;
    var style:StyleBoxFlat = StyleBoxFlat.new();
    style.bg_color = Color(0.08, 0.07, 0.06, 0.92);
    style.set_corner_radius_all(6);
    style.set_content_margin_all(8);
    add_theme_stylebox_override("panel", style);
    PanelMover.make_movable(self, &"citizens");
    var col:VBoxContainer = VBoxContainer.new();
    add_child(col);
    var title:Label = Label.new();
    title.text = "Citizens";
    col.add_child(title);
    _scroll = ScrollContainer.new();
    _scroll.custom_minimum_size = Vector2(450, 300);
    _scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED;
    col.add_child(_scroll);
    _grid = GridContainer.new();
    _grid.columns = COLUMNS.size();
    _grid.add_theme_constant_override("h_separation", 12);
    _grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
    _scroll.add_child(_grid);

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
    var sig:String = "%d%s %s" % [_sort_col, _sort_desc, ",".join(pawns.map(func(p:Pawn) -> String: return p.first_name))];
    if sig != _sig:
        _sig = sig;
        _rebuild(pawns);
    for row in _cells:
        var p:Pawn = row[0];
        if not World.alive(p):
            continue;
        (row[2] as Label).text = "%d" % int(p.age);
        (row[3] as Label).text = p.profession_name() if p.is_adult() else p.stage_name().capitalize();
        (row[4] as Label).text = p.status;
        (row[5] as Label).text = "-" if p.is_baby() else "%d%%" % roundi(p.happiness() * 100.0);
        (row[4] as Label).add_theme_color_override("font_color", Color(1.0, 0.85, 0.4) if p.is_idle() else Color.WHITE);

# Orders two citizens by the chosen column (name breaks ties), reversed when sorting down.
func _before(a:Pawn, b:Pawn) -> bool:
    var ka:Variant = _key(a);
    var kb:Variant = _key(b);
    if ka == kb:
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
    return p.first_name;

func _sort_by(col:int) -> void:
    _sort_desc = not _sort_desc if col == _sort_col else false;
    _sort_col = col;
    _timer = 0.0;

func _rebuild(pawns:Array[Pawn]) -> void:
    for c in _grid.get_children():
        c.queue_free();
    _cells.clear();
    for i in COLUMNS.size():
        var head:Button = Button.new();
        head.text = COLUMNS[i] + ((" v" if _sort_desc else " ^") if i == _sort_col else "");
        head.flat = true;
        head.alignment = HORIZONTAL_ALIGNMENT_LEFT;
        head.focus_mode = Control.FOCUS_NONE;
        head.add_theme_color_override("font_color", Color(0.7, 0.7, 0.65));
        head.pressed.connect(_sort_by.bind(i));
        _grid.add_child(head);
    for p in pawns:
        var btn:Button = Button.new();
        btn.text = p.first_name;
        btn.flat = true;
        btn.alignment = HORIZONTAL_ALIGNMENT_LEFT;
        btn.focus_mode = Control.FOCUS_NONE;
        btn.pressed.connect(_locate.bind(p));
        _grid.add_child(btn);
        var row:Array = [p, btn];
        for i in 4:
            var l:Label = Label.new();
            l.clip_text = true;
            l.custom_minimum_size.x = [28, 80, 160, 40][i];
            _grid.add_child(l);
            row.append(l);
        _cells.append(row);

func _locate(p:Pawn) -> void:
    if not World.alive(p):
        return;
    var w:World = World.instance;
    w.tools.select(p);
    w.camera_rig.focus_on(Vector3(p.position.x, 0.0, p.position.z));
