# ----------------------------------------------------------------
# HoldPanel
#     The Trading Post's own inventory, opened from its inspector:
#     how much of each tradeable item to keep at the post for trading.
#     Laborers carry the goods there from storage (and carry any excess
#     back). Goods at the post are not colony stock, so nobody eats or
#     burns them. Purchases waiting to be carried out are listed too.
# ----------------------------------------------------------------
class_name HoldPanel extends PanelContainer;

const REFRESH:float = 0.5;

var _post   :TradingPost;
var _title  :Label;
var _list   :VBoxContainer;
var _foot   :Label;
var _timer  :float = 0.0;
var _sig    :String = "";

func setup() -> void:
    visible = false;
    set_anchors_and_offsets_preset(Control.PRESET_CENTER);
    custom_minimum_size = Vector2(520, 440);
    offset_left = -260.0;
    offset_right = 260.0;
    offset_top = -220.0;
    offset_bottom = 220.0;
    mouse_filter = Control.MOUSE_FILTER_STOP;
    var style:StyleBoxFlat = StyleBoxFlat.new();
    style.bg_color = Color(0.08, 0.07, 0.06, 0.97);
    style.set_corner_radius_all(6);
    style.set_content_margin_all(10);
    add_theme_stylebox_override("panel", style);
    PanelMover.make_movable(self, &"hold");
    var col:VBoxContainer = VBoxContainer.new();
    col.add_theme_constant_override("separation", 6);
    add_child(col);
    var head:HBoxContainer = HBoxContainer.new();
    col.add_child(head);
    _title = Label.new();
    _title.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
    head.add_child(_title);
    var close:Button = Button.new();
    close.text = "Close";
    close.focus_mode = Control.FOCUS_NONE;
    close.pressed.connect(func() -> void: visible = false);
    head.add_child(close);
    var note:Label = Label.new();
    note.text = "Goods kept here are set aside for trading: citizens cannot use them. Laborers carry them in and out.";
    note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;
    note.add_theme_color_override("font_color", Color(0.8, 0.8, 0.78));
    col.add_child(note);
    var scroll:ScrollContainer = ScrollContainer.new();
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL;
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED;
    col.add_child(scroll);
    _list = VBoxContainer.new();
    _list.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
    scroll.add_child(_list);
    _foot = Label.new();
    _foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;
    col.add_child(_foot);

func open(post:TradingPost) -> void:
    _post = post;
    _sig = "";
    visible = true;
    _refresh();

func _process(delta:float) -> void:
    if not visible:
        return;
    _timer -= delta;
    if _timer <= 0.0:
        _timer = REFRESH;
        _refresh();

# Items worth listing: tradeable ones in storage, at the post, or with a level set.
func _items() -> Array[StringName]:
    var out:Array[StringName] = [];
    for item in Defs.TRADE_VALUE:
        if Stock.amount(item) > 0 or _post.held(item) > 0 or _post.hold.has(item):
            out.append(item);
    return out;

func _refresh() -> void:
    if not World.alive(_post):
        visible = false;
        return;
    _title.text = "Goods held at the Trading Post: %d of %d" % [_post.held_total(), TradingPost.HOLD_CAP];
    var items:Array[StringName] = _items();
    var sig:String = str(items);
    if sig != _sig:
        _sig = sig;
        _rows(items);
    for row in _list.get_children():
        var item:StringName = row.get_meta("item");
        (row.get_node("Name") as Label).text = "%s   in store %d" % [Defs.item_name(item), Stock.amount(item)];
        (row.get_node("Level") as Label).text = "%d / %d" % [_post.held(item), _post.hold.get(item, 0)];
    var bought:PackedStringArray = [];
    for item in _post.pickup:
        bought.append("%d %s" % [_post.pickup[item], Defs.item_name(item).to_lower()]);
    _foot.text = "Bought goods waiting to be carried to storage: %s" % (", ".join(bought) if not bought.is_empty() else "none");

func _rows(items:Array[StringName]) -> void:
    for c in _list.get_children():
        c.queue_free();
    for item in items:
        var row:HBoxContainer = HBoxContainer.new();
        row.set_meta("item", item);
        var name:Label = Label.new();
        name.name = "Name";
        name.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
        name.clip_text = true;
        row.add_child(name);
        for step in [-25, -5, -1]:
            row.add_child(_button(step, item));
        var level:Label = Label.new();
        level.name = "Level";
        level.custom_minimum_size.x = 70;
        level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;
        row.add_child(level);
        for step in [1, 5, 25]:
            row.add_child(_button(step, item));
        _list.add_child(row);

func _button(step:int, item:StringName) -> Button:
    var b:Button = Button.new();
    b.text = ("+%d" if step > 0 else "%d") % step;
    b.focus_mode = Control.FOCUS_NONE;
    b.custom_minimum_size = Vector2(34, 0);
    b.pressed.connect(func() -> void:
        if World.alive(_post):
            _post.set_hold(item, _post.hold.get(item, 0) + step);
            _refresh());
    return b;
