# ----------------------------------------------------------------
# HUD
#     Code-built prototype UI: top bar (date, weather, stock, speed),
#     bottom toolbar, profession counters, event log and the inspector.
# ----------------------------------------------------------------
class_name HUD extends CanvasLayer;

const SHOWN_ITEMS   :Array[StringName] = [&"wood", &"firewood", &"coal", &"stone", &"iron"];
const LOW_SOIL      :float = 0.4;           # a field under this warns on crops that drain it
const GOOD_SOIL     :float = 0.7;           # under this a soil-restoring crop is pointed out
const LOG_WIDTH     :float = 440.0;
const LOG_HEIGHT    :float = 110.0;
const LOG_LINES     :int = 80;         # messages the log panel keeps
const REFRESH_RATE  :float = 0.25;

var _date       :Label;
var _weather    :Label;
var _stock      :Label;
var _speed_btns :Array[Button] = [];
var _tool_btns  :Dictionary = {};       # key -> Button
var _cat_btns   :Array[Button] = [];     # build categories (Housing, Storage, ...)
var _build_row  :HFlowContainer;         # the buildings of the open category
var _open_cat   :int = -1;               # index into Defs.BUILD_CATEGORIES, or -1 when none is open
var _jobs_rows  :Array[Label] = [];
var _jobs_flags :Array[Label] = [];     # a red ! on professions whose buildings have empty positions
var _log_panel  :PanelContainer;
var _log_scroll :ScrollContainer;
var _log        :VBoxContainer;      # one label per message inside the log panel
var _hint       :Label;
var _toolbar    :PanelContainer;
var _info       :PanelContainer;
var _info_title :Label;
var _info_body  :Label;
var _help_btn   :Button;               # "?" beside the title: shows or hides the explanations (help_text)
var _help_label :Label;
var _help_open  :bool = false;
var _info_btn   :Button;
var _move_btn   :Button;
var _jobs_panel :PanelContainer;
var _jobs_toggle:Button;
var _soil_toggle:Button;               # colours the ground by soil fertility and numbers the selected field's plots
var _citizens_toggle:Button;
var _log_toggle :Button;
var _citizens   :CitizensPanel;
var _extras     :InspectorExtras;    # mark-for-harvest button and the worker list
var _site_box   :VBoxContainer;      # cancel and build priority for a site
var _cancel_btn :Button;
var _priority_btns:Array[Button] = [];
var _size_label :Label;              # follows the cursor while sizing a field, graveyard or stockpile
var _crop_list  :VBoxContainer;      # the crop choices, shown inline under the inspector's button
var _ledger_btn :Button;
var _ledger_panel:LedgerPanel;
var _policies_btn:Button;
var _menu       :Control;            # the Esc menu: a dimmed full-screen layer with a centred panel
var _menu_resume_speed:int = 1;

var _filter_box :VBoxContainer;
var _filter_head:Button;              # "Accepts: ..." summary; opens and closes the item toggles
var _filter_flow:HFlowContainer;
var _controls_box:VBoxContainer;
var _info_scroll:ScrollContainer;
var _info_col:VBoxContainer;
var _upgrade_box:VBoxContainer;
var _upgrade_sig:String = "";             # what the upgrade buttons were last built for
var _controls_sig:String = "";
var _controls_for:Variant = null;       # the building the control widgets were built for
var _filter_checks:Dictionary = {};     # item -> toggle Button
var _refresh    :float = 0.0;

const FONT_SIZE:int = 13;         # the whole HUD's text size (Godot's default is 16)
const TITLE_FONT_SIZE:int = 17;
const TITLE_SCENE:String = "res://scenes/title.tscn";
const LOG_FONT_SIZE:int = 11;     # the event log is secondary text

func _ready() -> void:
    var root:Control = Control.new();
    root.set_anchors_preset(Control.PRESET_FULL_RECT);
    root.mouse_filter = Control.MOUSE_FILTER_IGNORE;
    var theme:Theme = Theme.new();
    theme.default_font_size = FONT_SIZE;
    root.theme = theme;
    add_child(root);
    _build_top_bar(root);
    _build_toolbar(root);
    _build_jobs_panel(root);
    _build_policies_panel(root);
    _build_info_panel(root);
    _build_log(root);
    _build_menu(root);
    _size_label = Label.new();
    _size_label.visible = false;
    _size_label.mouse_filter = Control.MOUSE_FILTER_IGNORE;
    _size_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7));
    _size_label.add_theme_color_override("font_outline_color", Color.BLACK);
    _size_label.add_theme_constant_override("outline_size", 5);
    root.add_child(_size_label);
    _ledger_panel = LedgerPanel.new();
    root.add_child(_ledger_panel);
    _ledger_panel.setup(World.instance.ledger);
    _citizens = CitizensPanel.new();
    root.add_child(_citizens);
    _citizens.setup();
    _bind_toggle(_jobs_toggle, _jobs_panel, true);
    _bind_toggle(_log_toggle, _log_panel, true);
    _bind_toggle(_citizens_toggle, _citizens, false);

    var tools:PlayerTools = World.instance.tools;
    tools.mode_changed.connect(_on_mode_changed);
    tools.selection_changed.connect(_on_selection_changed);
    GameClock.speed_changed.connect(_on_speed_changed);
    _on_speed_changed(GameClock.speed_index);
    _on_selection_changed(null);
    _refresh_all();

func _process(delta:float) -> void:
    # until the player moves it, the log panel sits at the lower left, just above the toolbar (which grows a line when narrow)
    if not PanelMover.has_moved(_log_panel):
        _log_panel.offset_bottom = -(_toolbar.size.y + 8.0);
        _log_panel.offset_top = _log_panel.offset_bottom - 1.0;       # its contents decide the height (grows upward)
    var size_text:String = World.instance.tools.size_text();
    _size_label.visible = size_text != "";
    if size_text != "":
        _size_label.text = size_text;
        _size_label.position = get_viewport().get_mouse_position() + Vector2(18, 20);
    _refresh -= delta;
    if _refresh <= 0.0:
        _refresh = REFRESH_RATE;
        _refresh_all();

func notify(msg:String) -> void:
    var l:Label = Label.new();
    l.text = "[%s %s] %s" % [GameClock.date_string(), GameClock.time_string(), msg];
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;
    l.custom_minimum_size.x = LOG_WIDTH - 24.0;
    l.add_theme_font_size_override("font_size", LOG_FONT_SIZE);
    _log.add_child(l);
    while _log.get_child_count() > LOG_LINES:
        _log.get_child(0).free();
    _scroll_log_to_end.call_deferred();

func _scroll_log_to_end() -> void:
    _log_scroll.scroll_vertical = int(_log_scroll.get_v_scroll_bar().max_value);

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
    _apply_category();
    parts.append("Pop %d" % w.pawns.size());
    var idle:int = w.pawns.filter(func(p:Pawn) -> bool: return p.is_idle()).size();
    if idle > 0:
        parts.append("Idle %d" % idle);
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
        var slots:int = w.jobs.total_slots(prof) if prof != JobManager.Profession.LABORER else 0;
        var shown:String = "%d/%d" % [have, slots] if slots > 0 else str(have);       # workers over positions, where there are buildings
        if prof == JobManager.Profession.LABORER:
            shown = str(_working_laborers(w));
        _jobs_rows[prof].text = "%s: %s%s" % [JobManager.PROFESSION_NAMES[prof], shown, short];
        var open:int = w.jobs.open_slots(prof) if prof != JobManager.Profession.LABORER else 0;
        open = open if have == 0 else 0;       # only a profession with nobody at all is flagged
        _jobs_flags[prof].visible = open > 0;
        _jobs_flags[prof].tooltip_text = "Its buildings have %d open position%s and nobody is assigned. Raise the number with +." % [open, "" if open == 1 else "s"];
        _jobs_rows[prof].add_theme_color_override("font_color", Color(1.0, 0.7, 0.45) if open > 0 else Color.WHITE);
    var tools:PlayerTools = w.tools;
    _hint.text = tools.hint + ("   " + tools.error if tools.error != "" else "");
    _refresh_info();

# Laborers for the list: children count only while they are doing labor (a student is not one), babies never.
func _working_laborers(w:World) -> int:
    var n:int = 0;
    for p in w.pawns:
        if p.profession == JobManager.Profession.LABORER and (p.is_adult() or (not p.is_baby() and p.is_laboring())):
            n += 1;
    return n;

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
    var help:String = obj.help_text() if obj.has_method("help_text") else "";
    _help_btn.visible = help != "";
    _help_btn.set_pressed_no_signal(_help_open);
    _help_label.text = help;
    _help_label.visible = _help_open and help != "";
    _info_btn.visible = obj is Field;
    for b in World.instance.buildings:
        if b is Field:
            (b as Field).show_soil_numbers(_soil_toggle.button_pressed and is_same(b, obj));
    _refresh_relocate(obj);
    _refresh_site(obj);
    _extras.refresh(obj);
    _refresh_ledger_button(obj);
    _refresh_filters(obj);
    _refresh_controls(obj);
    _refresh_upgrades(obj);
    if obj is Field:
        _info_btn.text = "Change crop (%s)" % (obj as Field).crop()["name"];
    const TOP_BAR:float = 48.0;
    const PANEL_PADDING:float = 40.0;      # panel margins, title and the gap above the toolbar
    # the toolbar grows a line when the window is narrow, so measure it
    var top:float = _info.global_position.y if PanelMover.has_moved(_info) else TOP_BAR;       # a moved inspector may start lower
    var room:float = get_viewport().get_visible_rect().size.y - top - _toolbar.size.y - PANEL_PADDING;
    _info_scroll.custom_minimum_size.y = minf(_info_col.get_combined_minimum_size().y, room);

# Cancel and build priority for a building going up (or being upgraded).
func _refresh_site(obj:Variant) -> void:
    var b:Building = obj as Building if obj is Building else null;
    var show:bool = b != null and b.is_site();
    _site_box.visible = show;
    if not show:
        return;
    _cancel_btn.visible = b.state == Building.State.CONSTRUCTION;
    _cancel_btn.tooltip_text = "Stop building and take back every material delivered so far";
    for i in _priority_btns.size():
        _priority_btns[i].set_pressed_no_signal(b.priority == i);

func _on_priority_pressed(level:int) -> void:
    var sel:Variant = World.instance.tools.selected;
    if sel is Building and World.alive(sel) and (sel as Building).is_site():
        (sel as Building).set_priority(level);
    _refresh_info();

func _on_cancel_build() -> void:
    var sel:Variant = World.instance.tools.selected;
    if sel is Building and World.alive(sel) and (sel as Building).state == Building.State.CONSTRUCTION:
        World.instance.remove_building(sel, true);

# The Town Hall's Ledger button: enabled once it has the Governance upgrade (the record is kept regardless).
func _refresh_ledger_button(obj:Variant) -> void:
    var b:Building = obj as Building if obj is Building else null;
    _ledger_btn.visible = b != null and b.def_id == &"town_hall" and b.is_complete();
    var governed:bool = World.instance.has_governance();
    _ledger_btn.disabled = not governed;
    _ledger_btn.tooltip_text = "Graphs and the history of the colony" if governed else "Needs the Town Hall's Governance upgrade";
    if not governed:
        _ledger_panel.visible = false;

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
        var check:Button = _filter_checks[item];
        var can:bool = Defs.is_food(item) or not b.def.get("food_only", false);
        if b.def.has("accepts_items"):
            can = (b.def["accepts_items"] as Array).has(item);
        check.visible = can;
        check.set_pressed_no_signal(not b.forbidden.has(item));
    _update_filter_head(b);

# One line: everything is accepted, or what is switched off.
func _update_filter_head(b:Building) -> void:
    var off:Array[String] = [];
    var total:int = 0;
    for item in _filter_checks:
        if (_filter_checks[item] as Button).visible:
            total += 1;
            if b.forbidden.has(item):
                off.append(Defs.item_name(item));
    var summary:String = "everything" if off.is_empty() else ("nothing" if off.size() == total else "all but " + (", ".join(off) if off.size() <= 2 else "%d items" % off.size()));
    _filter_head.text = "Accepts: %s %s" % [summary, "-" if _filter_flow.visible else "+"];

func _on_filter_toggled(on:bool, item:StringName) -> void:
    var obj:Variant = World.instance.tools.selected;
    if obj is Building and World.alive(obj):
        (obj as Building).set_forbidden(item, not on);
        _update_filter_head(obj);

# --------------------------------
# Callbacks

func _on_mode_changed(mode:int) -> void:
    var key:String = World.instance.tools.build_id if mode == PlayerTools.Mode.BUILD else str(mode);
    for k in _tool_btns:
        (_tool_btns[k] as Button).set_pressed_no_signal(k == key);
    if mode == PlayerTools.Mode.BUILD:       # picking a building any other way opens its category
        for ci in Defs.BUILD_CATEGORIES.size():
            if (Defs.BUILD_CATEGORIES[ci][1] as Array).has(StringName(key)):
                _open_cat = ci;
        _apply_category();

func _on_selection_changed(_obj:Variant) -> void:
    _crop_list.visible = false;
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
        if _crop_list.visible:
            _crop_list.visible = false;
            return;
        for child in _crop_list.get_children():
            child.queue_free();
        for id in Defs.CROPS:
            var c:Dictionary = Defs.CROPS[id];
            var btn:Button = Button.new();
            var known:bool = World.instance.seeds.has(id);
            var soil:float = (obj as Field).mean_fertility();
            btn.text = "%s: %d days, sows %s" % [c["name"], roundi(c["grow_days"]), Defs.sow_text(id)] if known else "%s: no seeds yet" % c["name"];
            btn.tooltip_text = c["desc"] if known else "Citizens picking wild food may find its seeds while picking wild food.";
            if known:
                var drain:float = c["fertility"];
                btn.tooltip_text += "\nSoil: %s%d%% per harvest. Yield on this field's soil (%d%%): %d%%." % ["+" if drain > 0.0 else "", roundi(drain * 100.0), roundi(soil * 100.0), roundi(lerpf(0.4, 1.3, soil) / 1.3 * 100.0)];
                if drain < 0.0 and soil < LOW_SOIL:
                    btn.text = "! " + btn.text;
                    btn.add_theme_color_override("font_color", Color(1.0, 0.65, 0.3));
                    btn.tooltip_text += "\nLow soil: this crop will take the field lower. Grow something that restores it first (beans).";
                elif drain > 0.0 and soil < GOOD_SOIL:
                    btn.text += " (restores soil)";
                    btn.add_theme_color_override("font_color", Color(0.6, 0.9, 0.5));
            btn.disabled = not known;
            btn.alignment = HORIZONTAL_ALIGNMENT_LEFT;
            btn.focus_mode = Control.FOCUS_NONE;
            btn.pressed.connect(func() -> void:
                var sel:Variant = World.instance.tools.selected;
                if sel is Field and World.alive(sel):
                    (sel as Field).set_crop(id);
                _crop_list.visible = false;
                _refresh_info());
            _crop_list.add_child(btn);
        _crop_list.visible = true;

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
    # panel toggles: each button opens and closes its panel
    _jobs_toggle = _panel_toggle(row, "Jobs");
    _citizens_toggle = _panel_toggle(row, "Citizens");
    _log_toggle = _panel_toggle(row, "Log");
    _policies_btn = _panel_toggle(row, "Policies");
    _soil_toggle = _panel_toggle(row, "Soil");
    _soil_toggle.tooltip_text = "Show soil fertility on the ground (brown poor, green rich)";
    _soil_toggle.toggled.connect(func(on:bool) -> void:
        World.instance.terrain.set_soil_view(on);
        _refresh_info());
    var labels:Array[String] = ["||", "1x", "2x", "5x", "10x"];
    for i in labels.size():
        var b:Button = Button.new();
        b.text = labels[i];
        b.toggle_mode = true;
        b.focus_mode = Control.FOCUS_NONE;
        b.custom_minimum_size.x = 36;
        b.pressed.connect(GameClock.set_speed.bind(i));
        row.add_child(b);
        _speed_btns.append(b);

# A toggle button that shows and hides a panel (and stays in step if the panel is closed some other way).
func _bind_toggle(btn:Button, panel:Control, shown:bool) -> void:
    panel.visible = shown;
    btn.set_pressed_no_signal(shown);
    btn.toggled.connect(func(on:bool) -> void: panel.visible = on);

func _panel_toggle(row:Container, text:String) -> Button:
    var b:Button = Button.new();
    b.text = text;
    b.toggle_mode = true;
    b.focus_mode = Control.FOCUS_NONE;
    row.add_child(b);
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
        [PlayerTools.Mode.SELECT, "Select"], [PlayerTools.Mode.HARVEST, "Harvest"], [PlayerTools.Mode.FORAGE, "Forage"],
        [PlayerTools.Mode.ROAD, "Road"], [PlayerTools.Mode.DEMOLISH, "Demolish"], [PlayerTools.Mode.CANCEL, "Cancel"],
        [PlayerTools.Mode.RAISE, "Raise"], [PlayerTools.Mode.LOWER, "Lower"], [PlayerTools.Mode.FLATTEN, "Flatten"],
    ];
    for m in modes:
        var b:Button = _tool_button(row, group, m[1], PlayerTools.MODE_HINTS[m[0]]);
        b.pressed.connect(tools.set_mode.bind(m[0], &""));
        _tool_btns[str(m[0])] = b;
    row.add_child(VSeparator.new());
    # buildings are grouped: a button per category opens that category's buildings on a second line
    _build_row = HFlowContainer.new();
    col.add_child(_build_row);
    var cat_group:ButtonGroup = ButtonGroup.new();
    cat_group.allow_unpress = true;
    for ci in Defs.BUILD_CATEGORIES.size():
        var cb:Button = _tool_button(row, cat_group, Defs.BUILD_CATEGORIES[ci][0] + " >", "Show the %s buildings" % Defs.BUILD_CATEGORIES[ci][0].to_lower());
        cb.pressed.connect(_on_category_pressed.bind(ci));
        _cat_btns.append(cb);
        for id in Defs.BUILD_CATEGORIES[ci][1]:
            var def:Dictionary = Defs.BUILDINGS[id];
            var b:Button = _tool_button(_build_row, group, def["name"], "Cost: %s" % Defs.cost_string(def["cost"]));
            b.pressed.connect(tools.set_mode.bind(PlayerTools.Mode.BUILD, id));
            _tool_btns[String(id)] = b;
    (_tool_btns[str(PlayerTools.Mode.SELECT)] as Button).set_pressed_no_signal(true);
    _apply_category();

func _on_category_pressed(index:int) -> void:
    _open_cat = -1 if _open_cat == index else index;
    _apply_category();

# Shows the buildings of the open category (the Town Hall's button also hides while one stands) and the matching
# category button as pressed.
func _apply_category() -> void:
    _build_row.visible = _open_cat >= 0;
    for ci in _cat_btns.size():
        _cat_btns[ci].set_pressed_no_signal(ci == _open_cat);
        for id in Defs.BUILD_CATEGORIES[ci][1]:
            var shown:bool = ci == _open_cat;
            if id == &"town_hall":
                shown = shown and not _town_hall_exists(World.instance);
            (_tool_btns[String(id)] as Button).visible = shown;

func _build_jobs_panel(root:Control) -> void:
    var panel:PanelContainer = _panel(root, &"jobs");
    _jobs_panel = panel;
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
        _jobs_rows.append(l);
        var flag:Label = Label.new();
        flag.text = "!";
        flag.visible = false;
        flag.mouse_filter = Control.MOUSE_FILTER_STOP;
        flag.add_theme_color_override("font_color", Color(1.0, 0.45, 0.3));
        _jobs_flags.append(flag);
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

func menu_open() -> bool:
    return _menu.visible;

# Opening the menu pauses the game; closing it resumes at the speed it had.
func toggle_menu() -> void:
    if _menu.visible:
        _menu.visible = false;
        GameClock.set_speed(_menu_resume_speed);
    else:
        _menu_resume_speed = GameClock.speed_index;
        GameClock.set_speed(0);
        _menu.visible = true;

func _build_menu(root:Control) -> void:
    _menu = Control.new();
    _menu.set_anchors_preset(Control.PRESET_FULL_RECT);
    _menu.mouse_filter = Control.MOUSE_FILTER_STOP;       # nothing under the menu gets clicked
    _menu.visible = false;
    root.add_child(_menu);
    var dim:ColorRect = ColorRect.new();
    dim.color = Color(0.0, 0.0, 0.0, 0.45);
    dim.set_anchors_preset(Control.PRESET_FULL_RECT);
    dim.mouse_filter = Control.MOUSE_FILTER_IGNORE;
    _menu.add_child(dim);
    var center:CenterContainer = CenterContainer.new();
    center.set_anchors_preset(Control.PRESET_FULL_RECT);
    center.mouse_filter = Control.MOUSE_FILTER_IGNORE;
    _menu.add_child(center);
    var panel:PanelContainer = _panel(center);
    var col:VBoxContainer = VBoxContainer.new();
    col.custom_minimum_size.x = 220;
    col.add_theme_constant_override("separation", 6);
    panel.add_child(col);
    var title:Label = Label.new();
    title.text = "Paused";
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;
    title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE);
    col.add_child(title);
    var seed_label:Label = Label.new();
    seed_label.text = "Map seed: %d" % World.instance.world_seed;
    seed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;
    col.add_child(seed_label);
    var items:Array = [
        ["Resume", toggle_menu],
        ["Save (F5)", func() -> void: SaveGame.save(World.instance)],
        ["Load (F9)", func() -> void: toggle_menu(); SaveGame.load_slot(World.instance)],
        ["Quit to title", func() -> void: get_tree().change_scene_to_file(TITLE_SCENE)],
        ["Quit game", func() -> void: get_tree().quit()],
    ];
    for item in items:
        var b:Button = Button.new();
        b.text = item[0];
        b.focus_mode = Control.FOCUS_NONE;
        b.pressed.connect(item[1]);
        col.add_child(b);

# The colony-wide rules as check boxes in a panel of their own, opened by the top bar's Policies button.
func _build_policies_panel(root:Control) -> void:
    var panel:PanelContainer = _panel(root, &"policies");
    panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);
    panel.offset_left = 200;
    panel.offset_top = 48;
    panel.visible = false;
    var box:VBoxContainer = VBoxContainer.new();
    panel.add_child(box);
    var title:Label = Label.new();
    title.text = "Policies";
    box.add_child(title);
    _policies_btn.toggled.connect(func(on:bool) -> void: panel.visible = on);
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
    _info = _panel(root, &"info");
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
    var title_row:HBoxContainer = HBoxContainer.new();
    col.add_child(title_row);
    _info_title = Label.new();
    _info_title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE);
    _info_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
    title_row.add_child(_info_title);
    _help_btn = Button.new();
    _help_btn.text = "?";
    _help_btn.toggle_mode = true;
    _help_btn.focus_mode = Control.FOCUS_NONE;
    _help_btn.tooltip_text = "Show or hide what this does";
    _help_btn.toggled.connect(func(on:bool) -> void:
        _help_open = on;
        _help_label.visible = on and _help_label.text != "";
        PanelMover.refit_height(_info));
    title_row.add_child(_help_btn);
    _help_label = Label.new();
    _help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;
    _help_label.custom_minimum_size.x = 300;
    _help_label.add_theme_color_override("font_color", Color(0.78, 0.8, 0.72));
    _help_label.visible = false;
    col.add_child(_help_label);
    _info_body = Label.new();
    _info_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;
    _info_body.custom_minimum_size.x = 300;
    col.add_child(_info_body);
    _info_btn = Button.new();
    _info_btn.focus_mode = Control.FOCUS_NONE;
    _info_btn.pressed.connect(_on_info_button);
    col.add_child(_info_btn);
    _crop_list = VBoxContainer.new();
    _crop_list.visible = false;
    col.add_child(_crop_list);
    _move_btn = Button.new();
    _move_btn.focus_mode = Control.FOCUS_NONE;
    _move_btn.visible = false;
    _move_btn.pressed.connect(func() -> void:
        var sel:Variant = World.instance.tools.selected;
        if sel is Building and World.alive(sel):
            World.instance.tools.start_relocate(sel));
    col.add_child(_move_btn);
    _extras = InspectorExtras.new();
    col.add_child(_extras);
    _site_box = VBoxContainer.new();
    _site_box.visible = false;
    col.add_child(_site_box);
    _cancel_btn = Button.new();
    _cancel_btn.text = "Cancel construction";
    _cancel_btn.focus_mode = Control.FOCUS_NONE;
    _cancel_btn.pressed.connect(_on_cancel_build);
    _site_box.add_child(_cancel_btn);
    var prio_title:Label = Label.new();
    prio_title.text = "Build priority:";
    _site_box.add_child(prio_title);
    var prio_row:HBoxContainer = HBoxContainer.new();
    _site_box.add_child(prio_row);
    for i in Building.PRIORITY_NAMES.size():
        var pb:Button = Button.new();
        pb.text = Building.PRIORITY_NAMES[i];
        pb.toggle_mode = true;
        pb.focus_mode = Control.FOCUS_NONE;
        pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
        pb.tooltip_text = "No hauling or building here" if i == 0 else "Builders and haulers serve higher priorities first";
        pb.pressed.connect(_on_priority_pressed.bind(i));
        prio_row.add_child(pb);
        _priority_btns.append(pb);
    _ledger_btn = Button.new();
    _ledger_btn.text = "Ledger";
    _ledger_btn.focus_mode = Control.FOCUS_NONE;
    _ledger_btn.visible = false;
    _ledger_btn.pressed.connect(func() -> void: _ledger_panel.open());
    col.add_child(_ledger_btn);
    _upgrade_box = VBoxContainer.new();
    _upgrade_box.visible = false;
    col.add_child(_upgrade_box);
    _controls_box = VBoxContainer.new();
    _controls_box.visible = false;
    col.add_child(_controls_box);
    _filter_box = VBoxContainer.new();
    _filter_box.visible = false;
    col.add_child(_filter_box);
    _filter_head = Button.new();
    _filter_head.flat = true;
    _filter_head.alignment = HORIZONTAL_ALIGNMENT_LEFT;
    _filter_head.focus_mode = Control.FOCUS_NONE;
    _filter_head.tooltip_text = "Click to choose which goods this store takes";
    _filter_box.add_child(_filter_head);
    _filter_flow = HFlowContainer.new();
    _filter_flow.visible = false;
    _filter_flow.add_theme_constant_override("h_separation", 3);
    _filter_flow.add_theme_constant_override("v_separation", 3);
    _filter_box.add_child(_filter_flow);
    _filter_head.pressed.connect(func() -> void:
        _filter_flow.visible = not _filter_flow.visible;
        if World.instance.tools.selected is Building:
            _update_filter_head(World.instance.tools.selected);
        PanelMover.refit_height(_info));
    for item in Defs.ITEMS:
        var check:Button = Button.new();       # a lit button is an item the store accepts
        check.text = Defs.item_name(item);
        check.toggle_mode = true;
        check.focus_mode = Control.FOCUS_NONE;
        check.add_theme_font_size_override("font_size", 11);
        check.toggled.connect(_on_filter_toggled.bind(item));
        _filter_flow.add_child(check);
        _filter_checks[item] = check;

func _build_log(root:Control) -> void:
    _log_panel = _panel(root, &"log");
    _log_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT);
    _log_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN;
    _log_panel.offset_left = 8;
    _log_panel.offset_right = 8 + LOG_WIDTH;
    _log_panel.offset_top = -(96 + LOG_HEIGHT);
    _log_panel.offset_bottom = -96;
    _log_panel.custom_minimum_size.x = LOG_WIDTH;
    var col:VBoxContainer = VBoxContainer.new();
    _log_panel.add_child(col);
    var title:Button = Button.new();
    title.text = "Log  -";
    title.flat = true;
    title.alignment = HORIZONTAL_ALIGNMENT_LEFT;
    title.focus_mode = Control.FOCUS_NONE;
    title.tooltip_text = "Click to collapse or expand";
    col.add_child(title);
    _log_scroll = ScrollContainer.new();
    _log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED;
    _log_scroll.custom_minimum_size = Vector2(LOG_WIDTH, LOG_HEIGHT);
    col.add_child(_log_scroll);
    title.pressed.connect(func() -> void:
        _log_scroll.visible = not _log_scroll.visible;
        title.text = "Log  -" if _log_scroll.visible else "Log  +";
        PanelMover.refit_height(_log_panel);
        _scroll_log_to_end.call_deferred());
    _log = VBoxContainer.new();
    _log.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
    _log_scroll.add_child(_log);

# A HUD panel. With an id it can be dragged by the strip along its top edge (see PanelMover).
func _panel(root:Control, id:StringName = &"") -> PanelContainer:
    var p:PanelContainer = PanelContainer.new();
    p.mouse_filter = Control.MOUSE_FILTER_STOP;
    var style:StyleBoxFlat = StyleBoxFlat.new();
    style.bg_color = Color(0.08, 0.07, 0.06, 0.78);
    style.set_corner_radius_all(6);
    style.set_content_margin_all(8);
    p.add_theme_stylebox_override("panel", style);
    root.add_child(p);
    if id != &"":
        PanelMover.make_movable(p, id);
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
