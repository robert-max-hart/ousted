# ----------------------------------------------------------------
# LoadingScreen
#     The cover shown while a world is built (a new game, a loaded one, the picture behind the title): an
#     opaque overlay with the title, what is being done, a progress bar and a tip, so the map never appears
#     piece by piece. It lives under the scene tree's root, so it survives the change from the title to the
#     game. While it is up the game clock is held (GameClock.held). World._ready reports each stage with
#     progress() and, once everything has been built and drawn, calls finish(), which fades it out.
#     begin() is called by whatever starts the build (the title screen, loading a save); tests never call it, so a
#     world they make is built at once, as before.
# ----------------------------------------------------------------
class_name LoadingScreen extends CanvasLayer;

static var active:bool = false;
static var _instance:LoadingScreen = null;

const BACKGROUND:Color = Color(0.085, 0.07, 0.055);
const GOLD      :Color = Color(0.93, 0.76, 0.36);
const TEXT      :Color = Color(0.86, 0.8, 0.68);
const FADE_SECONDS:float = 0.5;
const TIPS:Array[String] = [
    "Fields need water: build near a river, a pond or a well, or dig channels.",
    "A varied diet keeps citizens happier. Foragers and fishermen fill the gaps before the first harvest.",
    "Pause and look around: nothing happens while the game is paused, so you can plan in peace.",
    "Frost kills young crops. A crop caught by the first frost can still be harvested early for most of its yield.",
    "Wood stoves need firewood. Set a woodcutter to make it before the first winter.",
    "Merchants walk in from the edge of the map. Keep spare goods in the Trading Post to sell them quickly.",
    "Citizens sleep in houses when they have them. Shacks are a stopgap: build real homes.",
    "Children go to school if there is a teacher. Schooling makes them better workers for life.",
    "Roads make citizens walk faster, and bridges let them cross the river without wading.",
    "A pasture needs only grass in summer. In the cold months the animals eat grain.",
    "The Soil, Water and Slope buttons on the top bar paint the ground to help you plan.",
    "Press Esc to open the menu, save the game or change settings.",
];

var _bar        :Control;
var _stage      :Label;
var _tip        :Label;
var _shown      :float = 0.0;      # the progress drawn, easing toward `_target`
var _target     :float = 0.0;
var _fading     :bool = false;
var _root       :Control;

# Puts the loading screen up (does nothing if it already is) and holds the game clock.
static func begin(tree:SceneTree) -> void:
    if active and is_instance_valid(_instance):
        return;
    active = true;
    GameClock.held = true;
    _instance = LoadingScreen.new();
    _instance.layer = 128;
    _instance.name = "LoadingScreen";
    tree.root.add_child.call_deferred(_instance);        # (the root may be busy setting up the scene that asked for this)

# What is being done, and how far along the build is (0 to 1).
static func progress(fraction:float, text:String) -> void:
    if is_instance_valid(_instance):
        _instance._set_progress(fraction, text);

# The world is ready: fade the screen out and let the game clock run.
static func finish() -> void:
    active = false;
    GameClock.held = false;
    if is_instance_valid(_instance):
        _instance._fade_out();
    _instance = null;

func _ready() -> void:
    _root = Control.new();
    _root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);
    _root.mouse_filter = Control.MOUSE_FILTER_STOP;       # (nothing underneath can be clicked while it loads)
    add_child(_root);
    var back:ColorRect = ColorRect.new();
    back.color = BACKGROUND;
    back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);
    _root.add_child(back);
    var centre:VBoxContainer = VBoxContainer.new();
    centre.set_anchors_and_offsets_preset(Control.PRESET_CENTER);
    centre.grow_horizontal = Control.GROW_DIRECTION_BOTH;
    centre.grow_vertical = Control.GROW_DIRECTION_BOTH;
    centre.custom_minimum_size = Vector2(520, 0);
    centre.add_theme_constant_override("separation", 14);
    _root.add_child(centre);
    var font:SystemFont = SystemFont.new();
    font.font_names = PackedStringArray(TitleScreen.SERIF_FONTS);
    font.font_weight = 900;
    var title:Label = Label.new();
    title.text = "Ousted";
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;
    title.add_theme_font_override("font", font);
    title.add_theme_font_size_override("font_size", 64);
    title.add_theme_color_override("font_color", GOLD);
    title.add_theme_color_override("font_outline_color", Color(0.18, 0.1, 0.04));
    title.add_theme_constant_override("outline_size", 8);
    centre.add_child(title);
    _bar = Control.new();
    _bar.custom_minimum_size = Vector2(520, 10);
    _bar.draw.connect(_draw_bar);
    centre.add_child(_bar);
    _stage = Label.new();
    _stage.text = "Loading";
    _stage.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;
    _stage.add_theme_font_size_override("font_size", 16);
    _stage.add_theme_color_override("font_color", TEXT);
    centre.add_child(_stage);
    _tip = Label.new();
    _tip.text = TIPS[randi() % TIPS.size()];
    _tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;
    _tip.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM;
    _tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;
    _tip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE);
    _tip.offset_top = -90;
    _tip.offset_bottom = -36;
    _tip.offset_left = 120;
    _tip.offset_right = -120;
    _tip.add_theme_font_size_override("font_size", 14);
    _tip.add_theme_color_override("font_color", Color(TEXT, 0.7));
    _root.add_child(_tip);

func _draw_bar() -> void:
    var w:float = _bar.size.x;
    _bar.draw_rect(Rect2(0, 3, w, 4), Color(1, 1, 1, 0.1));
    _bar.draw_rect(Rect2(0, 3, w * _shown, 4), GOLD);
    _bar.draw_rect(Rect2(w * _shown - 3, 0, 6, 10), Color(1.0, 0.9, 0.6));

func _set_progress(fraction:float, text:String) -> void:
    _target = maxf(_target, clampf(fraction, 0.0, 1.0));
    if _stage != null:
        _stage.text = text;

func _process(delta:float) -> void:
    _shown = move_toward(_shown, _target, delta * 0.6);
    if _bar != null:
        _bar.queue_redraw();

func _fade_out() -> void:
    if _fading:
        return;
    _fading = true;
    _target = 1.0;
    _shown = 1.0;
    _root.mouse_filter = Control.MOUSE_FILTER_IGNORE;
    var tween:Tween = create_tween();
    tween.tween_property(_root, "modulate:a", 0.0, FADE_SECONDS);
    tween.tween_callback(queue_free);
