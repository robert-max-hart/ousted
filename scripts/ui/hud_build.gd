# ----------------------------------------------------------------
# HudBuild
#     Builds the HUD's panels once at start: the top bar and its stock
#     figures, the build toolbar, the Professions panel, the Esc menu,
#     the Policies panel, the inspector and the event log. Everything
#     it makes is stored on the HUD, which keeps them up to date.
# ----------------------------------------------------------------
class_name HudBuild extends RefCounted;

static func _build_top_bar(hud:HUD, root:Control) -> void:
    var panel:PanelContainer = hud._panel(root);
    (panel.get_theme_stylebox("panel") as StyleBoxFlat).corner_radius_top_left = 0;          # flush with the top of the screen: square corners there
    (panel.get_theme_stylebox("panel") as StyleBoxFlat).corner_radius_top_right = 0;
    panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE);
    var row:HBoxContainer = HBoxContainer.new();
    row.add_theme_constant_override("separation", 8);
    panel.add_child(row);
    hud._date = Label.new();
    hud._date.custom_minimum_size.x = 155;
    row.add_child(hud._date);
    hud._weather = Label.new();
    hud._weather.custom_minimum_size.x = 90;
    row.add_child(hud._weather);
    hud._stock = HBoxContainer.new();
    hud._stock.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
    hud._stock.clip_contents = true;           # a long stock line is cut off instead of pushing the speed buttons off-screen
    hud._stock.add_theme_constant_override("separation", 14);
    hud._stock.mouse_filter = Control.MOUSE_FILTER_PASS;
    row.add_child(hud._stock);
    for id in hud.SHOWN_ITEMS:
        HudBuild._stock_entry(hud, id, Defs.item_name(id));
    HudBuild._stock_entry(hud, &"food", "Food");
    HudBuild._stock_entry(hud, &"pop", "Citizens");
    HudBuild._stock_entry(hud, &"idle", "Citizens with nothing to do");
    HudBuild._stock_entry(hud, &"homeless", "Citizens with no home");
    # panel toggles: each button opens and closes its panel
    hud._jobs_toggle = hud._panel_toggle(row, "Jobs");
    hud._citizens_toggle = hud._panel_toggle(row, "Citizens");
    hud._log_toggle = hud._panel_toggle(row, "Log");
    hud._policies_btn = hud._panel_toggle(row, "Policies");
    hud._soil_toggle = hud._panel_toggle(row, "Soil");
    hud._soil_toggle.tooltip_text = "Show soil fertility on the ground (brown poor, green rich)";
    hud._soil_toggle.toggled.connect(func(on:bool) -> void:
        if on:
            hud._water_toggle.button_pressed = false;
        World.instance.terrain.set_soil_view(on);
        hud._refresh_info());
    hud._water_toggle = hud._panel_toggle(row, "Water");
    hud._water_toggle.tooltip_text = "Show how close the ground is to water. Blue-green ground is within reach of a water source (open water, a well or the Town Hall), so a Distillery or Potter's Workshop built there works; brown ground is too far.";
    hud._water_toggle.toggled.connect(func(on:bool) -> void:
        if on:
            hud._soil_toggle.button_pressed = false;
        World.instance.terrain.set_water_view(on));
    var labels:Array[String] = ["||", "1x", "2x", "5x", "10x"];
    for i in labels.size():
        var b:Button = Button.new();
        b.text = labels[i];
        b.toggle_mode = true;
        b.focus_mode = Control.FOCUS_NONE;
        b.custom_minimum_size.x = 36;
        b.pressed.connect(GameClock.set_speed.bind(i));
        row.add_child(b);
        hud._speed_btns.append(b);

# One figure in the top bar: its icon (StockIcons) and a number, with a tooltip.
static func _stock_entry(hud:HUD, id:StringName, tip:String) -> void:
    var box:HBoxContainer = HBoxContainer.new();
    box.add_theme_constant_override("separation", 4);
    box.mouse_filter = Control.MOUSE_FILTER_PASS;
    box.tooltip_text = tip;
    var icon:TextureRect = TextureRect.new();
    icon.texture = StockIcons.texture(id);
    icon.custom_minimum_size = Vector2(StockIcons.SIZE, StockIcons.SIZE);
    icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED;
    icon.mouse_filter = Control.MOUSE_FILTER_PASS;
    box.add_child(icon);
    var num:Label = Label.new();
    num.mouse_filter = Control.MOUSE_FILTER_PASS;
    box.add_child(num);
    hud._stock.add_child(box);
    hud._stock_vals[id] = num;

static func _build_toolbar(hud:HUD, root:Control) -> void:
    var panel:PanelContainer = hud._panel(root);
    hud._toolbar = panel;
    (panel.get_theme_stylebox("panel") as StyleBoxFlat).corner_radius_bottom_left = 0;       # flush with the bottom of the screen
    (panel.get_theme_stylebox("panel") as StyleBoxFlat).corner_radius_bottom_right = 0;
    panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE);
    panel.grow_vertical = Control.GROW_DIRECTION_BEGIN;
    var col:VBoxContainer = VBoxContainer.new();
    panel.add_child(col);
    hud._hint = Label.new();
    hud._hint.add_theme_color_override("font_color", Color(1.0, 0.92, 0.7));
    col.add_child(hud._hint);
    hud._harvest_opts = HBoxContainer.new();          # what the Harvest tool marks: switch kinds off to leave them standing
    hud._harvest_opts.visible = false;
    col.add_child(hud._harvest_opts);
    var opt_label:Label = Label.new();
    opt_label.text = "Harvest:";
    hud._harvest_opts.add_child(opt_label);
    for kind in [[&"trees", "Trees"], [&"stone", "Stone"], [&"iron", "Iron"]]:
        var cb:CheckBox = CheckBox.new();
        cb.text = kind[1];
        cb.button_pressed = true;
        cb.focus_mode = Control.FOCUS_NONE;
        var key:StringName = kind[0];
        cb.toggled.connect(func(on:bool) -> void: World.instance.tools.harvest_kinds[key] = on);
        hud._harvest_opts.add_child(cb);
    var row:HFlowContainer = HFlowContainer.new();     # wraps to a second line when the window is narrow
    hud._tool_row = row;
    col.add_child(row);
    var tools:PlayerTools = World.instance.tools;
    var group:ButtonGroup = ButtonGroup.new();
    group.allow_unpress = false;
    var modes:Array = [
        [PlayerTools.Mode.SELECT, "Select"], [PlayerTools.Mode.HARVEST, "Harvest"], [PlayerTools.Mode.FORAGE, "Forage"], [PlayerTools.Mode.PLANT, "Plant trees"],
        [PlayerTools.Mode.CHANNEL, "Channel"], [PlayerTools.Mode.DEMOLISH, "Demolish"], [PlayerTools.Mode.CANCEL, "Cancel"],
    ];
    for m in modes:
        var b:Button = hud._tool_button(row, group, m[1], PlayerTools.MODE_HINTS[m[0]]);
        b.pressed.connect(tools.set_mode.bind(m[0], &""));
        hud._tool_btns[str(m[0])] = b;
    row.add_child(VSeparator.new());
    # buildings are grouped: a button per category opens that category's buildings on a second line
    hud._build_row = HFlowContainer.new();
    col.add_child(hud._build_row);
    var cat_group:ButtonGroup = ButtonGroup.new();
    cat_group.allow_unpress = true;
    for ci in Defs.BUILD_CATEGORIES.size():
        var cb:Button = hud._tool_button(row, cat_group, Defs.BUILD_CATEGORIES[ci][0] + " >", "Show the %s buildings" % Defs.BUILD_CATEGORIES[ci][0].to_lower());
        cb.pressed.connect(hud._on_category_pressed.bind(ci));
        hud._cat_btns.append(cb);
        for id in Defs.BUILD_CATEGORIES[ci][1]:
            var def:Dictionary = Defs.BUILDINGS[id];
            var b:Button = hud._tool_button(hud._build_row, group, def["name"], "Cost: %s" % Defs.cost_string(def["cost"]));
            b.pressed.connect(tools.set_mode.bind(PlayerTools.Mode.BUILD, id));
            hud._tool_btns[String(id)] = b;
        if Defs.BUILD_CATEGORIES[ci][0] == "Civic":
            var rb:Button = hud._tool_button(hud._build_row, group, "Road", PlayerTools.MODE_HINTS[PlayerTools.Mode.ROAD]);
            rb.pressed.connect(tools.set_mode.bind(PlayerTools.Mode.ROAD, &""));
            hud._tool_btns[str(PlayerTools.Mode.ROAD)] = rb;
            hud._road_cat = ci;
    (hud._tool_btns[str(PlayerTools.Mode.SELECT)] as Button).set_pressed_no_signal(true);
    hud._apply_category();

static func _build_jobs_panel(hud:HUD, root:Control) -> void:
    var panel:PanelContainer = hud._panel(root, &"jobs");
    hud._jobs_panel = panel;
    panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);
    panel.offset_left = 8;
    panel.offset_top = 48;
    var col:VBoxContainer = VBoxContainer.new();
    panel.add_child(col);
    var title:Button = Button.new();
    title.text = "Professions  -";
    title.flat = true;
    title.alignment = HORIZONTAL_ALIGNMENT_LEFT;
    title.focus_mode = Control.FOCUS_NONE;
    title.tooltip_text = "Click to collapse or expand";
    col.add_child(title);
    var body:VBoxContainer = VBoxContainer.new();
    col.add_child(body);
    title.pressed.connect(func() -> void:
        body.visible = not body.visible;
        title.text = "Professions  -" if body.visible else "Professions  +";
        PanelMover.refit_height(panel));
    var jobs:JobManager = World.instance.jobs;
    for prof in JobManager.PROFESSION_NAMES.size():
        var row:HBoxContainer = HBoxContainer.new();
        body.add_child(row);
        var l:Label = Label.new();
        l.custom_minimum_size.x = 150;
        row.add_child(l);
        hud._jobs_rows.append(l);
        var flag:Label = Label.new();
        flag.text = "!";
        flag.visible = false;
        flag.mouse_filter = Control.MOUSE_FILTER_STOP;
        flag.add_theme_color_override("font_color", Color(1.0, 0.45, 0.3));
        hud._jobs_flags.append(flag);
        if prof == JobManager.Profession.GATHERER:
            row.visible = false;       # retired profession, see JobManager.Profession
            continue;
        if prof == JobManager.Profession.LABORER:
            l.tooltip_text = "Unassigned citizens. They harvest what is marked (trees, rocks, wild food), haul and help build.";
            l.mouse_filter = Control.MOUSE_FILTER_PASS;
            continue;
        for d in [-1, 1]:
            var b:Button = Button.new();
            b.text = "-" if d < 0 else "+";
            b.focus_mode = Control.FOCUS_NONE;
            b.custom_minimum_size.x = 28;
            b.pressed.connect(jobs.change_profession.bind(prof, d));
            row.add_child(b);
        row.add_child(flag);

static func _build_menu(hud:HUD, root:Control) -> void:
    hud._menu = Control.new();
    hud._menu.set_anchors_preset(Control.PRESET_FULL_RECT);
    hud._menu.mouse_filter = Control.MOUSE_FILTER_STOP;       # nothing under the menu gets clicked
    hud._menu.visible = false;
    root.add_child(hud._menu);
    var dim:ColorRect = ColorRect.new();
    dim.color = Color(0.0, 0.0, 0.0, 0.45);
    dim.set_anchors_preset(Control.PRESET_FULL_RECT);
    dim.mouse_filter = Control.MOUSE_FILTER_IGNORE;
    hud._menu.add_child(dim);
    var center:CenterContainer = CenterContainer.new();
    center.set_anchors_preset(Control.PRESET_FULL_RECT);
    center.mouse_filter = Control.MOUSE_FILTER_IGNORE;
    hud._menu.add_child(center);
    var panel:PanelContainer = hud._panel(center);
    var col:VBoxContainer = VBoxContainer.new();
    col.custom_minimum_size.x = 220;
    col.add_theme_constant_override("separation", 6);
    panel.add_child(col);
    var title:Label = Label.new();
    title.text = "Paused";
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;
    title.add_theme_font_size_override("font_size", hud.TITLE_FONT_SIZE);
    col.add_child(title);
    var seed_label:Label = Label.new();
    seed_label.text = "Map seed: %d" % World.instance.world_seed;
    seed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;
    col.add_child(seed_label);
    var items:Array = [
        ["Resume", hud.toggle_menu],
        ["Save (F5)", func() -> void: SaveGame.save(World.instance)],
        ["Load (F9)", func() -> void: hud.toggle_menu(); SaveGame.load_slot(World.instance)],
        ["Quit to title", func() -> void: hud.get_tree().change_scene_to_file(hud.TITLE_SCENE)],
        ["Quit game", func() -> void: hud.get_tree().quit()],
    ];
    for item in items:
        var b:Button = Button.new();
        b.text = item[0];
        b.focus_mode = Control.FOCUS_NONE;
        b.pressed.connect(item[1]);
        col.add_child(b);

# The colony-wide rules as check boxes in a panel of their own, opened by the top bar's Policies button.
static func _build_policies_panel(hud:HUD, root:Control) -> void:
    var panel:PanelContainer = hud._panel(root, &"policies");
    panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);
    panel.offset_left = 200;
    panel.offset_top = 48;
    panel.visible = false;
    var box:VBoxContainer = VBoxContainer.new();
    panel.add_child(box);
    var title:Label = Label.new();
    title.text = "Policies";
    box.add_child(title);
    hud._policies_btn.toggled.connect(func(on:bool) -> void: panel.visible = on);
    var policies:Policies = World.instance.policies;
    for id in Defs.POLICIES:
        var check:CheckBox = CheckBox.new();
        check.text = Defs.POLICIES[id]["name"];
        check.tooltip_text = Defs.POLICIES[id]["desc"];
        check.focus_mode = Control.FOCUS_NONE;
        check.set_pressed_no_signal(policies.is_on(id));
        var apply:Callable = func(on:bool, rule:StringName) -> void: policies.set_on(rule, on);
        check.toggled.connect(apply.bind(id));
        box.add_child(check);

static func _build_info_panel(hud:HUD, root:Control) -> void:
    hud._info = hud._panel(root, &"info");
    hud._info.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT);
    hud._info.grow_horizontal = Control.GROW_DIRECTION_BEGIN;
    hud._info.custom_minimum_size = Vector2(300, 0);
    hud._info.offset_right = -8;
    hud._info.offset_left = -308;
    hud._info.offset_top = 48;
    # long inspectors (a blacksmith with its settings and filters) scroll instead of running off screen
    hud._info_scroll = ScrollContainer.new();
    hud._info_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED;
    hud._info.add_child(hud._info_scroll);
    var col:VBoxContainer = VBoxContainer.new();
    col.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
    hud._info_scroll.add_child(col);
    hud._info_col = col;
    var title_row:HBoxContainer = HBoxContainer.new();
    col.add_child(title_row);
    hud._info_title = Label.new();
    hud._info_title.add_theme_font_size_override("font_size", hud.TITLE_FONT_SIZE);
    hud._info_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
    title_row.add_child(hud._info_title);
    hud._help_btn = Button.new();
    hud._help_btn.text = "?";
    hud._help_btn.toggle_mode = true;
    hud._help_btn.focus_mode = Control.FOCUS_NONE;
    hud._help_btn.tooltip_text = "Show or hide what this does";
    hud._help_btn.toggled.connect(func(on:bool) -> void:
        hud._help_open = on;
        hud._help_label.visible = on and hud._help_label.text != "";
        PanelMover.refit_height(hud._info));
    title_row.add_child(hud._help_btn);
    hud._help_label = Label.new();
    hud._help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;
    hud._help_label.custom_minimum_size.x = 300;
    hud._help_label.add_theme_color_override("font_color", Color(0.78, 0.8, 0.72));
    hud._help_label.visible = false;
    col.add_child(hud._help_label);
    hud._info_body = Label.new();
    hud._info_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;
    hud._info_body.custom_minimum_size.x = 300;
    col.add_child(hud._info_body);
    hud._info_btn = Button.new();
    hud._info_btn.focus_mode = Control.FOCUS_NONE;
    hud._info_btn.pressed.connect(hud._on_info_button);
    col.add_child(hud._info_btn);
    hud._crop_list = VBoxContainer.new();
    hud._crop_list.visible = false;
    col.add_child(hud._crop_list);
    hud._move_btn = Button.new();
    hud._move_btn.focus_mode = Control.FOCUS_NONE;
    hud._move_btn.visible = false;
    hud._move_btn.pressed.connect(func() -> void:
        var sel:Variant = World.instance.tools.selected;
        if sel is Building and World.alive(sel):
            World.instance.tools.start_relocate(sel));
    col.add_child(hud._move_btn);
    hud._copy_btn = Button.new();
    hud._copy_btn.text = "Build another";
    hud._copy_btn.tooltip_text = "Place another building of this kind (same size and facing)";
    hud._copy_btn.focus_mode = Control.FOCUS_NONE;
    hud._copy_btn.visible = false;
    hud._copy_btn.pressed.connect(func() -> void:
        var sel:Variant = World.instance.tools.selected;
        if sel is Building and World.alive(sel):
            World.instance.tools.start_copy(sel));
    col.add_child(hud._copy_btn);
    hud._extras = InspectorExtras.new();
    col.add_child(hud._extras);
    hud._site_box = VBoxContainer.new();
    hud._site_box.visible = false;
    col.add_child(hud._site_box);
    hud._cancel_btn = Button.new();
    hud._cancel_btn.text = "Cancel construction";
    hud._cancel_btn.focus_mode = Control.FOCUS_NONE;
    hud._cancel_btn.pressed.connect(hud._on_cancel_build);
    hud._site_box.add_child(hud._cancel_btn);
    var prio_title:Label = Label.new();
    prio_title.text = "Build priority:";
    hud._site_box.add_child(prio_title);
    var prio_row:HBoxContainer = HBoxContainer.new();
    hud._site_box.add_child(prio_row);
    for i in Building.PRIORITY_NAMES.size():
        var pb:Button = Button.new();
        pb.text = Building.PRIORITY_NAMES[i];
        pb.toggle_mode = true;
        pb.focus_mode = Control.FOCUS_NONE;
        pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
        pb.tooltip_text = "No hauling or building here" if i == 0 else "Builders and haulers serve higher priorities first";
        pb.pressed.connect(hud._on_priority_pressed.bind(i));
        prio_row.add_child(pb);
        hud._priority_btns.append(pb);
    hud._ledger_btn = Button.new();
    hud._ledger_btn.text = "Ledger";
    hud._ledger_btn.focus_mode = Control.FOCUS_NONE;
    hud._ledger_btn.visible = false;
    hud._ledger_btn.pressed.connect(func() -> void: hud._ledger_panel.open());
    col.add_child(hud._ledger_btn);
    hud._trade_btn = Button.new();
    hud._trade_btn.focus_mode = Control.FOCUS_NONE;
    hud._trade_btn.visible = false;
    hud._trade_btn.pressed.connect(func() -> void:
        var sel:Variant = World.instance.tools.selected;
        if sel is TradingPost:
            hud._trade_panel.open(sel));
    col.add_child(hud._trade_btn);
    hud._dismiss_btn = Button.new();
    hud._dismiss_btn.text = "Send the merchant away";
    hud._dismiss_btn.tooltip_text = "The merchant leaves now. An unfinished order lapses and its goods come back.";
    hud._dismiss_btn.focus_mode = Control.FOCUS_NONE;
    hud._dismiss_btn.visible = false;
    hud._dismiss_btn.pressed.connect(func() -> void:
        if World.instance.traders.present():
            hud._trade_panel.visible = false;
            World.instance.traders.depart());
    col.add_child(hud._dismiss_btn);
    hud._hold_btn = Button.new();
    hud._hold_btn.text = "Goods held for trade";
    hud._hold_btn.focus_mode = Control.FOCUS_NONE;
    hud._hold_btn.visible = false;
    hud._hold_btn.pressed.connect(func() -> void:
        var sel:Variant = World.instance.tools.selected;
        if sel is TradingPost:
            hud._hold_panel.open(sel));
    col.add_child(hud._hold_btn);
    hud._upgrade_box = VBoxContainer.new();
    hud._upgrade_box.visible = false;
    col.add_child(hud._upgrade_box);
    hud._controls_box = VBoxContainer.new();
    hud._controls_box.visible = false;
    col.add_child(hud._controls_box);
    hud._filter_box = VBoxContainer.new();
    hud._filter_box.visible = false;
    col.add_child(hud._filter_box);
    hud._filter_head = Button.new();
    hud._filter_head.flat = true;
    hud._filter_head.alignment = HORIZONTAL_ALIGNMENT_LEFT;
    hud._filter_head.focus_mode = Control.FOCUS_NONE;
    hud._filter_head.tooltip_text = "Click to choose which goods this store takes";
    hud._filter_box.add_child(hud._filter_head);
    hud._filter_flow = HFlowContainer.new();
    hud._filter_flow.visible = false;
    hud._filter_flow.add_theme_constant_override("h_separation", 3);
    hud._filter_flow.add_theme_constant_override("v_separation", 3);
    hud._filter_box.add_child(hud._filter_flow);
    hud._filter_head.pressed.connect(func() -> void:
        hud._filter_flow.visible = not hud._filter_flow.visible;
        if World.instance.tools.selected is Building:
            hud._update_filter_head(World.instance.tools.selected);
        PanelMover.refit_height(hud._info));
    for item in Defs.ITEMS:
        var check:Button = Button.new();       # a lit button is an item the store accepts
        check.text = Defs.item_name(item);
        check.toggle_mode = true;
        check.focus_mode = Control.FOCUS_NONE;
        check.add_theme_font_size_override("font_size", 11);
        check.toggled.connect(hud._on_filter_toggled.bind(item));
        hud._filter_flow.add_child(check);
        hud._filter_checks[item] = check;

static func _build_log(hud:HUD, root:Control) -> void:
    hud._log_panel = hud._panel(root, &"log");
    hud._log_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT);
    hud._log_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN;
    hud._log_panel.offset_left = 8;
    hud._log_panel.offset_right = 8 + hud.LOG_WIDTH;
    hud._log_panel.offset_top = -(96 + hud.LOG_HEIGHT);
    hud._log_panel.offset_bottom = -96;
    hud._log_panel.custom_minimum_size.x = hud.LOG_WIDTH;
    var col:VBoxContainer = VBoxContainer.new();
    hud._log_panel.add_child(col);
    var title:Button = Button.new();
    title.text = "Log  -";
    title.flat = true;
    title.alignment = HORIZONTAL_ALIGNMENT_LEFT;
    title.focus_mode = Control.FOCUS_NONE;
    title.tooltip_text = "Click to collapse or expand";
    col.add_child(title);
    hud._log_scroll = ScrollContainer.new();
    hud._log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED;
    hud._log_scroll.custom_minimum_size = Vector2(hud.LOG_WIDTH, hud.LOG_HEIGHT);
    col.add_child(hud._log_scroll);
    title.pressed.connect(func() -> void:
        hud._log_scroll.visible = not hud._log_scroll.visible;
        title.text = "Log  -" if hud._log_scroll.visible else "Log  +";
        PanelMover.refit_height(hud._log_panel);
        hud._scroll_log_to_end.call_deferred());
    hud._log = VBoxContainer.new();
    hud._log.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
    hud._log_scroll.add_child(hud._log);
