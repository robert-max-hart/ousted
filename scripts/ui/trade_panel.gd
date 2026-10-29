# ----------------------------------------------------------------
# TradePanel
#     The barter window, opened from the Trading Post's inspector while
#     a merchant is there. Left: what the merchant sells (price per
#     unit and how many they have). Right: what the colony could offer
#     (what they would pay per unit). Quantities are set with - and +;
#     the balance line says whether the offer covers the purchase, and
#     Place order hands the deal to TradingPost, whose goods citizens
#     then haul. While an order is open the window shows its progress.
# ----------------------------------------------------------------
class_name TradePanel extends PanelContainer;

const REFRESH:float = 0.5;

var _post       :TradingPost;
var _buy_qty    :Dictionary = {};      # item -> units to buy from the merchant
var _sell_qty   :Dictionary = {};      # item -> units to sell to the merchant
var _title      :Label;
var _buy_list   :VBoxContainer;
var _sell_list  :VBoxContainer;
var _balance    :Label;
var _message    :Label;
var _place      :Button;
var _timer      :float = 0.0;
var _sig        :String = "";

func setup() -> void:
    visible = false;
    set_anchors_and_offsets_preset(Control.PRESET_CENTER);
    custom_minimum_size = Vector2(700, 460);
    offset_left = -350.0;
    offset_right = 350.0;
    offset_top = -230.0;
    offset_bottom = 230.0;
    mouse_filter = Control.MOUSE_FILTER_STOP;
    var style:StyleBoxFlat = StyleBoxFlat.new();
    style.bg_color = Color(0.08, 0.07, 0.06, 0.97);
    style.set_corner_radius_all(6);
    style.set_content_margin_all(10);
    add_theme_stylebox_override("panel", style);
    PanelMover.make_movable(self, &"trade");
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
    var cols:HBoxContainer = HBoxContainer.new();
    cols.size_flags_vertical = Control.SIZE_EXPAND_FILL;
    cols.add_theme_constant_override("separation", 14);
    col.add_child(cols);
    _buy_list = _column(cols, "The merchant sells (you pay)");
    _sell_list = _column(cols, "You offer (they pay)");
    _balance = Label.new();
    col.add_child(_balance);
    _message = Label.new();
    _message.add_theme_color_override("font_color", Color(1.0, 0.7, 0.5));
    _message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;
    col.add_child(_message);
    _place = Button.new();
    _place.text = "Place order";
    _place.focus_mode = Control.FOCUS_NONE;
    _place.custom_minimum_size = Vector2(0, 38);
    _place.pressed.connect(_on_place);
    col.add_child(_place);

func _column(row:HBoxContainer, heading:String) -> VBoxContainer:
    var box:VBoxContainer = VBoxContainer.new();
    box.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
    row.add_child(box);
    var l:Label = Label.new();
    l.text = heading;
    l.add_theme_color_override("font_color", Color(0.97, 0.78, 0.16));
    box.add_child(l);
    var scroll:ScrollContainer = ScrollContainer.new();
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL;
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED;
    box.add_child(scroll);
    var list:VBoxContainer = VBoxContainer.new();
    list.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
    scroll.add_child(list);
    return list;

func open(post:TradingPost) -> void:
    _post = post;
    _buy_qty.clear();
    _sell_qty.clear();
    _message.text = "";
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

func _traders() -> Traders:
    return World.instance.traders;

func _refresh() -> void:
    if not World.alive(_post) or not _traders().present():
        visible = false;
        return;
    var t:Traders = _traders();
    var left:int = t.visit["days_left"];
    _title.text = "Trading with the merchant: they stay %d more day%s" % [left, "" if left == 1 else "s"];
    # rows only change when the lists do; quantities are updated in place
    var items:Array[StringName] = [];
    for item in t.visit["stock"]:
        items.append(item);
    var mine:Array[StringName] = [];
    for item in Defs.TRADE_VALUE:
        if Stock.available(item) > 0:
            mine.append(item);
    var sig:String = "%s|%s|%s" % [items, mine, _post.has_order()];
    if sig != _sig:
        _sig = sig;
        _rows(_buy_list, items, true);
        _rows(_sell_list, mine, false);
    _update_totals();

func _rows(list:VBoxContainer, items:Array[StringName], buying:bool) -> void:
    for c in list.get_children():
        c.queue_free();
    var locked:bool = _post.has_order();
    for item in items:
        var row:HBoxContainer = HBoxContainer.new();
        var name:Label = Label.new();
        name.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
        name.clip_text = true;
        row.add_child(name);
        var qty:Label = Label.new();
        qty.custom_minimum_size.x = 44;
        qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;
        qty.name = "Qty";
        var minus:Button = _step_button("-");
        var plus:Button = _step_button("+");
        minus.disabled = locked;
        plus.disabled = locked;
        minus.pressed.connect(_change.bind(item, buying, -1));
        plus.pressed.connect(_change.bind(item, buying, 1));
        row.add_child(minus);
        row.add_child(qty);
        row.add_child(plus);
        row.set_meta("item", item);
        name.name = "Name";
        list.add_child(row);
    _update_rows(list, buying);

func _step_button(text:String) -> Button:
    var b:Button = Button.new();
    b.text = text;
    b.focus_mode = Control.FOCUS_NONE;
    b.custom_minimum_size = Vector2(30, 0);
    return b;

func _update_rows(list:VBoxContainer, buying:bool) -> void:
    var t:Traders = _traders();
    var qtys:Dictionary = _buy_qty if buying else _sell_qty;
    for row in list.get_children():
        var item:StringName = row.get_meta("item");
        var have:int = t.visit["stock"].get(item, 0) if buying else Stock.available(item);
        var price:float = t.buy_price(item) if buying else t.sell_price(item);
        (row.get_node("Name") as Label).text = "%s  (%s each, %d)" % [Defs.offer_name(item) if buying else Defs.item_name(item), _fmt(price), have];
        (row.get_node("Qty") as Label).text = str(qtys.get(item, 0));
        if not buying:
            var good:bool = t.visit["wants"].has(item);
            (row.get_node("Name") as Label).add_theme_color_override("font_color", Color(0.65, 0.9, 0.55) if good else Color(0.8, 0.8, 0.78));

func _change(item:StringName, buying:bool, delta:int) -> void:
    var t:Traders = _traders();
    var qtys:Dictionary = _buy_qty if buying else _sell_qty;
    var cap:int = t.visit["stock"].get(item, 0) if buying else Stock.available(item);
    qtys[item] = clampi(qtys.get(item, 0) + delta, 0, cap);
    if qtys[item] == 0:
        qtys.erase(item);
    _message.text = "";
    _update_totals();

func _totals() -> Vector2:
    var t:Traders = _traders();
    var pay:float = 0.0;
    var get:float = 0.0;
    for item in _buy_qty:
        pay += _buy_qty[item] * t.buy_price(item);
    for item in _sell_qty:
        get += _sell_qty[item] * t.sell_price(item);
    return Vector2(get, pay);

func _update_totals() -> void:
    _update_rows(_buy_list, true);
    _update_rows(_sell_list, false);
    if _post.has_order():
        var lines:PackedStringArray = [];
        for item in _post.order["sell"]:
            lines.append("%s %d of %d" % [Defs.item_name(item), _post.order["delivered"].get(item, 0), _post.order["sell"][item]]);
        _balance.text = "Order open. Citizens are carrying goods to the post: %s" % ", ".join(lines);
        _place.disabled = true;
        _place.text = "Order in progress";
        return;
    var sums:Vector2 = _totals();
    var note:String = "";
    if sums.x + 0.0001 < sums.y:
        note = "  Offer more, or ask for less.";
    elif sums.x - sums.y >= 1.0 and sums.y > 0.0:
        note = "  The extra %s is lost: ask for more, or offer less." % _fmt(sums.x - sums.y);
    _balance.text = "They pay %s for your goods; you owe %s for theirs.%s" % [_fmt(sums.x), _fmt(sums.y), note];
    _place.text = "Place order";
    _place.disabled = _buy_qty.is_empty() or sums.x + 0.0001 < sums.y;

func _on_place() -> void:
    var err:String = _post.place_order(_sell_qty.duplicate(), _buy_qty.duplicate());
    _message.text = err if err != "" else "Order placed: citizens will carry your goods to the post.";
    if err == "":
        _buy_qty.clear();
        _sell_qty.clear();
        _sig = "";
    _refresh();

func _fmt(v:float) -> String:
    return "%.2f" % v if absf(v - roundf(v)) > 0.005 else "%d" % roundi(v);
