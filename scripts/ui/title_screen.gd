# ----------------------------------------------------------------
# TitleScreen
#     The first scene. A frozen mock town (TitleBackdrop, in a random
#     season) behind the game's name in big golden letters, with
#     Continue, New Game and Quit. New Game picks a difficulty and
#     optionally a map seed, then starts the main scene.
# ----------------------------------------------------------------
class_name TitleScreen extends Node;

const GOLD          :Color = Color(0.97, 0.78, 0.16);
const GOLD_EDGE     :Color = Color(0.36, 0.2, 0.03);
const TITLE_HOUR    :float = 17.2;       # late afternoon light
const SERIF_FONTS   :Array[String] = ["URW Bookman", "Bookman Old Style", "Palatino Linotype", "Palatino", "Georgia", "DejaVu Serif", "serif"];

var _menu       :VBoxContainer;
var _new_panel  :PanelContainer;
var _difficulty :StringName = &"normal";
var _choose_start:CheckBox;
var _size_pick  :OptionButton;
var _river_pick :OptionButton;
var _river_text :Label;
var _hills_pick :OptionButton;
var _climate_pick:OptionButton;
var _climate_text:Label;
var _climate_warn:Label;
var _new_scroll :ScrollContainer;      # the New Game options (they scroll on a small screen)
var _rules_box  :VBoxContainer;       # the custom rules, folded away until asked for
var _start_pick :OptionButton;
var _settlers_pick:OptionButton;
var _supplies_pick:OptionButton;
var _merchants_pick:OptionButton;
var _droughts_check:CheckBox;
var _realism_check:CheckBox;
var _diff_btns  :Dictionary = {};        # difficulty id -> Button
var _diff_text  :Label;
var _seed_edit  :LineEdit;
var _message    :Label;
var _changes    :PanelContainer;         # the changelist overlay (data/changelist.txt)
var _ui_root    :Control;               # the menu's layer: modal panels go in here so they draw over the menu
var _continue_slot:String = "";

func _ready() -> void:
    _build_backdrop();
    _build_ui();

# A World built as a picture: random map and season, clock stopped, light at golden hour.
func _build_backdrop() -> void:
    GameClock.set_speed(0);
    var season:int = randi() % 4;
    GameClock.total_hours = float((season * GameClock.DAYS_PER_SEASON + 3) * GameClock.HOURS_PER_DAY) + TITLE_HOUR;
    Weather.reset(0.85 if randf() < 0.35 else 0.0);       # now and then it rains (or, in winter, snows) behind the title
    Terrain.set_size(Terrain.DEFAULT_SIZE);       # the backdrop town is always on a Large map with the usual river
    Terrain.river_style = Terrain.RiverStyle.WINDING;
    Climate.current = Climate.Id.TEMPERATE;
    Terrain.hills_level = Terrain.Hills.NORMAL;
    GameRules.reset();
    World.backdrop = true;
    add_child((load(SaveGame.MAIN_SCENE) as PackedScene).instantiate());
    World.backdrop = false;

func _build_ui() -> void:
    var layer:CanvasLayer = CanvasLayer.new();
    add_child(layer);
    var root:Control = Control.new();
    root.set_anchors_preset(Control.PRESET_FULL_RECT);
    root.theme = _theme();
    layer.add_child(root);
    _ui_root = root;

    # darken the top and bottom a little so the letters and buttons read against any scene
    var shade:GradientTexture2D = GradientTexture2D.new();
    shade.fill_from = Vector2(0, 0);
    shade.fill_to = Vector2(0, 1);
    shade.gradient = Gradient.new();
    shade.gradient.offsets = PackedFloat32Array([0.0, 0.32, 0.65, 1.0]);
    shade.gradient.colors = PackedColorArray([Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.6)]);
    var shade_rect:TextureRect = TextureRect.new();
    shade_rect.texture = shade;
    shade_rect.set_anchors_preset(Control.PRESET_FULL_RECT);
    shade_rect.stretch_mode = TextureRect.STRETCH_SCALE;
    shade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE;
    root.add_child(shade_rect);

    var title:Label = Label.new();
    title.text = "Ousted";
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;
    title.set_anchors_preset(Control.PRESET_CENTER_TOP);
    title.anchor_left = 0.0;
    title.anchor_right = 1.0;
    title.offset_left = 0.0;
    title.offset_right = 0.0;
    title.offset_top = 36.0;
    title.add_theme_font_override("font", _title_font());
    title.add_theme_font_size_override("font_size", 132);
    title.add_theme_color_override("font_color", GOLD);
    title.add_theme_color_override("font_outline_color", GOLD_EDGE);
    title.add_theme_constant_override("outline_size", 16);
    title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55));
    title.add_theme_constant_override("shadow_offset_x", 4);
    title.add_theme_constant_override("shadow_offset_y", 6);
    title.mouse_filter = Control.MOUSE_FILTER_IGNORE;
    root.add_child(title);

    var center:CenterContainer = CenterContainer.new();
    center.set_anchors_preset(Control.PRESET_FULL_RECT);
    center.anchor_right = 0.4;       # the menu sits in the left part of the screen, the town in the rest
    center.offset_top = 150.0;
    center.mouse_filter = Control.MOUSE_FILTER_IGNORE;
    root.add_child(center);
    var stack:VBoxContainer = VBoxContainer.new();
    stack.add_theme_constant_override("separation", 10);
    center.add_child(stack);
    _menu = VBoxContainer.new();
    _menu.add_theme_constant_override("separation", 10);
    stack.add_child(_menu);
    Settings.apply_window();
    _continue_slot = "quicksave" if SaveGame.loadable(SaveGame.QUICKSAVE) else "autosave" if SaveGame.loadable(SaveGame.AUTOSAVE) else "";
    var cont:Button = _menu_button("Continue");
    cont.disabled = _continue_slot == "";
    cont.tooltip_text = "Load your last saved game" if _continue_slot != "" else "There is no saved game yet";
    cont.pressed.connect(_on_continue);
    var new_game:Button = _menu_button("New Game");
    new_game.pressed.connect(_show_new_game);
    var scenarios:Button = _menu_button("Scenarios");
    scenarios.tooltip_text = "Preset games with goals to reach";
    scenarios.pressed.connect(_show_scenarios);
    var tutorial:Button = _menu_button("Tutorial");
    tutorial.tooltip_text = "A guided first game on a mild map: build, farm and survive a winter";
    tutorial.pressed.connect(_on_tutorial);
    var load_game:Button = _menu_button("Load Game");
    load_game.tooltip_text = "Pick a saved game";
    load_game.pressed.connect(_show_load);
    var settings:Button = _menu_button("Settings");
    settings.tooltip_text = "Graphics and window options";
    settings.pressed.connect(func() -> void: _ui_root.add_child(SettingsPanel.new()));
    var changes:Button = _menu_button("Changelist");
    changes.tooltip_text = "What changed in each push to main";
    changes.pressed.connect(func() -> void: _changes.visible = true);
    var quit:Button = _menu_button("Quit");
    quit.pressed.connect(get_tree().quit);
    _build_new_game_panel(stack);
    _build_changelist(root);
    _message = Label.new();
    _message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;
    _message.add_theme_color_override("font_color", Color(1.0, 0.6, 0.5));
    stack.add_child(_message);
    (new_game if cont.disabled else cont).grab_focus();

    var footer:Label = Label.new();
    footer.text = "A colony of the cold north. Prototype.";
    footer.add_theme_color_override("font_color", Color(1, 1, 1, 0.6));
    footer.set_anchors_preset(Control.PRESET_BOTTOM_LEFT);
    footer.grow_vertical = Control.GROW_DIRECTION_BEGIN;
    footer.offset_left = 14.0;
    footer.offset_bottom = -10.0;
    root.add_child(footer);
    var build:Label = Label.new();       # the build id, in step with the changelist
    build.text = Changelist.build_id();
    build.add_theme_color_override("font_color", Color(1, 1, 1, 0.6));
    build.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT);
    build.grow_horizontal = Control.GROW_DIRECTION_BEGIN;
    build.grow_vertical = Control.GROW_DIRECTION_BEGIN;
    build.offset_right = -14.0;
    build.offset_bottom = -10.0;
    build.mouse_filter = Control.MOUSE_FILTER_IGNORE;
    root.add_child(build);

# The changelist overlay: one heading per push, newest first, read from data/changelist.txt.
func _build_changelist(root:Control) -> void:
    _changes = PanelContainer.new();
    _changes.visible = false;
    _changes.set_anchors_preset(Control.PRESET_CENTER);
    _changes.custom_minimum_size = Vector2(660, 520);
    _changes.offset_left = -60.0;       # right of centre, so the menu buttons stay in view
    _changes.offset_right = 600.0;
    _changes.offset_top = -190.0;
    _changes.offset_bottom = 330.0;
    root.add_child(_changes);
    var col:VBoxContainer = VBoxContainer.new();
    col.add_theme_constant_override("separation", 8);
    _changes.add_child(col);
    var heading:Label = Label.new();
    heading.text = "Changelist";
    heading.add_theme_font_size_override("font_size", 28);
    heading.add_theme_color_override("font_color", GOLD);
    col.add_child(heading);
    var scroll:ScrollContainer = ScrollContainer.new();
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL;
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED;
    col.add_child(scroll);
    var list:VBoxContainer = VBoxContainer.new();
    list.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
    list.add_theme_constant_override("separation", 4);
    scroll.add_child(list);
    for section in Changelist.parse():
        var head:Label = Label.new();
        head.text = "%s  (%s)  %s" % [section["version"], section["date"], section["title"]];
        head.add_theme_font_size_override("font_size", 19);
        head.add_theme_color_override("font_color", GOLD);
        head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;
        if list.get_child_count() > 0:
            var gap:Control = Control.new();
            gap.custom_minimum_size.y = 10;
            list.add_child(gap);
        list.add_child(head);
        for line in section["items"]:
            var item:Label = Label.new();
            item.text = "- " + line;
            item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;
            item.custom_minimum_size.x = 600;
            list.add_child(item);
    var close:Button = Button.new();
    close.text = "Close";
    close.custom_minimum_size = Vector2(0, 40);
    close.pressed.connect(func() -> void: _changes.visible = false);
    col.add_child(close);

func _menu_button(text:String) -> Button:
    var b:Button = Button.new();
    b.text = text;
    b.custom_minimum_size = Vector2(260, 46);
    b.focus_mode = Control.FOCUS_ALL;
    _menu.add_child(b);
    return b;

func _build_new_game_panel(stack:VBoxContainer) -> void:
    _new_panel = PanelContainer.new();
    _new_panel.visible = false;
    _new_panel.custom_minimum_size = Vector2(430, 0);
    stack.add_child(_new_panel);
    var outer:VBoxContainer = VBoxContainer.new();       # heading and buttons stay put, the options between them scroll
    outer.add_theme_constant_override("separation", 8);
    _new_panel.add_child(outer);
    var heading:Label = Label.new();
    heading.text = "New Game";
    heading.add_theme_font_size_override("font_size", 24);
    heading.add_theme_color_override("font_color", GOLD);
    outer.add_child(heading);
    var scroll:ScrollContainer = ScrollContainer.new();
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED;
    scroll.custom_minimum_size.y = clampf(get_viewport().get_visible_rect().size.y - 340.0, 200.0, 620.0);
    outer.add_child(scroll);
    _new_scroll = scroll;
    var col:VBoxContainer = VBoxContainer.new();
    col.add_theme_constant_override("separation", 8);
    col.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
    scroll.add_child(col);
    var row:HBoxContainer = HBoxContainer.new();
    row.add_theme_constant_override("separation", 8);
    col.add_child(row);
    var group:ButtonGroup = ButtonGroup.new();
    for id in [&"easy", &"normal", &"hard"]:
        var b:Button = Button.new();
        b.text = Defs.DIFFICULTIES[id]["name"];
        b.toggle_mode = true;
        b.button_group = group;
        b.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
        b.custom_minimum_size = Vector2(0, 38);
        b.pressed.connect(_pick_difficulty.bind(id));
        row.add_child(b);
        _diff_btns[id] = b;
    _diff_text = Label.new();
    _diff_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;
    _diff_text.custom_minimum_size = Vector2(400, 64);
    col.add_child(_diff_text);
    _size_pick = OptionButton.new();
    for i in Terrain.MAP_SIZES.size():
        _size_pick.add_item("%s (%d x %d)" % [Terrain.MAP_SIZE_NAMES[i], Terrain.MAP_SIZES[i], Terrain.MAP_SIZES[i]]);
    _size_pick.select(Terrain.MAP_SIZES.find(Terrain.DEFAULT_SIZE));
    _setup_row(col, "Map size", _size_pick);
    _river_pick = OptionButton.new();
    for id in Terrain.RIVER_STYLES:
        _river_pick.add_item(Terrain.RIVER_STYLES[id]["name"], id);
    _river_pick.select(_river_pick.get_item_index(Terrain.RiverStyle.WINDING));
    _river_pick.item_selected.connect(func(_i:int) -> void: _show_river_text());
    _setup_row(col, "Water", _river_pick);
    _river_text = Label.new();
    _river_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;
    _river_text.custom_minimum_size = Vector2(400, 0);
    _river_text.add_theme_color_override("font_color", Color(1, 1, 1, 0.7));
    col.add_child(_river_text);
    _show_river_text();
    _hills_pick = OptionButton.new();
    for id in Terrain.HILLS:
        _hills_pick.add_item(Terrain.HILLS[id]["name"], id);
        _hills_pick.set_item_tooltip(_hills_pick.get_item_count() - 1, Terrain.HILLS[id]["desc"]);
    _hills_pick.select(_hills_pick.get_item_index(Terrain.Hills.NORMAL));
    _hills_pick.tooltip_text = "How hilly the map is. Hills hold the stone and iron; level ground is where you build.";
    _setup_row(col, "Hills", _hills_pick);
    _climate_pick = OptionButton.new();
    for id in Climate.DEFS:
        _climate_pick.add_item(Climate.name_of(id), id);
    _climate_pick.select(_climate_pick.get_item_index(Climate.Id.TEMPERATE));
    _climate_pick.item_selected.connect(func(_i:int) -> void: _show_climate_text());
    _setup_row(col, "Climate", _climate_pick);
    _climate_text = Label.new();
    _climate_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;
    _climate_text.custom_minimum_size = Vector2(400, 0);
    _climate_text.add_theme_color_override("font_color", Color(1, 1, 1, 0.7));
    col.add_child(_climate_text);
    _climate_warn = Label.new();
    _climate_warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;
    _climate_warn.custom_minimum_size = Vector2(400, 0);
    _climate_warn.add_theme_color_override("font_color", Color(1.0, 0.6, 0.4));
    col.add_child(_climate_warn);
    _show_climate_text();
    _build_rules(col);
    var seed_row:HBoxContainer = HBoxContainer.new();
    col.add_child(seed_row);
    var seed_label:Label = Label.new();
    seed_label.text = "Map seed";
    seed_label.custom_minimum_size.x = 90;
    seed_row.add_child(seed_label);
    _seed_edit = LineEdit.new();
    _seed_edit.placeholder_text = "Random";
    _seed_edit.max_length = 9;
    _seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
    seed_row.add_child(_seed_edit);
    _choose_start = CheckBox.new();
    _choose_start.text = "Choose where to settle";
    _choose_start.button_pressed = true;
    _choose_start.tooltip_text = "Look over the map first and place the Town Hall yourself. Off: the game picks a level spot near the river.";
    col.add_child(_choose_start);
    var buttons:HBoxContainer = HBoxContainer.new();
    buttons.add_theme_constant_override("separation", 8);
    outer.add_child(buttons);
    var back:Button = Button.new();
    back.text = "Back";
    back.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
    back.pressed.connect(_show_menu);
    buttons.add_child(back);
    var start:Button = Button.new();
    start.text = "Start";
    start.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
    start.pressed.connect(_on_start);
    buttons.add_child(start);
    _pick_difficulty(&"normal");

func _setup_row(col:Container, text:String, control:Control) -> void:
    var row:HBoxContainer = HBoxContainer.new();
    var l:Label = Label.new();
    l.text = text;
    l.custom_minimum_size.x = 90;
    row.add_child(l);
    control.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
    row.add_child(control);
    col.add_child(row);

func _show_river_text() -> void:
    _river_text.text = Terrain.RIVER_STYLES[_river_pick.get_selected_id()]["desc"];

# Realism mode and a folded "Custom rules" block (settlers, supplies, merchants, droughts) on top of the preset.
@warning_ignore("integer_division")
func _build_rules(col:Container) -> void:
    _realism_check = CheckBox.new();
    _realism_check.text = "Realism mode";
    _realism_check.tooltip_text = "Slower days (a day lasts 6 real minutes at normal speed) and citizens age at the pace of the calendar: a citizen year is a whole game year, so children take 18 years to grow up.";
    col.add_child(_realism_check);
    var toggle:Button = Button.new();
    toggle.text = "Custom rules...";
    toggle.toggle_mode = true;
    toggle.tooltip_text = "Settlers, starting supplies, merchants and droughts";
    col.add_child(toggle);
    _rules_box = VBoxContainer.new();
    _rules_box.add_theme_constant_override("separation", 6);
    _rules_box.visible = false;
    col.add_child(_rules_box);
    toggle.toggled.connect(func(on:bool) -> void: _rules_box.visible = on);
    _start_pick = OptionButton.new();
    for i in GameRules.START_NAMES.size():
        _start_pick.add_item(GameRules.START_NAMES[i]);
        _start_pick.set_item_tooltip(i, GameRules.START_DESCS[i]);
    _start_pick.tooltip_text = "What the settlers arrive with besides their supply cart";
    _start_pick.item_selected.connect(func(_i:int) -> void: _pick_difficulty(_difficulty));
    _setup_row(_rules_box, "Start with", _start_pick);
    _settlers_pick = OptionButton.new();
    for n in GameRules.SETTLERS:
        _settlers_pick.add_item("%d (%d children)" % [n, n / 4]);
    _settlers_pick.select(GameRules.SETTLERS.find(12));
    _setup_row(_rules_box, "Settlers", _settlers_pick);
    _supplies_pick = OptionButton.new();
    for i in GameRules.SUPPLY_NAMES.size():
        _supplies_pick.add_item("%s (%d%%)" % [GameRules.SUPPLY_NAMES[i], roundi(GameRules.SUPPLY_SHARES[i] * 100.0)]);
    _supplies_pick.select(2);
    _setup_row(_rules_box, "Supplies", _supplies_pick);
    _merchants_pick = OptionButton.new();
    for n in GameRules.MERCHANT_NAMES:
        _merchants_pick.add_item(n);
    _merchants_pick.select(2);
    _setup_row(_rules_box, "Merchants", _merchants_pick);
    _droughts_check = CheckBox.new();
    _droughts_check.text = "Droughts";
    _droughts_check.button_pressed = true;
    _droughts_check.tooltip_text = "Dry spells with no rain, extra heat and fast-drying ground";
    _rules_box.add_child(_droughts_check);

func _show_climate_text() -> void:
    var d:Dictionary = Climate.DEFS[_climate_pick.get_selected_id()];
    var t:Array = d["temps"];
    _climate_text.text = "%s\nMean temperature: spring %d, summer %d, autumn %d, winter %d C." % [d["desc"], t[0], t[1], t[2], t[3]];
    _climate_warn.text = "Warning: %s" % d["warning"] if d.has("warning") else "";
    _climate_warn.visible = d.has("warning");
    if d.has("warning") and _new_scroll != null:
        _new_scroll.ensure_control_visible.call_deferred(_climate_warn);       # so a warning is never left below the fold

func _pick_difficulty(id:StringName) -> void:
    _difficulty = id;
    (_diff_btns[id] as Button).set_pressed_no_signal(true);
    var d:Dictionary = Defs.DIFFICULTIES[id];
    var upgrades:PackedStringArray = [];
    var start:int = _start_pick.selected if _start_pick != null else GameRules.Start.HALL;
    for up in (d["town_hall"] if start == GameRules.Start.HALL else []):
        upgrades.append(Defs.BUILDINGS[&"town_hall"]["upgrades"][up]["name"]);
    var seeds:PackedStringArray = [];
    for crop in d["seeds"]:
        seeds.append(Defs.CROPS[crop]["name"]);
    var trees:int = d.get("trees", 0);
    _diff_text.text = "%s\nSeeds to start: %s%s" % [("Town Hall: %s" % (", ".join(upgrades) if not upgrades.is_empty() else "bare (build storage yourself)")) if start == GameRules.Start.HALL else GameRules.START_DESCS[start], ", ".join(seeds), "\nOrchard saplings: %d, chosen at random" % trees if trees > 0 else ""];

func _show_new_game() -> void:
    _menu.visible = false;
    _new_panel.visible = true;
    _message.text = "";

func _show_menu() -> void:
    _new_panel.visible = false;
    _menu.visible = true;
    _message.text = "";

func _on_start() -> void:
    Defs.difficulty = _difficulty;
    var text:String = _seed_edit.text.strip_edges();
    World.new_game_seed = text.to_int() if text.is_valid_int() and text.to_int() > 0 else (hash(text) % 1000000 if text != "" else 0);
    World.choose_start = _choose_start.button_pressed;
    Terrain.set_size(Terrain.MAP_SIZES[_size_pick.selected]);
    Terrain.river_style = _river_pick.get_selected_id();
    Terrain.hills_level = _hills_pick.get_selected_id();
    Climate.current = _climate_pick.get_selected_id();
    GameRules.start = _start_pick.selected;
    GameRules.settlers = GameRules.SETTLERS[_settlers_pick.selected];
    GameRules.supplies = _supplies_pick.selected;
    GameRules.merchants = _merchants_pick.selected;
    GameRules.droughts = _droughts_check.button_pressed;
    GameRules.realism = _realism_check.button_pressed;
    _launch();

# The tutorial game: easy preset, a medium map with a winding river, mild weather (no droughts) and few merchants,
# the player chooses where to settle, and the guide panel is attached to the HUD.
func _on_tutorial() -> void:
    Defs.difficulty = &"easy";
    World.new_game_seed = 0;
    World.choose_start = true;
    Terrain.set_size(128);
    Terrain.river_style = Terrain.RiverStyle.WINDING;
    Climate.current = Climate.Id.TEMPERATE;
    GameRules.reset();
    GameRules.droughts = false;
    GameRules.merchants = 1;
    Tutorial.active = true;
    _launch();

func _show_scenarios() -> void:
    var list:ScenarioList = ScenarioList.new();
    _ui_root.add_child(list);
    list.chosen.connect(func(id:StringName, randomize:bool) -> void:
        Scenarios.apply(id, randomize);
        list.queue_free();
        _launch());

func _launch() -> void:
    GameClock.reset();
    Weather.reset();
    GameClock.locked = false;
    get_tree().change_scene_to_file(SaveGame.MAIN_SCENE);

func _show_load() -> void:
    var panel:SavePanel = SavePanel.new(false);
    _ui_root.add_child(panel);
    panel.load_chosen.connect(func(slot:String) -> void:
        _message.text = SaveGame.start_from_slot(get_tree(), slot);
        panel.queue_free());

func _on_continue() -> void:
    _message.text = SaveGame.start_from_slot(get_tree(), _continue_slot);

func _title_font() -> Font:
    var f:SystemFont = SystemFont.new();
    f.font_names = PackedStringArray(SERIF_FONTS);
    f.font_weight = 900;
    f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY;
    f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO;
    return f;

# Dark translucent buttons with a gold edge, in the same serif as the title.
func _theme() -> Theme:
    var t:Theme = Theme.new();
    var font:SystemFont = _title_font() as SystemFont;
    font.font_weight = 600;
    t.default_font = font;
    t.default_font_size = 20;
    var normal:StyleBoxFlat = _box(Color(0.1, 0.08, 0.05, 0.72), Color(0.6, 0.45, 0.12, 0.9));
    var hover:StyleBoxFlat = _box(Color(0.22, 0.16, 0.06, 0.85), GOLD);
    var pressed:StyleBoxFlat = _box(Color(0.32, 0.22, 0.05, 0.92), GOLD);
    var disabled:StyleBoxFlat = _box(Color(0.08, 0.08, 0.08, 0.55), Color(0.4, 0.4, 0.4, 0.5));
    for style_name in ["normal", "hover", "pressed", "disabled", "focus"]:
        var sb:StyleBoxFlat = {"normal": normal, "hover": hover, "pressed": pressed, "disabled": disabled, "focus": hover}[style_name];
        t.set_stylebox(style_name, "Button", sb);
    t.set_color("font_color", "Button", Color(0.95, 0.88, 0.7));
    t.set_color("font_hover_color", "Button", Color(1, 0.95, 0.75));
    t.set_color("font_pressed_color", "Button", GOLD);
    t.set_color("font_disabled_color", "Button", Color(0.55, 0.55, 0.5));
    t.set_stylebox("panel", "PanelContainer", _box(Color(0.08, 0.06, 0.04, 0.82), Color(0.6, 0.45, 0.12, 0.9), 14));
    t.set_color("font_color", "Label", Color(0.95, 0.9, 0.78));
    return t;

func _box(bg:Color, edge:Color, margin:int = 8) -> StyleBoxFlat:
    var s:StyleBoxFlat = StyleBoxFlat.new();
    s.bg_color = bg;
    s.border_color = edge;
    s.set_border_width_all(2);
    s.set_corner_radius_all(8);
    s.set_content_margin_all(margin);
    return s;
