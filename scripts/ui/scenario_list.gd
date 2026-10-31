# ----------------------------------------------------------------
# ScenarioList
#     The title screen's scenario picker: the scenarios on the left, the
#     chosen one's description, setup and goals on the right, a check box
#     to draw a random map instead of the fixed one, and Start.
# ----------------------------------------------------------------
class_name ScenarioList extends Control;

signal chosen(id:StringName, randomize:bool);

var _selected:StringName = &"";
var _buttons :Dictionary = {};          # id -> Button
var _name    :Label;
var _desc    :Label;
var _setup   :Label;
var _goals   :Label;
var _done    :Label;
var _random  :CheckBox;
var _start   :Button;

func _init() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT);
    mouse_filter = Control.MOUSE_FILTER_STOP;
    var dim:ColorRect = ColorRect.new();
    dim.color = Color(0.0, 0.0, 0.0, 0.5);
    dim.set_anchors_preset(Control.PRESET_FULL_RECT);
    dim.mouse_filter = Control.MOUSE_FILTER_IGNORE;
    add_child(dim);
    var center:CenterContainer = CenterContainer.new();
    center.set_anchors_preset(Control.PRESET_FULL_RECT);
    center.mouse_filter = Control.MOUSE_FILTER_IGNORE;
    add_child(center);
    var panel:PanelContainer = PanelContainer.new();
    var style:StyleBoxFlat = StyleBoxFlat.new();
    style.bg_color = Color(0.08, 0.07, 0.06, 1.0);
    style.set_corner_radius_all(6);
    style.set_content_margin_all(14);
    panel.add_theme_stylebox_override("panel", style);
    center.add_child(panel);
    var outer:VBoxContainer = VBoxContainer.new();
    outer.add_theme_constant_override("separation", 8);
    panel.add_child(outer);
    var title:Label = Label.new();
    title.text = "Scenarios";
    title.add_theme_font_size_override("font_size", 22);
    title.add_theme_color_override("font_color", Color(0.95, 0.78, 0.25));
    outer.add_child(title);
    var row:HBoxContainer = HBoxContainer.new();
    row.add_theme_constant_override("separation", 14);
    outer.add_child(row);
    var list:VBoxContainer = VBoxContainer.new();
    list.custom_minimum_size.x = 230;
    list.add_theme_constant_override("separation", 4);
    row.add_child(list);
    for s in Scenarios.LIST:
        var b:Button = Button.new();
        b.toggle_mode = true;
        b.focus_mode = Control.FOCUS_NONE;
        b.alignment = HORIZONTAL_ALIGNMENT_LEFT;
        var days:int = Scenarios.done_days(s["id"]);
        b.text = "%s%s" % [s["name"], "   (done, %d days)" % days if days >= 0 else ""];
        var id:StringName = s["id"];
        b.pressed.connect(func() -> void: _select(id));
        list.add_child(b);
        _buttons[id] = b;
    var side:VBoxContainer = VBoxContainer.new();
    side.custom_minimum_size = Vector2(380, 0);
    side.add_theme_constant_override("separation", 8);
    row.add_child(side);
    _name = Label.new();
    _name.add_theme_font_size_override("font_size", HUD.TITLE_FONT_SIZE);
    side.add_child(_name);
    _desc = _wrapped(side, Color.WHITE);
    _setup = _wrapped(side, Color(0.7, 0.75, 0.8));
    _goals = _wrapped(side, Color(0.95, 0.85, 0.5));
    _done = _wrapped(side, Color(0.5, 0.9, 0.5));
    _random = CheckBox.new();
    _random.text = "Randomize the map";
    _random.tooltip_text = "Draw a new map for variety. Off: the scenario's own map, the same for everyone.";
    side.add_child(_random);
    var buttons:HBoxContainer = HBoxContainer.new();
    buttons.add_theme_constant_override("separation", 8);
    outer.add_child(buttons);
    var back:Button = Button.new();
    back.text = "Back";
    back.focus_mode = Control.FOCUS_NONE;
    back.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
    back.pressed.connect(close);
    buttons.add_child(back);
    _start = Button.new();
    _start.text = "Start";
    _start.focus_mode = Control.FOCUS_NONE;
    _start.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
    _start.pressed.connect(func() -> void: chosen.emit(_selected, _random.button_pressed));
    buttons.add_child(_start);
    _select(Scenarios.LIST[0]["id"]);

func _wrapped(side:Container, color:Color) -> Label:
    var l:Label = Label.new();
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;
    l.custom_minimum_size.x = 380;
    l.add_theme_color_override("font_color", color);
    side.add_child(l);
    return l;

func _select(id:StringName) -> void:
    _selected = id;
    for k in _buttons:
        (_buttons[k] as Button).set_pressed_no_signal(k == id);
    var s:Dictionary = Scenarios.find(id);
    var run:ScenarioRun = ScenarioRun.new(id);
    _name.text = s["name"];
    _desc.text = s["desc"];
    _setup.text = Scenarios.setup_text(s);
    var lines:PackedStringArray = ["Goals:"];
    for i in run.goals().size():
        lines.append("  - %s" % run.goal_text(i));
    _goals.text = "\n".join(lines);
    var days:int = Scenarios.done_days(id);
    _done.text = "Completed in %d days." % days if days >= 0 else "";
    _done.visible = days >= 0;

func close() -> void:
    queue_free();

func _input(ev:InputEvent) -> void:
    if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
        get_viewport().set_input_as_handled();
        close();
