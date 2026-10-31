# ----------------------------------------------------------------
# SavePanel
#     A modal list of the saved games. In save mode it also has a name
#     box, so a game can go into a new slot or over an old one; in load
#     mode it loads the chosen slot. Used by the Esc menu and the title.
# ----------------------------------------------------------------
class_name SavePanel extends Control;

signal save_chosen(slot:String);
signal load_chosen(slot:String);
signal closed;

var saving:bool = false;
var _list   :VBoxContainer;
var _name   :LineEdit;
var _status :Label;
var _selected:String = "";
var _confirming:String = "";        # the name a first Save press asked to overwrite (a second press does it)
var _action :Button;
var _delete :Button;

# --------------------------------
func _init(save_mode:bool = false) -> void:
    saving = save_mode;
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
    style.bg_color = Color(0.08, 0.07, 0.06, 1.0);
    style.set_corner_radius_all(6);
    style.set_content_margin_all(12);
    panel.add_theme_stylebox_override("panel", style);
    center.add_child(panel);
    var col:VBoxContainer = VBoxContainer.new();
    col.custom_minimum_size = Vector2(460, 0);
    col.add_theme_constant_override("separation", 6);
    panel.add_child(col);
    var title:Label = Label.new();
    title.text = "Save game" if saving else "Load game";
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;
    col.add_child(title);
    var scroll:ScrollContainer = ScrollContainer.new();
    scroll.custom_minimum_size = Vector2(0, 260);
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED;
    col.add_child(scroll);
    _list = VBoxContainer.new();
    _list.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
    scroll.add_child(_list);
    if saving:
        _name = LineEdit.new();
        _name.placeholder_text = "Name of the save";
        _name.text = "Day %d" % (GameClock.day_index() + 1);
        _name.max_length = 32;
        _name.text_changed.connect(func(_t:String) -> void: _cancel_confirm(); _refresh_buttons());
        _name.text_submitted.connect(func(_t:String) -> void: _on_action());
        col.add_child(_name);
    _status = Label.new();
    _status.add_theme_color_override("font_color", Color(1.0, 0.6, 0.5));
    col.add_child(_status);
    var row:HBoxContainer = HBoxContainer.new();
    row.alignment = BoxContainer.ALIGNMENT_CENTER;
    row.add_theme_constant_override("separation", 6);
    col.add_child(row);
    _action = _button(row, "Save" if saving else "Load", _on_action);
    _delete = _button(row, "Delete", _on_delete);
    _button(row, "Back", close);
    _rebuild();

func _button(row:Container, text:String, call:Callable) -> Button:
    var b:Button = Button.new();
    b.text = text;
    b.focus_mode = Control.FOCUS_NONE;
    b.pressed.connect(call);
    row.add_child(b);
    return b;

# --------------------------------
func _rebuild() -> void:
    for c in _list.get_children():
        c.queue_free();
    var rows:Array = SaveGame.list_slots();
    if rows.is_empty():
        var none:Label = Label.new();
        none.text = "No saved games yet.";
        _list.add_child(none);
    for r in rows:
        var b:Button = Button.new();
        b.toggle_mode = true;
        b.focus_mode = Control.FOCUS_NONE;
        b.alignment = HORIZONTAL_ALIGNMENT_LEFT;
        b.button_pressed = r["slot"] == _selected;
        var when:String = Time.get_datetime_string_from_unix_time(int(r["saved_at"]), true);
        if r["ok"]:
            b.text = "%s    %s, %d citizens    (%s)" % [r["slot"], r["date"], r["pawns"], when] if r["date"] != "" else "%s    (%s)" % [r["slot"], when];
        else:
            b.text = "%s    can't be loaded (an older version)" % r["slot"];
        b.set_meta("ok", r["ok"]);
        var slot:String = r["slot"];
        b.pressed.connect(func() -> void: _select(slot));
        _list.add_child(b);
    _refresh_buttons();

func _select(slot:String) -> void:
    _selected = slot;
    _cancel_confirm();
    if _name != null:
        _name.text = slot;
    for b in _list.get_children():
        if b is Button:
            (b as Button).button_pressed = (b as Button).text.begins_with(slot + "    ");
    _refresh_buttons();

func _slot_ok(slot:String) -> bool:
    for r in SaveGame.list_slots():
        if r["slot"] == slot:
            return r["ok"];
    return false;

func _refresh_buttons() -> void:
    _delete.disabled = _selected == "";
    if saving:
        _action.disabled = SaveGame.clean_name(_name.text) == "";
    else:
        _action.disabled = _selected == "" or not _slot_ok(_selected);

func _on_action() -> void:
    if saving:
        var slot:String = SaveGame.clean_name(_name.text);
        if slot == "":
            return;
        if SaveGame.exists(slot) and _confirming != slot:       # saving over a save: ask first
            _confirming = slot;
            _action.text = "Overwrite";
            _status.text = "A save called '%s' already exists. Press Overwrite to replace it, or pick another name." % slot;
            return;
        _cancel_confirm();
        save_chosen.emit(slot);
    elif _selected != "" and _slot_ok(_selected):
        load_chosen.emit(_selected);

func _cancel_confirm() -> void:
    _confirming = "";
    if saving and _action != null:
        _action.text = "Save";
        _status.text = "";

func _on_delete() -> void:
    if _selected == "":
        return;
    SaveGame.delete(_selected);
    _selected = "";
    _cancel_confirm();
    _status.text = "";
    _rebuild();

# Re-reads the list (after a save from this panel).
func refresh(message:String = "") -> void:
    _status.text = message;
    _rebuild();

func close() -> void:
    closed.emit();
    queue_free();

func _input(ev:InputEvent) -> void:
    if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
        get_viewport().set_input_as_handled();
        close();
