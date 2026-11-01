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
    panel.add_theme_stylebox_override("panel", UITheme.panel_box(1.0, 6, 12));
    center.add_child(panel);
    var col:VBoxContainer = VBoxContainer.new();
    col.custom_minimum_size = Vector2(380, 0);
    col.add_theme_constant_override("separation", 8);
    panel.add_child(col);
    var title:Label = Label.new();
    title.text = "Settings";
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;
    col.add_child(title);

    _volume(col, "Master volume", Settings.volume_master, "volume_master", "");
    _volume(col, "Effects volume", Settings.volume_sfx, "volume_sfx", "Work sounds, clicks and the chimes for events.");
    _volume(col, "Ambience volume", Settings.volume_ambient, "volume_ambient", "Wind, rain, water, birds and crickets.");
    var grass:OptionButton = OptionButton.new();
    grass.focus_mode = Control.FOCUS_NONE;
    for n in Settings.GRASS_NAMES:
        grass.add_item(n);
    grass.select(Settings.grass);
    grass.item_selected.connect(func(i:int) -> void: Settings.set_value("grass", i));
    _row(col, "Grass tufts", grass, "Fewer tufts help the frame rate. Takes a moment to redraw.");
    var water:OptionButton = OptionButton.new();
    water.focus_mode = Control.FOCUS_NONE;
    for n in Settings.WATER_NAMES:
        water.add_item(n);
    water.select(Settings.water);
    water.item_selected.connect(func(i:int) -> void: Settings.set_value("water", i));
    _row(col, "Water detail", water, "Simple is a flat tint. Medium adds swells and ripples; Full adds a second ripple layer and shore foam.");
    var dist:OptionButton = OptionButton.new();
    dist.focus_mode = Control.FOCUS_NONE;
    for n in Settings.DISTANCE_NAMES:
        dist.add_item(n);
    dist.select(Settings.tree_distance);
    dist.item_selected.connect(func(i:int) -> void: Settings.set_value("tree_distance", i));
    _row(col, "Tree and crop distance", dist, "How far away trees, bushes, rocks and crops are drawn. Near is the lightest on the graphics card; Far draws them out to the horizon.");
    var detail:OptionButton = OptionButton.new();
    detail.focus_mode = Control.FOCUS_NONE;
    for n in Settings.DETAIL_NAMES:
        detail.add_item(n);
    detail.select(Settings.model_detail);
    detail.item_selected.connect(func(i:int) -> void: Settings.set_value("model_detail", i));
    _row(col, "Model detail", detail, "Reduced uses simpler trees, bushes, rocks and crops (fewer sides, leaves and stalks). Helps weak graphics cards.");
    _check(col, "Tree sway", Settings.sway, "sway", "Trees, bushes and hazel bend in the wind. Off helps weak graphics cards.");
    _check(col, "Grass sway", Settings.grass_sway, "grass_sway", "The grass tufts bend in the wind. Off helps weak graphics cards.");
    _check(col, "Ground detail", Settings.ground, "ground", "Grain on the ground and bands on steep slopes. Off shows the plain ground colour.");
    _check(col, "Snow edge detail", Settings.snow_edge, "snow_edge", "Ragged, patchy snow edges. Off makes snow an even cover.");
    _check(col, "Wispy cloud edges", Settings.wispy_clouds, "wispy_clouds", "The clouds round the map break up into dithered wisps at their edges. Off makes them solid, which is a little lighter on weak graphics cards.");
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

func _volume(col:Container, text:String, value:int, key:String, tip:String) -> void:
    var slider:HSlider = HSlider.new();
    slider.min_value = 0;
    slider.max_value = 100;
    slider.step = 5;
    slider.value = value;
    slider.custom_minimum_size = Vector2(150, 0);
    slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER;
    slider.focus_mode = Control.FOCUS_NONE;
    slider.value_changed.connect(func(v:float) -> void: Settings.set_value(key, int(v)));
    _row(col, text, slider, tip);

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
