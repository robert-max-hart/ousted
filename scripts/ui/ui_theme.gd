# ----------------------------------------------------------------
# UITheme
#     The look shared by the HUD, the modal windows and the title
#     screen: dark warm-brown panels with a thin gold edge, buttons
#     that warm up under the cursor, gold for what is selected.
#     make() builds the Theme (set it on the root control), panel_box()
#     is the one panel style every window and bar uses.
# ----------------------------------------------------------------
class_name UITheme extends RefCounted;

const GOLD       :Color = Color(0.97, 0.78, 0.16);
const EDGE       :Color = Color(0.55, 0.42, 0.14, 0.85);       # the thin gold-brown line round panels and buttons
const EDGE_SOFT  :Color = Color(0.45, 0.36, 0.16, 0.5);
const PANEL_BG   :Color = Color(0.085, 0.07, 0.055);
const TEXT       :Color = Color(0.95, 0.9, 0.78);
const TEXT_DIM   :Color = Color(0.62, 0.58, 0.5);

static var _theme:Theme;

# --------------------------------
# The shared panel style: `alpha` is the background opacity, `radius` the corners, `margin` the inner space.
static func panel_box(alpha:float = 0.88, radius:int = 6, margin:int = 8) -> StyleBoxFlat:
    var s:StyleBoxFlat = StyleBoxFlat.new();
    s.bg_color = Color(PANEL_BG, alpha);
    s.border_color = EDGE;
    s.set_border_width_all(1);
    s.set_corner_radius_all(radius);
    s.set_content_margin_all(margin);
    s.shadow_color = Color(0, 0, 0, 0.35);
    s.shadow_size = 4;
    return s;

static func _box(bg:Color, edge:Color, radius:int, mx:int, my:int, border:int = 1) -> StyleBoxFlat:
    var s:StyleBoxFlat = StyleBoxFlat.new();
    s.bg_color = bg;
    s.border_color = edge;
    s.set_border_width_all(border);
    s.set_corner_radius_all(radius);
    s.content_margin_left = mx;
    s.content_margin_right = mx;
    s.content_margin_top = my;
    s.content_margin_bottom = my;
    return s;

# --------------------------------
# The theme, built once. `font_size` is the text size of the whole interface.
static func make(font_size:int) -> Theme:
    if _theme != null and _theme.default_font_size == font_size:
        return _theme;
    var t:Theme = Theme.new();
    t.default_font_size = font_size;

    var normal :StyleBoxFlat = _box(Color(0.15, 0.125, 0.095, 0.9), EDGE_SOFT, 4, 6, 3);
    var hover  :StyleBoxFlat = _box(Color(0.27, 0.205, 0.1, 0.95), EDGE, 4, 6, 3);
    var pressed:StyleBoxFlat = _box(Color(0.36, 0.26, 0.07, 1.0), GOLD, 4, 6, 3);
    var disabled:StyleBoxFlat = _box(Color(0.1, 0.095, 0.085, 0.7), Color(0.3, 0.28, 0.24, 0.4), 4, 6, 3);
    var focus  :StyleBoxFlat = _box(Color(0, 0, 0, 0), Color(GOLD, 0.6), 4, 6, 3);
    for cls in ["Button", "OptionButton", "MenuButton"]:
        t.set_stylebox("normal", cls, normal);
        t.set_stylebox("hover", cls, hover);
        t.set_stylebox("pressed", cls, pressed);
        t.set_stylebox("hover_pressed", cls, pressed);
        t.set_stylebox("disabled", cls, disabled);
        t.set_stylebox("focus", cls, focus);
        t.set_color("font_color", cls, TEXT);
        t.set_color("font_hover_color", cls, Color(1, 0.96, 0.8));
        t.set_color("font_pressed_color", cls, GOLD);
        t.set_color("font_hover_pressed_color", cls, GOLD);
        t.set_color("font_focus_color", cls, TEXT);
        t.set_color("font_disabled_color", cls, TEXT_DIM);

    t.set_stylebox("panel", "PanelContainer", panel_box());
    t.set_stylebox("panel", "Panel", panel_box());
    t.set_color("font_color", "Label", TEXT);
    t.set_color("font_color", "RichTextLabel", TEXT);
    t.set_color("default_color", "RichTextLabel", TEXT);

    t.set_icon("checked", "CheckBox", _check_icon(true));
    t.set_icon("unchecked", "CheckBox", _check_icon(false));
    t.set_icon("checked_disabled", "CheckBox", _check_icon(true, true));
    t.set_icon("unchecked_disabled", "CheckBox", _check_icon(false, true));
    for cls in ["CheckBox", "CheckButton"]:
        t.set_color("font_color", cls, TEXT);
        t.set_color("font_hover_color", cls, Color(1, 0.96, 0.8));
        t.set_color("font_pressed_color", cls, GOLD);
        t.set_color("font_hover_pressed_color", cls, GOLD);
        t.set_color("font_disabled_color", cls, TEXT_DIM);
        t.set_stylebox("normal", cls, StyleBoxEmpty.new());
        t.set_stylebox("pressed", cls, StyleBoxEmpty.new());
        t.set_stylebox("hover", cls, StyleBoxEmpty.new());
        t.set_stylebox("hover_pressed", cls, StyleBoxEmpty.new());
        t.set_stylebox("disabled", cls, StyleBoxEmpty.new());
        t.set_stylebox("focus", cls, StyleBoxEmpty.new());

    var popup:StyleBoxFlat = panel_box(0.97, 4, 4);
    t.set_stylebox("panel", "PopupMenu", popup);
    t.set_stylebox("hover", "PopupMenu", _box(Color(0.3, 0.22, 0.08, 0.95), Color(0, 0, 0, 0), 3, 4, 2, 0));
    t.set_color("font_color", "PopupMenu", TEXT);
    t.set_color("font_hover_color", "PopupMenu", Color(1, 0.96, 0.8));
    t.set_color("font_disabled_color", "PopupMenu", TEXT_DIM);

    t.set_stylebox("panel", "TooltipPanel", _box(Color(0.06, 0.05, 0.04, 0.96), EDGE, 4, 7, 4));
    t.set_color("font_color", "TooltipLabel", TEXT);

    var field:StyleBoxFlat = _box(Color(0.05, 0.045, 0.04, 0.95), EDGE_SOFT, 3, 6, 3);
    t.set_stylebox("normal", "LineEdit", field);
    t.set_stylebox("focus", "LineEdit", _box(Color(0.05, 0.045, 0.04, 0.95), GOLD, 3, 6, 3));
    t.set_stylebox("read_only", "LineEdit", field);
    t.set_color("font_color", "LineEdit", TEXT);
    t.set_color("caret_color", "LineEdit", GOLD);
    t.set_color("selection_color", "LineEdit", Color(GOLD, 0.35));

    # scroll bars: a slim track and a warm grabber
    var track:StyleBoxFlat = _box(Color(0, 0, 0, 0.25), Color(0, 0, 0, 0), 4, 2, 2, 0);
    var grab :StyleBoxFlat = _box(Color(0.5, 0.4, 0.2, 0.75), Color(0, 0, 0, 0), 4, 2, 2, 0);
    var grab_hi:StyleBoxFlat = _box(Color(0.75, 0.6, 0.25, 0.9), Color(0, 0, 0, 0), 4, 2, 2, 0);
    for cls in ["VScrollBar", "HScrollBar"]:
        t.set_stylebox("scroll", cls, track);
        t.set_stylebox("scroll_focus", cls, track);
        t.set_stylebox("grabber", cls, grab);
        t.set_stylebox("grabber_highlight", cls, grab_hi);
        t.set_stylebox("grabber_pressed", cls, grab_hi);

    t.set_stylebox("background", "ProgressBar", _box(Color(0, 0, 0, 0.4), EDGE_SOFT, 3, 2, 2));
    t.set_stylebox("fill", "ProgressBar", _box(Color(0.62, 0.48, 0.14, 0.95), Color(0, 0, 0, 0), 3, 2, 2, 0));
    t.set_color("font_color", "ProgressBar", TEXT);

    var line:StyleBoxLine = StyleBoxLine.new();
    line.color = EDGE_SOFT;
    line.thickness = 1;
    t.set_stylebox("separator", "HSeparator", line);
    var vline:StyleBoxLine = StyleBoxLine.new();
    vline.color = EDGE_SOFT;
    vline.thickness = 1;
    vline.vertical = true;
    t.set_stylebox("separator", "VSeparator", vline);

    _theme = t;
    return t;

# A 16 px box with a gold edge, and a gold tick when checked (drawn at 4x and scaled down for soft edges).
static func _check_icon(on:bool, dim:bool = false) -> Texture2D:
    var big:int = 64;
    var img:Image = Image.create(big, big, false, Image.FORMAT_RGBA8);
    var edge:Color = Color(GOLD, 0.45 if dim else 1.0) if on else Color(EDGE, 0.5 if dim else 1.0);
    var fill:Color = Color(0.05, 0.045, 0.04, 0.95);
    for y in range(4, big - 4):
        for x in range(4, big - 4):
            var rim:bool = x < 9 or y < 9 or x >= big - 9 or y >= big - 9;
            img.set_pixel(x, y, edge if rim else fill);
    if on:
        var tick:Color = Color(GOLD, 0.45 if dim else 1.0);
        for i in 14:       # down stroke then up stroke, 7 px thick
            _dot(img, 16 + i, 32 + i, tick);
        for i in 28:
            _dot(img, 30 + i, 46 - i, tick);
    img.resize(16, 16, Image.INTERPOLATE_LANCZOS);
    return ImageTexture.create_from_image(img);

static func _dot(img:Image, cx:int, cy:int, c:Color) -> void:
    for y in range(cy - 3, cy + 4):
        for x in range(cx - 3, cx + 4):
            if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
                img.set_pixel(x, y, c);
