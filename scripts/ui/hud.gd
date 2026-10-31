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
var _stock      :HBoxContainer;         # the stock figures in the top bar, each an icon and a number
var _stock_vals :Dictionary = {};       # entry id -> its number Label (the entry's box is the label's parent)
var _speed_btns :Array[Button] = [];
var _tool_btns  :Dictionary = {};       # key -> Button
var _cat_btns   :Array[Button] = [];     # build categories (Housing, Storage, ...)
var _build_row  :HFlowContainer;         # the buildings of the open category
var _toast      :Label;
var _toast_tween:Tween;
var _tool_row   :HFlowContainer;
var _harvest_opts:HBoxContainer;        # trees / stone / iron check boxes, shown while the Harvest tool is chosen
var _road_cat   :int = -1;               # the category the Road tool button lives in
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
var _copy_btn   :Button;               # start placing another building of the selected one's kind
var _dismiss_btn:Button;               # send the merchant on their way early
var _jobs_panel :PanelContainer;
var _jobs_toggle:Button;
var _water_toggle:Button;               # colours the ground by reach of water (where a Distillery or Potter's Workshop may go)
var _slope_toggle:Button;              # colours the ground by how steep it is for building
var _soil_toggle:Button;               # colours the ground by soil fertility and numbers the selected field's plots
var _citizens_toggle:Button;
var _log_toggle :Button;
var _citizens   :CitizensPanel;
var _extras     :InspectorExtras;    # mark-for-harvest button and the worker list
var _site_box   :VBoxContainer;      # cancel and build priority for a site
var _cancel_btn :Button;
var _priority_btns:Array[Button] = [];
var _merchant_label:Label;           # a note under the top bar while a merchant is on the way, here or leaving
var _site_panel :PanelContainer;     # the rating of the spot under the cursor while the Town Hall is being placed
var _site_text  :RichTextLabel;
var _site_for   :Vector2i = Vector2i(-9999, -9999);
var _size_label :Label;              # follows the cursor while sizing a field, graveyard or stockpile
var _crop_list  :VBoxContainer;      # the crop choices, shown inline under the inspector's button
var _ledger_btn :Button;
var _trade_btn  :Button;               # opens the barter window at a Trading Post with a merchant
var _trade_panel:TradePanel;
var _hold_btn   :Button;               # opens the Trading Post's own inventory
var _hold_panel :HoldPanel;
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
    if Tutorial.active:
        Tutorial.active = false;
        Tutorial.attach(self, root);
    elif World.instance.scenario != null:
        ScenarioPanel.attach(self, root);
    _merchant_label = Label.new();
    _merchant_label.visible = false;
    _merchant_label.mouse_filter = Control.MOUSE_FILTER_STOP;
    _merchant_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND;
    _merchant_label.tooltip_text = "Click to look at the merchant";
    _merchant_label.gui_input.connect(_on_merchant_label_input);
    _merchant_label.set_anchors_preset(Control.PRESET_CENTER_TOP);
    _merchant_label.grow_horizontal = Control.GROW_DIRECTION_BOTH;
    _merchant_label.offset_top = 52.0;
    _merchant_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.5));
    _merchant_label.add_theme_color_override("font_outline_color", Color.BLACK);
    _merchant_label.add_theme_constant_override("outline_size", 5);
    root.add_child(_merchant_label);
    _size_label = Label.new();
    _size_label.visible = false;
    _size_label.mouse_filter = Control.MOUSE_FILTER_IGNORE;
    _size_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7));
    _size_label.add_theme_color_override("font_outline_color", Color.BLACK);
    _size_label.add_theme_constant_override("outline_size", 5);
    root.add_child(_size_label);
    _site_panel = PanelContainer.new();
    _site_panel.visible = false;
    _site_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE;
    var site_style:StyleBoxFlat = StyleBoxFlat.new();
    site_style.bg_color = Color(0.06, 0.06, 0.05, 0.88);
    site_style.set_corner_radius_all(5);
    site_style.set_content_margin_all(8);
    _site_panel.add_theme_stylebox_override("panel", site_style);
    _site_text = RichTextLabel.new();
    _site_text.bbcode_enabled = true;
    _site_text.fit_content = true;
    _site_text.scroll_active = false;
    _site_text.custom_minimum_size = Vector2(290, 0);
    _site_text.mouse_filter = Control.MOUSE_FILTER_IGNORE;
    _site_panel.add_child(_site_text);
    root.add_child(_site_panel);
    _toast = Label.new();
    _toast.visible = false;
    _toast.mouse_filter = Control.MOUSE_FILTER_IGNORE;
    _toast.set_anchors_preset(Control.PRESET_CENTER_TOP);
    _toast.grow_horizontal = Control.GROW_DIRECTION_BOTH;
    _toast.offset_top = 90.0;
    _toast.z_index = 100;
    _toast.add_theme_font_size_override("font_size", 20);
    _toast.add_theme_color_override("font_color", Color(0.75, 1.0, 0.7));
    _toast.add_theme_color_override("font_outline_color", Color.BLACK);
    _toast.add_theme_constant_override("outline_size", 6);
    root.add_child(_toast);
    _ledger_panel = LedgerPanel.new();
    root.add_child(_ledger_panel);
    _ledger_panel.setup(World.instance.ledger);
    _trade_panel = TradePanel.new();
    root.add_child(_trade_panel);
    _trade_panel.setup();
    _hold_panel = HoldPanel.new();
    root.add_child(_hold_panel);
    _hold_panel.setup();
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
    _update_site_panel();
    _refresh -= delta;
    if _refresh <= 0.0:
        _refresh = REFRESH_RATE;
        _refresh_all();

# While the Town Hall is being placed: what the spot under the cursor is like (redone when the cursor moves to a new cell).
func _update_site_panel() -> void:
    var w:World = World.instance;
    _site_panel.visible = w.awaiting_start and w.tools.hover_valid();
    if not _site_panel.visible:
        return;
    var c:Vector2i = w.tools.hover_origin() + Vector2i(2, 2);
    if c != _site_for:
        _site_for = c;
        _site_text.text = SiteRating.bbcode(SiteRating.rate(w, c));
    var mouse:Vector2 = get_viewport().get_mouse_position();
    var room:Vector2 = get_viewport().get_visible_rect().size - _site_panel.size - Vector2(8, 8);
    _site_panel.position = Vector2(minf(mouse.x + 28.0, room.x), minf(mouse.y + 24.0, room.y));

# A short message in the middle of the screen that fades out (it also shows over the Esc menu).
func toast(msg:String) -> void:
    _toast.text = msg;
    _toast.visible = true;
    _toast.modulate = Color.WHITE;
    if _toast_tween != null:
        _toast_tween.kill();
    _toast_tween = create_tween();
    _toast_tween.tween_interval(1.2);
    _toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.8);
    _toast_tween.tween_callback(func() -> void: _toast.visible = false);

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
    for item in SHOWN_ITEMS:
        _set_stock(item, Stock.amount(item));
    _set_stock(&"food", Stock.food_total());
    var governed:bool = w.has_governance();
    _policies_btn.disabled = not governed;
    _policies_btn.tooltip_text = "Colony-wide rules" if governed else "Needs the Town Hall's Governance upgrade";
    if not governed and _policies_btn.button_pressed:
        _policies_btn.button_pressed = false;
    _apply_category();
    _tool_row.visible = not w.awaiting_start;          # before the Town Hall is down there is only one thing to do
    if w.awaiting_start:
        _build_row.visible = false;
    _set_stock(&"pop", w.pawns.size());
    var idle:int = w.pawns.filter(func(p:Pawn) -> bool: return p.is_idle()).size();
    _set_stock(&"idle", idle, idle > 0);
    var homeless:int = w.families.homeless_count();
    _set_stock(&"homeless", homeless, homeless > 0);
    var merchant_note:String = w.traders.top_text();
    _merchant_label.visible = merchant_note != "";
    _merchant_label.text = merchant_note;
    var food_tip:PackedStringArray = ["Storage: %d / %d" % [Stock.used(), Stock.capacity()]];
    for item in Defs.ITEMS:
        if Defs.ITEMS[item].get("food", false):
            food_tip.append("%s: %d" % [Defs.item_name(item), Stock.amount(item)]);
    (_stock_vals[&"food"] as Label).get_parent().tooltip_text = "\n".join(food_tip);
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
    _info_btn.visible = obj is Field or obj is Pasture;
    for b in World.instance.buildings:
        if b is Field:
            (b as Field).show_soil_numbers(_soil_toggle.button_pressed and is_same(b, obj));
    _refresh_relocate(obj);
    _refresh_site(obj);
    _extras.refresh(obj);
    _refresh_ledger_button(obj);
    _refresh_trade_button(obj);
    _refresh_filters(obj);
    _refresh_controls(obj);
    _refresh_upgrades(obj);
    if obj is Field:
        _info_btn.text = "Change crop (%s)" % (obj as Field).crop()["name"];
        _info_btn.disabled = false;
        _info_btn.tooltip_text = "";
    elif obj is Pasture:
        _info_btn.text = "Change animal (%s)" % (obj as Pasture).animal()["name"];
        _info_btn.disabled = not (obj as Pasture).can_change_kind();
        _info_btn.tooltip_text = "" if not _info_btn.disabled else "Only an empty pasture can change its animal.";
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
func _refresh_trade_button(obj:Variant) -> void:
    var post:TradingPost = obj as TradingPost if obj is TradingPost else null;
    var here:bool = post != null and post.is_complete() and World.instance.traders.present();
    _trade_btn.visible = post != null and post.is_complete();
    _trade_btn.disabled = not here;
    _trade_btn.text = "Trade with the merchant" if here else "No merchant here";
    _dismiss_btn.visible = here;
    _hold_btn.visible = post != null and post.is_complete();
    if post == null and _hold_panel.visible:
        _hold_panel.visible = false;
    if not here and _trade_panel.visible:
        _trade_panel.visible = false;

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
    _copy_btn.visible = b != null and b.is_complete() and Defs.BUILD_MENU.has(b.def_id) and not b.def.get("unique", false);
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
    _harvest_opts.visible = mode == PlayerTools.Mode.HARVEST;
    var key:String = World.instance.tools.build_id if mode == PlayerTools.Mode.BUILD else str(mode);
    for k in _tool_btns:
        (_tool_btns[k] as Button).set_pressed_no_signal(k == key);
    if mode == PlayerTools.Mode.BUILD:       # picking a building any other way opens its category
        for ci in Defs.BUILD_CATEGORIES.size():
            if (Defs.BUILD_CATEGORIES[ci][1] as Array).has(StringName(key)):
                _open_cat = ci;
        _apply_category();
    elif mode == PlayerTools.Mode.ROAD and _road_cat >= 0:
        _open_cat = _road_cat;
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
    if obj is Pasture:
        _animal_choices(obj as Pasture);
        return;
    if obj is Field:
        if _crop_list.visible:
            _crop_list.visible = false;
            return;
        for child in _crop_list.get_children():
            child.queue_free();
        for id in Defs.CROPS:
            var c:Dictionary = Defs.CROPS[id];
            if c.get("tree", false) != (obj as Field).is_orchard():
                continue;       # fields grow crops, orchards grow trees
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

# The animals a pasture can keep, listed inline like the crops of a field.
func _animal_choices(pen:Pasture) -> void:
    if _crop_list.visible:
        _crop_list.visible = false;
        return;
    for child in _crop_list.get_children():
        child.queue_free();
    for id in Defs.ANIMALS:
        var a:Dictionary = Defs.ANIMALS[id];
        var btn:Button = Button.new();
        btn.text = "%s: gives %s" % [a["name"], Defs.item_name(a["product"]).to_lower()];
        btn.tooltip_text = "Needs %.1f cells each. Also gives manure, and meat%s when slaughtered." % [a["cells"], " and leather" if a.get("leather", 0) > 0 else ""];
        btn.alignment = HORIZONTAL_ALIGNMENT_LEFT;
        btn.focus_mode = Control.FOCUS_NONE;
        btn.pressed.connect(func() -> void:
            var sel:Variant = World.instance.tools.selected;
            if sel is Pasture and World.alive(sel):
                (sel as Pasture).set_kind(id);
            _crop_list.visible = false;
            _refresh_info());
        _crop_list.add_child(btn);
    _crop_list.visible = true;

# --------------------------------
# Construction



func _set_stock(id:StringName, value:int, shown:bool = true) -> void:
    var num:Label = _stock_vals[id];
    num.text = str(value);
    num.get_parent().visible = shown;

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


func _on_merchant_label_input(ev:InputEvent) -> void:
    if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
        var m:Merchant = World.instance.traders.merchant;
        if is_instance_valid(m):          # (a Merchant has no `removed` flag, so World.alive does not apply)
            World.instance.camera_rig.focus_on(Vector3(m.position.x, 0.0, m.position.z));

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
    if _tool_btns.has(str(PlayerTools.Mode.ROAD)):
        (_tool_btns[str(PlayerTools.Mode.ROAD)] as Button).visible = _open_cat == _road_cat;


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





# A HUD panel. With an id it can be dragged by the strip along its top edge (see PanelMover).
func world_camera() -> RTSCamera:
    return World.instance.camera_rig;

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

# --------------------------------
# Delegates: the panels are built by HudBuild

func _build_top_bar(root:Control) -> void:
    HudBuild._build_top_bar(self, root);

func _build_toolbar(root:Control) -> void:
    HudBuild._build_toolbar(self, root);

func _build_jobs_panel(root:Control) -> void:
    HudBuild._build_jobs_panel(self, root);

func _build_menu(root:Control) -> void:
    HudBuild._build_menu(self, root);

func _build_policies_panel(root:Control) -> void:
    HudBuild._build_policies_panel(self, root);

func _build_info_panel(root:Control) -> void:
    HudBuild._build_info_panel(self, root);

func _build_log(root:Control) -> void:
    HudBuild._build_log(self, root);
