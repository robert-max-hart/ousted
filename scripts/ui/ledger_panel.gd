# ----------------------------------------------------------------
# Ledger panel
#     Two tabs over World.ledger: line graphs of the daily samples
#     (one set of lines at a time) and the history of events, newest
#     first. Opened from the Town Hall inspector once it has Governance.
# ----------------------------------------------------------------
class_name LedgerPanel extends PanelContainer;

const SUM_DAYS:int = 8;        # lines marked as sums show the total of this many days up to each day (a season)

# Each graph: a name and its lines (sample key, label, colour, optionally true for a rolling sum).
const GRAPHS:Array[Dictionary] = [
    {"name": "Population", "lines": [["pop", "Total", Color(0.95, 0.95, 0.9)], ["adults", "Adults", Color(0.45, 0.75, 0.95)], ["children", "Children", Color(0.95, 0.8, 0.35)], ["babies", "Babies", Color(0.95, 0.5, 0.65)]]},
    {"name": "Food", "lines": [["food", "Food", Color(0.9, 0.78, 0.35)], ["firewood", "Firewood", Color(0.75, 0.5, 0.28)]]},
    {"name": "Happiness", "lines": [["mood", "Average happiness (%)", Color(0.55, 0.85, 0.5)]]},
    {"name": "Births and deaths", "lines": [["births", "Births (per 8 days)", Color(0.55, 0.85, 0.5), true], ["deaths", "Deaths (per 8 days)", Color(0.9, 0.4, 0.4), true]]},
];

var _ledger:Ledger;
var _chart:LedgerChart;
var _legend:HBoxContainer;
var _graph_btns:Array[Button] = [];
var _history:VBoxContainer;
var _shown_events:int = -1;
var _timer:float = 0.0;

func setup(ledger:Ledger) -> void:
    _ledger = ledger;
    visible = false;
    # between the jobs panel on the left and the inspector on the right
    set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT);
    offset_left = 252.0;
    offset_right = 252.0 + 510.0;
    custom_minimum_size = Vector2(510, 360);
    grow_vertical = Control.GROW_DIRECTION_BOTH;
    mouse_filter = Control.MOUSE_FILTER_STOP;
    var style:StyleBoxFlat = StyleBoxFlat.new();
    style.bg_color = Color(0.08, 0.07, 0.06, 1.0);
    style.set_corner_radius_all(6);
    style.set_content_margin_all(10);
    add_theme_stylebox_override("panel", style);
    var col:VBoxContainer = VBoxContainer.new();
    add_child(col);
    var head:HBoxContainer = HBoxContainer.new();
    col.add_child(head);
    var title:Label = Label.new();
    title.text = "Ledger";
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
    head.add_child(title);
    var close:Button = Button.new();
    close.text = "Close";
    close.focus_mode = Control.FOCUS_NONE;
    close.pressed.connect(func() -> void: visible = false);
    head.add_child(close);
    var tabs:TabContainer = TabContainer.new();
    tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL;
    col.add_child(tabs);
    tabs.add_child(_build_graphs());
    tabs.set_tab_title(0, "Graphs");
    tabs.add_child(_build_history());
    tabs.set_tab_title(1, "History");

func _build_graphs() -> Control:
    var box:VBoxContainer = VBoxContainer.new();
    var row:HBoxContainer = HBoxContainer.new();
    box.add_child(row);
    for i in GRAPHS.size():
        var b:Button = Button.new();
        b.text = GRAPHS[i]["name"];
        b.toggle_mode = true;
        b.focus_mode = Control.FOCUS_NONE;
        b.pressed.connect(_show_graph.bind(i));
        row.add_child(b);
        _graph_btns.append(b);
    _chart = LedgerChart.new();
    _chart.size_flags_vertical = Control.SIZE_EXPAND_FILL;
    _chart.custom_minimum_size = Vector2(470, 220);
    box.add_child(_chart);
    _legend = HBoxContainer.new();
    _legend.add_theme_constant_override("separation", 14);
    box.add_child(_legend);
    _show_graph(0);
    return box;

func _build_history() -> Control:
    var scroll:ScrollContainer = ScrollContainer.new();
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED;
    _history = VBoxContainer.new();
    _history.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
    scroll.add_child(_history);
    return scroll;

func _show_graph(i:int) -> void:
    for j in _graph_btns.size():
        _graph_btns[j].set_pressed_no_signal(j == i);
    var lines:Array = GRAPHS[i]["lines"];
    _chart.set_data(_ledger, lines);
    for c in _legend.get_children():
        _legend.remove_child(c);
        c.queue_free();
    for line in lines:
        var l:Label = Label.new();
        l.text = "■ " + line[1];
        l.add_theme_color_override("font_color", line[2]);
        _legend.add_child(l);

func open() -> void:
    visible = true;
    _shown_events = -1;
    _refresh_history();
    _chart.queue_redraw();

func _process(delta:float) -> void:
    if not visible:
        return;
    _timer -= delta;
    if _timer <= 0.0:
        _timer = 1.0;
        _refresh_history();
        _chart.queue_redraw();

# Newest first. Rebuilt only when an event has been added.
func _refresh_history() -> void:
    if _ledger.events.size() == _shown_events:
        return;
    _shown_events = _ledger.events.size();
    for c in _history.get_children():
        _history.remove_child(c);
        c.queue_free();
    if _ledger.events.is_empty():
        var none:Label = Label.new();
        none.text = "Nothing has happened yet.";
        _history.add_child(none);
        return;
    for i in range(_ledger.events.size() - 1, -1, -1):
        var e:Dictionary = _ledger.events[i];
        var l:Label = Label.new();
        l.text = "%s: %s" % [e["when"], e["text"]];
        l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;
        l.custom_minimum_size.x = 460;
        _history.add_child(l);

# --------------------------------
# The line chart: one line per series over the recorded days, a grid with the top value on the left, and a
# marker at the start of each season.
class LedgerChart extends Control:
    var _ledger:Ledger;
    var _lines:Array = [];

    func set_data(ledger:Ledger, lines:Array) -> void:
        _ledger = ledger;
        _lines = lines;
        queue_redraw();

    func _draw() -> void:
        var font:Font = get_theme_default_font();
        var size_px:int = 12;
        var left:float = 44.0;
        var area:Rect2 = Rect2(left, 6.0, size.x - left - 6.0, size.y - 24.0);
        draw_rect(area, Color(0, 0, 0, 0.25));
        var samples:Array = _ledger.samples;
        if samples.size() < 2:
            draw_string(font, area.position + Vector2(10, 24), "Waiting for a second day of records.", HORIZONTAL_ALIGNMENT_LEFT, -1, size_px);
            return;
        var values:Array = [];       # per line, one value per sample
        var top:float = 4.0;
        for line in _lines:
            var v:Array[float] = _values(samples, line);
            values.append(v);
            for x in v:
                top = maxf(top, x);
        top = _nice_top(top);
        for k in range(0, 5):
            var y:float = area.end.y - area.size.y * k / 4.0;
            draw_line(Vector2(area.position.x, y), Vector2(area.end.x, y), Color(1, 1, 1, 0.12));
            draw_string(font, Vector2(2.0, y + 4.0), str(roundi(top * k / 4.0)), HORIZONTAL_ALIGNMENT_LEFT, left - 6.0, size_px);
        var first:int = samples[0]["day"];
        var span:float = maxf(1.0, float(samples[samples.size() - 1]["day"] - first));
        for s in samples:
            if s["day"] % GameClock.DAYS_PER_SEASON == 0:
                var x:float = area.position.x + area.size.x * (s["day"] - first) / span;
                draw_line(Vector2(x, area.position.y), Vector2(x, area.end.y), Color(1, 1, 1, 0.08));
                var season:int = (s["day"] / GameClock.DAYS_PER_SEASON) % 4;
                draw_string(font, Vector2(x + 2.0, area.end.y + 14.0), GameClock.SEASON_NAMES[season].substr(0, 3), HORIZONTAL_ALIGNMENT_LEFT, -1, size_px - 1, Color(1, 1, 1, 0.5));
        for k in _lines.size():
            var pts:PackedVector2Array = [];
            for j in samples.size():
                pts.append(Vector2(area.position.x + area.size.x * (samples[j]["day"] - first) / span, area.end.y - area.size.y * clampf(values[k][j] / top, 0.0, 1.0)));
            draw_polyline(pts, _lines[k][2], 2.0, true);

    # A line's value for every sample: the sample itself, or for a sum the last SUM_DAYS samples added up.
    func _values(samples:Array, line:Array) -> Array[float]:
        var out:Array[float] = [];
        var running:float = 0.0;
        for j in samples.size():
            running += float(samples[j][line[0]]);
            if line.size() > 3 and line[3]:
                if j >= SUM_DAYS:
                    running -= float(samples[j - SUM_DAYS][line[0]]);
                out.append(running);
            else:
                out.append(float(samples[j][line[0]]));
                running = 0.0;
        return out;

    # Rounds the top of the scale up to 4, 8, 12 or 20 times a power of ten, so the four grid steps are whole numbers.
    func _nice_top(v:float) -> float:
        var base:float = 1.0;
        while true:
            for m in [4.0, 8.0, 12.0, 20.0]:
                if v <= m * base:
                    return m * base;
            base *= 10.0;
        return v;
