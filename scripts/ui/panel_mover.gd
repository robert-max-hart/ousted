# ----------------------------------------------------------------
# PanelMover
#     Makes a HUD panel draggable by a grip strip along its top edge
#     (marked with a few dots, with a move cursor over it), keeps it
#     on screen, and remembers where the player put it between runs
#     (user://ui_layout.cfg). Static functions only.
# ----------------------------------------------------------------
class_name PanelMover extends RefCounted;

const GRIP_HEIGHT   :float = 14.0;
const SAVE_PATH     :String = "user://ui_layout.cfg";
const KEEP_VISIBLE  :float = 48.0;      # at least this much of a panel stays on screen

# Call once after the panel's style is set (this raises its top margin to make room for the grip).
static func make_movable(panel:Control, id:StringName) -> void:
    var style:StyleBox = panel.get_theme_stylebox("panel");
    if style is StyleBoxFlat:
        (style as StyleBoxFlat).content_margin_top = GRIP_HEIGHT + 2.0;
    panel.set_meta("drag_from", null);
    panel.set_meta("moved", false);
    panel.gui_input.connect(_on_gui_input.bind(panel, id));
    panel.draw.connect(_draw_grip.bind(panel));
    panel.item_rect_changed.connect(panel.queue_redraw);
    _restore.call_deferred(panel, id);

# After a panel's contents shrink or grow (a collapse), lets a moved panel take its natural height again: moving
# fixes its offsets to the size it had then.
static func refit_height(panel:Control) -> void:
    if has_moved(panel):
        panel.offset_bottom = panel.offset_top + 1.0;

static func has_moved(panel:Control) -> bool:
    return panel.get_meta("moved", false);

static func _draw_grip(panel:Control) -> void:
    var cx:float = panel.size.x * 0.5;
    for i in range(-2, 3):
        panel.draw_circle(Vector2(cx + i * 7.0, GRIP_HEIGHT * 0.5 + 1.0), 1.6, Color(1, 1, 1, 0.28));

static func _on_gui_input(event:InputEvent, panel:Control, id:StringName) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if event.pressed and event.position.y <= GRIP_HEIGHT:
            panel.set_meta("drag_from", event.global_position - panel.global_position);
            panel.accept_event();
        elif not event.pressed and panel.get_meta("drag_from") != null:
            panel.set_meta("drag_from", null);
            _save(panel, id);
            panel.accept_event();
    elif event is InputEventMouseMotion:
        panel.mouse_default_cursor_shape = Control.CURSOR_MOVE if event.position.y <= GRIP_HEIGHT or panel.get_meta("drag_from") != null else Control.CURSOR_ARROW;
        if panel.get_meta("drag_from") != null:
            _place(panel, event.global_position - (panel.get_meta("drag_from") as Vector2));
            panel.accept_event();

# Moves the panel's top-left corner to pos (kept on screen), freeing it from the anchors it started with.
static func _place(panel:Control, pos:Vector2) -> void:
    var view:Vector2 = panel.get_viewport_rect().size;
    var size:Vector2 = panel.size.max(panel.get_combined_minimum_size());
    pos.x = clampf(pos.x, KEEP_VISIBLE - size.x, view.x - KEEP_VISIBLE);
    pos.y = clampf(pos.y, 0.0, view.y - GRIP_HEIGHT * 2.0);
    panel.anchor_left = 0.0;
    panel.anchor_top = 0.0;
    panel.anchor_right = 0.0;
    panel.anchor_bottom = 0.0;
    panel.grow_horizontal = Control.GROW_DIRECTION_END;
    panel.grow_vertical = Control.GROW_DIRECTION_END;
    panel.offset_left = pos.x;
    panel.offset_top = pos.y;
    panel.offset_right = pos.x + size.x;
    panel.offset_bottom = pos.y + size.y;
    panel.set_meta("moved", true);

static func _save(panel:Control, id:StringName) -> void:
    var cfg:ConfigFile = ConfigFile.new();
    cfg.load(SAVE_PATH);
    cfg.set_value("panels", String(id), Vector2(panel.offset_left, panel.offset_top));
    cfg.save(SAVE_PATH);

static func _restore(panel:Variant, id:StringName) -> void:
    if not is_instance_valid(panel):       # the HUD may be gone already (a world was rebuilt)
        return;
    var cfg:ConfigFile = ConfigFile.new();
    if cfg.load(SAVE_PATH) != OK or not cfg.has_section_key("panels", String(id)):
        return;
    var pos:Variant = cfg.get_value("panels", String(id));
    if pos is Vector2:
        _place(panel, pos);

# Forgets every saved position (the default layout comes back at the next start).
static func reset_saved() -> void:
    DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH));
