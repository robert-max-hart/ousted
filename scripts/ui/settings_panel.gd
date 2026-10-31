# ----------------------------------------------------------------
# SettingsPanel
#     A modal window for the graphics and window settings (see
#     Settings). Changes apply and save at once. Used by the Esc menu
#     and the title screen.
# ----------------------------------------------------------------
class_name SettingsPanel extends Control;

signal closed;

# --------------------------------
func _init() -> void:
    Settings.ensure_loaded();
    set_anchors_preset(Control.PRESET_FULL_RECT);
    mouse_filter = Control.MOUSE_FILTER_STOP;
    var dim:ColorRect = ColorRect.new();
    dim.color = Color(0.0, 0.0, 0.0, 0.45);
    dim.set_anchors_preset(Control.PRESET_FULL_RECT);
    dim.mouse_filter = Control.MOUSE_FILTER_IGNORE;
    add_child(dim);
    var center:CenterContainer = CenterContainer.new();
    center.set_anchors_preset(Control.PRESET_FULL_RECT);
    center.mouse_filter = Control.MOUSE_FILTER_IGNORE;
    add_child(center);
    var panel:PanelContainer = PanelContainer.new();
    var style:StyleBoxFlat = StyleBoxFlat.new();
    style.bg_color = Color(0.08, 0.07, 0.06, 0.92);
    style.set_corner_radius_all(6);
    style.set_content_margin_all(12);
    panel.add_theme_stylebox_override("panel", style);
    center.add_child(panel);
    var col:VBoxContainer = VBoxContainer.new();
    col.custom_minimum_size = Vector2(380, 0);
    col.add_theme_constant_override("separation", 8);
    panel.add_child(col);
    var title:Label = Label.new();
    title.text = "Settings";
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;
    col.add_child(title);

    var grass:OptionButton = OptionButton.new();
    grass.focus_mode = Control.FOCUS_NONE;
    for n in Settings.GRASS_NAMES:
        grass.add_item(n);
    grass.select(Settings.grass);
    grass.item_selected.connect(func(i:int) -> void: Settings.set_value("grass", i));
    _row(col, "Grass tufts", grass, "Fewer tufts help the frame rate. Takes a moment to redraw.");
    _check(col, "Shadows", Settings.shadows, "shadows", "Sun and moon shadows. Off helps weak graphics cards.");
    _check(col, "Fullscreen", Settings.fullscreen, "fullscreen", "");
    _check(col, "Vertical sync", Settings.vsync, "vsync", "Stops tearing; turn off if the game feels laggy.");
    var back:Button = Button.new();
    back.text = "Back";
    back.focus_mode = Control.FOCUS_NONE;
    back.pressed.connect(close);
    col.add_child(back);

func _row(col:Container, text:String, control:Control, tip:String) -> void:
    var row:HBoxContainer = HBoxContainer.new();
    var l:Label = Label.new();
    l.text = text;
    l.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
    l.tooltip_text = tip;
    l.mouse_filter = Control.MOUSE_FILTER_PASS;
    row.add_child(l);
    row.add_child(control);
    col.add_child(row);

func _check(col:Container, text:String, on:bool, key:String, tip:String) -> void:
    var c:CheckBox = CheckBox.new();
    c.text = text;
    c.button_pressed = on;
    c.focus_mode = Control.FOCUS_NONE;
    c.tooltip_text = tip;
    c.toggled.connect(func(v:bool) -> void: Settings.set_value(key, v));
    col.add_child(c);

func close() -> void:
    closed.emit();
    queue_free();

func _input(ev:InputEvent) -> void:
    if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
        get_viewport().set_input_as_handled();
        close();
