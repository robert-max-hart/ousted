# ----------------------------------------------------------------
# HUD
#     Code-built prototype UI: top bar (date, weather, stock, speed),
#     bottom toolbar, profession counters, event log and the inspector.
# ----------------------------------------------------------------
class_name HUD extends CanvasLayer;

const SHOWN_ITEMS   :Array[StringName] = [&"wood", &"firewood", &"coal", &"stone", &"iron"];
const LOG_SECONDS   :float = 10.0;
const REFRESH_RATE  :float = 0.25;

var _date       :Label;
var _weather    :Label;
var _stock      :Label;
var _speed_btns :Array[Button] = [];
var _tool_btns  :Dictionary = {};       # key -> Button
var _jobs_rows  :Array[Label] = [];
var _log        :VBoxContainer;
var _hint       :Label;
var _toolbar    :PanelContainer;
var _info       :PanelContainer;
var _info_title :Label;
var _info_body  :Label;
var _info_btn   :Button;
var _move_btn   :Button;
var _policies_btn:Button;
var _filter_box :VBoxContainer;
var _controls_box:VBoxContainer;
var _info_scroll:ScrollContainer;
var _info_col:VBoxContainer;
var _upgrade_box:VBoxContainer;
var _upgrade_sig:String = "";             # what the upgrade buttons were last built for
var _controls_sig:String = "";
var _controls_for:Variant = null;       # the building the control widgets were built for
var _filter_checks:Dictionary = {};     # item -> CheckBox
var _refresh    :float = 0.0;

func _ready() -> void:
    var root:Control = Control.new();
    root.set_anchors_preset(Control.PRESET_FULL_RECT);
    root.mouse_filter = Control.MOUSE_FILTER_IGNORE;
    add_child(root);
    _build_top_bar(root);
    _build_toolbar(root);
    _build_jobs_panel(root);
    _build_info_panel(root);
    _build_log(root);

    var tools:PlayerTools = World.instance.tools;
    tools.mode_changed.connect(_on_mode_changed);
    tools.selection_changed.connect(_on_selection_changed);
    GameClock.speed_changed.connect(_on_speed_changed);
    _on_speed_changed(GameClock.speed_index);
    _on_selection_changed(null);
    _refresh_all();

func _process(delta:float) -> void:
    # the event log sits just above the toolbar, which grows a line when the window is narrow
    _log.offset_bottom = -(_toolbar.size.y + 8.0);
    _log.offset_top = _log.offset_bottom;
    _refresh -= delta;
    if _refresh <= 0.0:
        _refresh = REFRESH_RATE;
        _refresh_all();

func notify(msg:String) -> void:
    var l:Label = Label.new();
    l.text = "[%s %s] %s" % [GameClock.date_string(), GameClock.time_string(), msg];
    l.add_theme_color_override("font_shadow_color", Color.BLACK);
    _log.add_child(l);
    while _log.get_child_count() > 6:
        _log.get_child(0).free();
    var tween:Tween = l.create_tween();
    tween.tween_interval(LOG_SECONDS);
    tween.tween_property(l, "modulate:a", 0.0, 1.5);
    tween.tween_callback(l.queue_free);

# --------------------------------
# Refresh

func _refresh_all() -> void:
    var w:World = World.instance;
    _date.text = "%s   %s" % [GameClock.date_string(), GameClock.time_string()];
    _weather.text = "%s, %.0f C" % [Weather.description(), Weather.temperature];
    var parts:PackedStringArray = [];
    for item in SHOWN_ITEMS:
        parts.append("%s %d" % [Defs.item_name(item), Stock.amount(item)]);
    parts.append("Food %d" % Stock.food_total());
    var governed:bool = w.has_governance();
    _policies_btn.disabled = not governed;
    _policies_btn.tooltip_text = "Colony-wide rules" if governed else "Needs the Town Hall's Governance upgrade";
    if not governed and _policies_btn.button_pressed:
        _policies_btn.button_pressed = false;
    (_tool_btns["town_hall"] as Button).visible = not _town_hall_exists(w);
    parts.append("Pop %d" % w.pawns.size());
    var homeless:int = w.families.homeless_count();
    if homeless > 0:
        parts.append("Homeless %d" % homeless);
    _stock.text = "   ".join(parts);
    var food_tip:PackedStringArray = ["Storage: %d / %d" % [Stock.used(), Stock.capacity()]];
    for item in Defs.ITEMS:
        if Defs.ITEMS[item].get("food", false):
            food_tip.append("%s: %d" % [Defs.item_name(item), Stock.amount(item)]);
    _stock.tooltip_text = "\n".join(food_tip);
    for prof in JobManager.PROFESSION_NAMES.size():
        var have:int = w.jobs.count(prof);
        var want:int = w.jobs.target(prof);
        var short:String = " (want %d)" % want if prof != JobManager.Profession.LABORER and want > have else "";
        _jobs_rows[prof].text = "%s: %d%s" % [JobManager.PROFESSION_NAMES[prof], have, short];
    var tools:PlayerTools = w.tools;
    _hint.text = tools.hint + ("   " + tools.error if tools.error != "" else "");
    _refresh_info();

func _refresh_info() -> void:
    var obj:Variant = World.instance.tools.selected;
    if obj == null or not World.alive(obj):
        _info.visible = false;
        return;
    _info.visible = true;
    if obj is Pawn:
        _info_title.text = (obj as Pawn).first_name;
    else:
        _info_title.text = obj.display_name();
    _info_body.text = obj.info_text();
    _info_btn.visible = obj is Field;
    _refresh_relocate(obj);
    _refresh_filters(obj);
    _refresh_controls(obj);
    _refresh_upgrades(obj);
    if obj is Field:
        _info_btn.text = "Change crop (%s)" % (obj as Field).crop()["name"];
    const TOP_BAR:float = 48.0;
    const PANEL_PADDING:float = 40.0;      # panel margins, title and the gap above the toolbar
    # the toolbar grows a line when the window is narrow, so measure it
    var room:float = get_viewport().get_visible_rect().size.y - TOP_BAR - _toolbar.size.y - PANEL_PADDING;
    _info_scroll.custom_minimum_size.y = minf(_info_col.get_combined_minimum_size().y, room);

# The Relocate button for a finished building: disabled with the reason when it can't be moved now.
func _refresh_relocate(obj:Variant) -> void:
    var b:Building = obj as Building if obj is Building else null;
    var show:bool = b != null and b.def.get("relocatable", true) and b.is_complete();
    _move_btn.visible = show;
    if not show:
        return;
    var why:String = World.instance.relocation_block_reason(b);
    _move_btn.disabled = why != "";
    _move_btn.text = "Relocate (%s)" % why.to_lower() if why != "" else "Relocate (half the build cost)";

# Per-building settings (see the "controls" schema in Defs): a cycling choice, a toggle, or a
# production cap with - and + buttons.
func _refresh_controls(obj:Variant) -> void:
    var b:Building = obj as Building if obj is Building else null;
    var show:bool = b != null and b.is_complete() and b.def.has("controls");
    _controls_box.visible = show;
    if not show:
        _controls_for = null;
        return;
    var sig:String = str(b.upgrades_done.keys());
    if is_same(_controls_for, b) and sig == _controls_sig:
        return;
    _controls_for = b;
    _controls_sig = sig;
    for child in _controls_box.get_children():
        _controls_box.remove_child(child);
        child.queue_free();
    var title:Label = Label.new();
    title.text = "Settings:";
    _controls_box.add_child(title);
    for c in b.def["controls"]:
        if c.has("requires_upgrade") and not b.has_upgrade(c["requires_upgrade"]):
            continue;
        _controls_box.add_child(_make_control(b, c));

# Upgrade buttons for a finished building: one per upgrade in its def. Blocked ones are disabled and say why;
# while one is being built the only button is Cancel.
func _refresh_upgrades(obj:Variant) -> void:
    var b:Building = obj as Building if obj is Building else null;
    var show:bool = b != null and b.is_complete() and b.def.has("upgrades");
    _upgrade_box.visible = show;
    if not show:
        _upgrade_sig = "";
        return;
    var sig:String = "%d|%s|%s" % [b.get_instance_id(), b.upgrading, b.upgrades_done.keys()];
    if sig == _upgrade_sig:
        return;
    _upgrade_sig = sig;
    for child in _upgrade_box.get_children():
        _upgrade_box.remove_child(child);
        child.queue_free();
    var title:Label = Label.new();
    title.text = "Upgrades:";
    _upgrade_box.add_child(title);
    var ups:Dictionary = b.def["upgrades"];
    for id in ups:
        var up:Dictionary = ups[id];
        var btn:Button = Button.new();
        btn.focus_mode = Control.FOCUS_NONE;
        btn.tooltip_text = up.get("desc", "");
        var why:String = b.upgrade_block_reason(id);
        if b.upgrading == id:
            btn.text = "Cancel upgrade: %s" % up["name"];
            btn.pressed.connect(b.cancel_upgrade);
        elif b.has_upgrade(id):
            btn.text = "%s (built)" % up["name"];
            btn.disabled = true;
        elif why != "":
            btn.text = "%s (%s)" % [up["name"], why.to_lower()];
            btn.disabled = true;
        else:
            btn.text = "Upgrade: %s (%s)" % [up["name"], Defs.cost_string(up["cost"])];
            btn.pressed.connect(b.start_upgrade.bind(id));
        _upgrade_box.add_child(btn);

func _make_control(b:Building, c:Dictionary) -> Control:
    var id:String = c["id"];
    match c["type"]:
        "toggle":
            var check:CheckBox = CheckBox.new();
            check.text = c["label"];
            check.focus_mode = Control.FOCUS_NONE;
            check.button_pressed = b.settings[id];
            check.toggled.connect(func(on:bool) -> void:
                b.settings[id] = on);
            return check;
        "choice":
            var btn:Button = Button.new();
            btn.focus_mode = Control.FOCUS_NONE;
            var opts:Array = c["options"];
            var label_for:Callable = func() -> String:
                return "%s: %s" % [c["label"], opts[b.settings[id]]];
            btn.text = label_for.call();
            btn.pressed.connect(func() -> void:
                b.settings[id] = (b.settings[id] + 1) % opts.size();
                btn.text = label_for.call());
            return btn;
        "cap":
            var row:HBoxContainer = HBoxContainer.new();
            var l:Label = Label.new();
            l.text = c["label"];
            l.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
            row.add_child(l);
            var value:Label = Label.new();
            value.custom_minimum_size.x = 64;
            value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;
            var show_value:Callable = func() -> void:
                value.text = c.get("zero_label", "No cap") if b.settings[id] <= 0 else str(b.settings[id]);
            show_value.call();
            var step:int = c.get("step", 10);
            var minus:Button = Button.new();
            minus.text = "-";
            minus.focus_mode = Control.FOCUS_NONE;
            minus.pressed.connect(func() -> void:
                b.settings[id] = maxi(0, b.settings[id] - step);
                show_value.call());
            var plus:Button = Button.new();
            plus.text = "+";
            plus.focus_mode = Control.FOCUS_NONE;
            plus.pressed.connect(func() -> void:
                b.settings[id] = b.settings[id] + step;
                show_value.call());
            row.add_child(minus);
            row.add_child(value);
            row.add_child(plus);
            return row;
    return Control.new();

# Item filter checkboxes for storage buildings.
func _refresh_filters(obj:Variant) -> void:
    var show:bool = obj is Building and (obj as Building).is_storage();
    _filter_box.visible = show;
    if not show:
        return;
    var b:Building = obj;
    for item in _filter_checks:
        var check:CheckBox = _filter_checks[item];
        var can:bool = Defs.is_food(item) or not b.def.get("food_only", false);
        if b.def.has("accepts_items"):
            can = (b.def["accepts_items"] as Array).has(item);
        check.visible = can;
        check.set_pressed_no_signal(not b.forbidden.has(item));

func _on_filter_toggled(on:bool, item:StringName) -> void:
    var obj:Variant = World.instance.tools.selected;
    if obj is Building and World.alive(obj):
        (obj as Building).set_forbidden(item, not on);

# --------------------------------
# Callbacks

func _on_mode_changed(mode:int) -> void:
    var key:String = World.instance.tools.build_id if mode == PlayerTools.Mode.BUILD else str(mode);
    for k in _tool_btns:
        (_tool_btns[k] as Button).set_pressed_no_signal(k == key);

func _on_selection_changed(_obj:Variant) -> void:
    _refresh_info();

func _on_speed_changed(index:int) -> void:
    for i in _speed_btns.size():
        _speed_btns[i].set_pressed_no_signal(i == index);

func _town_hall_exists(w:World) -> bool:
    for b in w.buildings:
        if b.def_id == &"town_hall":
            return true;
    return false;

func _on_info_button() -> void:
    var obj:Variant = World.instance.tools.selected;
    if obj is Field:
        (obj as Field).cycle_crop();
        _refresh_info();

# --------------------------------
# Construction

func _build_top_bar(root:Control) -> void:
    var panel:PanelContainer = _panel(root);
    panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE);
    var row:HBoxContainer = HBoxContainer.new();
    row.add_theme_constant_override("separation", 12);
    panel.add_child(row);
    _date = Label.new();
    _date.custom_minimum_size.x = 175;
    row.add_child(_date);
    _weather = Label.new();
    _weather.custom_minimum_size.x = 90;
    row.add_child(_weather);
    _stock = Label.new();
    _stock.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
    _stock.clip_text = true;               # a long stock line shrinks instead of pushing the speed buttons off-screen
    _stock.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS;
    _stock.mouse_filter = Control.MOUSE_FILTER_PASS;
    row.add_child(_stock);
    var labels:Array[String] = ["||", "1x", "2x", "5x"];
    for i in labels.size():
        var b:Button = Button.new();
        b.text = labels[i];
        b.toggle_mode = true;
        b.focus_mode = Control.FOCUS_NONE;
        b.custom_minimum_size.x = 36;
        b.pressed.connect(GameClock.set_speed.bind(i));
        row.add_child(b);
        _speed_btns.append(b);

func _save_button(text:String, tip:String, action:Callable) -> Button:
    var b:Button = Button.new();
    b.text = text;
    b.tooltip_text = tip;
    b.focus_mode = Control.FOCUS_NONE;
    b.pressed.connect(action);
    return b;

func _build_toolbar(root:Control) -> void:
    var panel:PanelContainer = _panel(root);
    _toolbar = panel;
    panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE);
    panel.grow_vertical = Control.GROW_DIRECTION_BEGIN;
    var col:VBoxContainer = VBoxContainer.new();
    panel.add_child(col);
    _hint = Label.new();
    _hint.add_theme_color_override("font_color", Color(1.0, 0.92, 0.7));
    col.add_child(_hint);
    var row:HFlowContainer = HFlowContainer.new();     # wraps to a second line when the window is narrow
    col.add_child(row);
    var tools:PlayerTools = World.instance.tools;
    var group:ButtonGroup = ButtonGroup.new();
    group.allow_unpress = false;
    var modes:Array = [
        [PlayerTools.Mode.SELECT, "Select"], [PlayerTools.Mode.HARVEST, "Harvest"],
        [PlayerTools.Mode.ROAD, "Road"], [PlayerTools.Mode.DEMOLISH, "Demolish"],
        [PlayerTools.Mode.RAISE, "Raise"], [PlayerTools.Mode.LOWER, "Lower"], [PlayerTools.Mode.FLATTEN, "Flatten"],
    ];
    for m in modes:
        var b:Button = _tool_button(row, group, m[1], PlayerTools.MODE_HINTS[m[0]]);
        b.pressed.connect(tools.set_mode.bind(m[0], &""));
        _tool_btns[str(m[0])] = b;
    row.add_child(VSeparator.new());
    for id in Defs.BUILD_MENU:
        var def:Dictionary = Defs.BUILDINGS[id];
        var b:Button = _tool_button(row, group, def["name"], "%s\nCost: %s" % [def["desc"], Defs.cost_string(def["cost"])]);
        b.pressed.connect(tools.set_mode.bind(PlayerTools.Mode.BUILD, id));
        _tool_btns[String(id)] = b;
    (_tool_btns[str(PlayerTools.Mode.SELECT)] as Button).set_pressed_no_signal(true);

func _build_jobs_panel(root:Control) -> void:
    var panel:PanelContainer = _panel(root);
    panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);
    panel.offset_left = 8;
    panel.offset_top = 48;
    var col:VBoxContainer = VBoxContainer.new();
    panel.add_child(col);
    var title:Label = Label.new();
    title.text = "Professions";
    col.add_child(title);
    var jobs:JobManager = World.instance.jobs;
    for prof in JobManager.PROFESSION_NAMES.size():
        var row:HBoxContainer = HBoxContainer.new();
        col.add_child(row);
        var l:Label = Label.new();
        l.custom_minimum_size.x = 150;
        row.add_child(l);
        _jobs_rows.append(l);
        if prof == JobManager.Profession.LABORER:
            l.tooltip_text = "Unassigned citizens. They clear marked trees and rocks, haul and help build.";
            l.mouse_filter = Control.MOUSE_FILTER_PASS;
            continue;
        for d in [-1, 1]:
            var b:Button = Button.new();
            b.text = "-" if d < 0 else "+";
            b.focus_mode = Control.FOCUS_NONE;
            b.custom_minimum_size.x = 28;
            b.pressed.connect(jobs.change_profession.bind(prof, d));
            row.add_child(b);
    _build_policies(col);
    var save_row:HBoxContainer = HBoxContainer.new();
    col.add_child(save_row);
    var do_save:Callable = func() -> void: SaveGame.save(World.instance);
    var do_load:Callable = func() -> void: SaveGame.load_slot(World.instance);
    save_row.add_child(_save_button("Save", "Save the game to the quicksave slot (F5)", do_save));
    save_row.add_child(_save_button("Load", "Load the quicksave (F9)", do_load));

# A "Policies" button that opens the list of colony-wide rules as check boxes.
func _build_policies(col:VBoxContainer) -> void:
    var box:VBoxContainer = VBoxContainer.new();
    box.visible = false;
    var toggle:Button = Button.new();
    toggle.text = "Policies";
    toggle.tooltip_text = "Colony-wide rules";
    toggle.toggle_mode = true;
    toggle.focus_mode = Control.FOCUS_NONE;
    toggle.toggled.connect(func(on:bool) -> void: box.visible = on);
    _policies_btn = toggle;
    col.add_child(toggle);
    col.add_child(box);
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

func _build_info_panel(root:Control) -> void:
    _info = _panel(root);
    _info.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT);
    _info.grow_horizontal = Control.GROW_DIRECTION_BEGIN;
    _info.custom_minimum_size = Vector2(300, 0);
    _info.offset_right = -8;
    _info.offset_left = -308;
    _info.offset_top = 48;
    # long inspectors (a blacksmith with its settings and filters) scroll instead of running off screen
    _info_scroll = ScrollContainer.new();
    _info_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED;
    _info.add_child(_info_scroll);
    var col:VBoxContainer = VBoxContainer.new();
    col.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
    _info_scroll.add_child(col);
    _info_col = col;
    _info_title = Label.new();
    _info_title.add_theme_font_size_override("font_size", 20);
    col.add_child(_info_title);
    _info_body = Label.new();
    _info_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;
    _info_body.custom_minimum_size.x = 300;
    col.add_child(_info_body);
    _info_btn = Button.new();
    _info_btn.focus_mode = Control.FOCUS_NONE;
    _info_btn.pressed.connect(_on_info_button);
    col.add_child(_info_btn);
    _move_btn = Button.new();
    _move_btn.focus_mode = Control.FOCUS_NONE;
    _move_btn.visible = false;
    _move_btn.pressed.connect(func() -> void:
        var sel:Variant = World.instance.tools.selected;
        if sel is Building and World.alive(sel):
            World.instance.tools.start_relocate(sel));
    col.add_child(_move_btn);
    _upgrade_box = VBoxContainer.new();
    _upgrade_box.visible = false;
    col.add_child(_upgrade_box);
    _controls_box = VBoxContainer.new();
    _controls_box.visible = false;
    col.add_child(_controls_box);
    _filter_box = VBoxContainer.new();
    _filter_box.visible = false;
    col.add_child(_filter_box);
    var ftitle:Label = Label.new();
    ftitle.text = "Accepts:";
    _filter_box.add_child(ftitle);
    for item in Defs.ITEMS:
        var check:CheckBox = CheckBox.new();
        check.text = Defs.item_name(item);
        check.focus_mode = Control.FOCUS_NONE;
        check.toggled.connect(_on_filter_toggled.bind(item));
        _filter_box.add_child(check);
        _filter_checks[item] = check;

func _build_log(root:Control) -> void:
    _log = VBoxContainer.new();
    _log.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT);
    _log.grow_vertical = Control.GROW_DIRECTION_BEGIN;
    _log.offset_left = 10;
    _log.offset_top = -96;
    _log.offset_bottom = -96;
    _log.mouse_filter = Control.MOUSE_FILTER_IGNORE;
    root.add_child(_log);

func _panel(root:Control) -> PanelContainer:
    var p:PanelContainer = PanelContainer.new();
    p.mouse_filter = Control.MOUSE_FILTER_STOP;
    var style:StyleBoxFlat = StyleBoxFlat.new();
    style.bg_color = Color(0.08, 0.07, 0.06, 0.78);
    style.set_corner_radius_all(6);
    style.set_content_margin_all(8);
    p.add_theme_stylebox_override("panel", style);
    root.add_child(p);
    return p;

func _tool_button(row:Container, group:ButtonGroup, text:String, tip:String) -> Button:
    var b:Button = Button.new();
    b.text = text;
    b.tooltip_text = tip;
    b.toggle_mode = true;
    b.button_group = group;
    b.focus_mode = Control.FOCUS_NONE;
    row.add_child(b);
    return b;
