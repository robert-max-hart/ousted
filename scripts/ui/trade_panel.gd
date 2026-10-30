# ----------------------------------------------------------------
# TradePanel
#     The barter window, opened from the Trading Post's inspector while
#     a merchant is there. Left: what the merchant sells (price per
#     unit and how many they have). Right: what the colony could offer
#     (what they would pay per unit). Quantities are set with - and +;
#     the balance line says whether the offer covers the purchase, and
#     Place order hands the deal to TradingPost, whose goods citizens
#     then haul. While an order is open the window shows its progress.
#     Each side is a table (item, unit price, stock, steppers). A price
#     is green when it favours the colony (cheap to buy, dear to sell)
#     and red when it does not; goods the merchant asked for are bold on
#     a golden backer and sorted to the top. A bar compares what they
#     pay with what is owed.
# ----------------------------------------------------------------
class_name TradePanel extends PanelContainer;

const REFRESH:float = 0.5;
const W_PRICE:float = 58.0;
const W_HAVE :float = 48.0;
const W_STEP :float = 30.0;
const W_QTY  :float = 36.0;
const W_MAX  :float = 42.0;
const PRICE_NEUTRAL:Color = Color(0.85, 0.85, 0.82);
const PRICE_GOOD   :Color = Color(0.45, 0.9, 0.45);
const PRICE_BAD    :Color = Color(1.0, 0.45, 0.4);
const PRICE_FULL   :float = 0.3;       # a season factor this far from 1 shows the full colour
const WANTED_BACK  :Color = Color(0.85, 0.68, 0.15, 0.28);

# What the two sides of the deal come to, drawn as one bar: green is what covers the bill, amber the part they pay for
# that the bill does not need (lost), a dim red stretch the part still missing; the white tick marks what is owed.
class BalanceBar extends Control:
    var pay_in:float = 0.0;
    var owed  :float = 0.0;

    func _init() -> void:
        custom_minimum_size = Vector2(0, 20);

    func set_values(get_value:float, owe:float) -> void:
        pay_in = get_value;
        owed = owe;
        queue_redraw();

    func _draw() -> void:
        var w:float = size.x;
        var h:float = size.y;
        draw_rect(Rect2(0, 0, w, h), Color(0.15, 0.14, 0.13));
        var scale:float = maxf(maxf(pay_in, owed), 1.0) * 1.15;
        var covered:float = minf(pay_in, owed);
        draw_rect(Rect2(0, 0, covered / scale * w, h), Color(0.35, 0.75, 0.35));
        if pay_in > owed:
            draw_rect(Rect2(owed / scale * w, 0, (pay_in - owed) / scale * w, h), Color(0.9, 0.7, 0.2));
        elif owed > pay_in:
            draw_rect(Rect2(pay_in / scale * w, 0, (owed - pay_in) / scale * w, h), Color(0.6, 0.2, 0.18, 0.7));
        if owed > 0.0:
            draw_rect(Rect2(owed / scale * w - 1.0, 0, 2.0, h), Color.WHITE);
        draw_rect(Rect2(0, 0, w, h), Color(0.4, 0.38, 0.34), false, 1.0);

var _post       :TradingPost;
var _buy_qty    :Dictionary = {};      # item -> units to buy from the merchant
var _sell_qty   :Dictionary = {};      # item -> units to sell to the merchant
var _title      :Label;
var _buy_list   :VBoxContainer;
var _sell_list  :VBoxContainer;
var _balance    :Label;
var _bar        :BalanceBar;
var _bold       :FontVariation;
var _message    :Label;
var _place      :Button;
var _timer      :float = 0.0;
var _sig        :String = "";

func setup() -> void:
    visible = false;
    set_anchors_and_offsets_preset(Control.PRESET_CENTER);
    custom_minimum_size = Vector2(1180, 480);
    offset_left = -590.0;
    offset_right = 590.0;
    offset_top = -240.0;
    offset_bottom = 240.0;
    mouse_filter = Control.MOUSE_FILTER_STOP;
    var style:StyleBoxFlat = StyleBoxFlat.new();
    style.bg_color = Color(0.08, 0.07, 0.06, 0.97);
    style.set_corner_radius_all(6);
    style.set_content_margin_all(10);
    add_theme_stylebox_override("panel", style);
    PanelMover.make_movable(self, &"trade");
    _bold = FontVariation.new();
    _bold.base_font = ThemeDB.fallback_font;
    _bold.variation_embolden = 0.9;
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
    _buy_list = _column(cols, "The merchant sells (you pay)", "Stock");
    _sell_list = _column(cols, "You offer (they pay)", "Spare");
    _bar = BalanceBar.new();
    col.add_child(_bar);
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

func _column(row:HBoxContainer, heading:String, have_title:String) -> VBoxContainer:
    var box:VBoxContainer = VBoxContainer.new();
    box.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
    row.add_child(box);
    var l:Label = Label.new();
    l.text = heading;
    l.add_theme_color_override("font_color", Color(0.97, 0.78, 0.16));
    box.add_child(l);
    var head:HBoxContainer = HBoxContainer.new();
    head.add_theme_constant_override("separation", 4);
    box.add_child(head);
    for h in [["Item", 0.0], ["Price", W_PRICE], [have_title, W_HAVE]]:
        var hl:Label = Label.new();
        hl.text = h[0];
        hl.add_theme_color_override("font_color", Color(0.65, 0.63, 0.58));
        if h[1] == 0.0:
            hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
        else:
            hl.custom_minimum_size.x = h[1];
            hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT;
        head.add_child(hl);
    var pad:Control = Control.new();
    pad.custom_minimum_size.x = W_STEP * 5.0 + W_QTY + W_MAX + 4.0 * 6.0;
    head.add_child(pad);
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
    _title.text = "Trading with the %s: they stay %d more day%s." % [t.type_name(), left, "" if left == 1 else "s"];
    # rows only change when the lists do; quantities are updated in place
    var items:Array[StringName] = [];
    for item in t.visit["stock"]:
        items.append(item);
    var mine:Array[StringName] = [];
    for item in Defs.TRADE_VALUE:         # what they asked for first, then the rest
        if _post.spare(item) > 0 and t.visit["wants"].has(item):
            mine.append(item);
    for item in Defs.TRADE_VALUE:
        if _post.spare(item) > 0 and not t.visit["wants"].has(item):
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
    var wants:Dictionary = _traders().visit["wants"];
    for item in items:
        var row:HBoxContainer = HBoxContainer.new();
        row.add_theme_constant_override("separation", 4);
        var wanted:bool = not buying and wants.has(item);
        var back:PanelContainer = PanelContainer.new();
        back.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
        var box:StyleBoxFlat = StyleBoxFlat.new();
        box.bg_color = WANTED_BACK if wanted else Color(0, 0, 0, 0);
        box.set_corner_radius_all(3);
        box.content_margin_left = 4.0;
        box.content_margin_right = 4.0;
        back.add_theme_stylebox_override("panel", box);
        var name:Label = Label.new();
        name.clip_text = true;
        if wanted:
            name.add_theme_font_override("font", _bold);
            name.tooltip_text = "The merchant asked for this";
        back.add_child(name);
        row.add_child(back);
        var price:Label = _cell(W_PRICE);
        var have:Label = _cell(W_HAVE);
        row.add_child(price);
        row.add_child(have);
        var qty:Label = Label.new();
        qty.custom_minimum_size.x = W_QTY;
        qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;
        for step in [["0", 0], ["-5", -5], ["-1", -1]]:
            row.add_child(_step_button(step[0], item, buying, step[1], locked, step[0] == "0"));
        row.add_child(qty);
        for step in [["+1", 1], ["+5", 5]]:
            row.add_child(_step_button(step[0], item, buying, step[1], locked, false));
        var most:Button = Button.new();
        most.text = "Max";
        most.tooltip_text = "Everything available";
        most.focus_mode = Control.FOCUS_NONE;
        most.custom_minimum_size.x = W_MAX;
        most.disabled = locked;
        most.pressed.connect(_set_max.bind(item, buying));
        row.add_child(most);
        row.set_meta("item", item);
        row.set_meta("ui", {"name": name, "price": price, "have": have, "qty": qty});
        list.add_child(row);
    _update_rows(list, buying);

func _cell(width:float) -> Label:
    var l:Label = Label.new();
    l.custom_minimum_size.x = width;
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT;
    l.mouse_filter = Control.MOUSE_FILTER_PASS;
    return l;

func _step_button(text:String, item:StringName, buying:bool, delta:int, locked:bool, zero:bool) -> Button:
    var b:Button = Button.new();
    b.text = text;
    b.focus_mode = Control.FOCUS_NONE;
    b.custom_minimum_size = Vector2(W_STEP, 0);
    b.disabled = locked;
    if zero:
        b.tooltip_text = "Clear this line";
        b.pressed.connect(_zero.bind(item, buying));
    else:
        b.pressed.connect(_change.bind(item, buying, delta));
    return b;

# Green when the price favours the colony (cheap to buy, dear to sell), red when it does not, plain near the usual.
func _price_color(factor:float, buying:bool) -> Color:
    var fav:float = (1.0 - factor) if buying else (factor - 1.0);
    var t:float = clampf(fav / PRICE_FULL, -1.0, 1.0);
    return PRICE_NEUTRAL.lerp(PRICE_GOOD if t > 0.0 else PRICE_BAD, absf(t));

func _update_rows(list:VBoxContainer, buying:bool) -> void:
    var t:Traders = _traders();
    var qtys:Dictionary = _buy_qty if buying else _sell_qty;
    for row in list.get_children():
        var item:StringName = row.get_meta("item");
        var ui:Dictionary = row.get_meta("ui");
        var have:int = t.visit["stock"].get(item, 0) if buying else _post.spare(item);
        var price:float = t.buy_price(item) if buying else t.sell_price(item);
        var factor:float = t.season_factor(item);
        (ui["name"] as Label).text = Defs.offer_name(item) if buying else Defs.item_name(item);
        var pl:Label = ui["price"];
        pl.text = _fmt(price);
        pl.add_theme_color_override("font_color", _price_color(factor, buying));
        pl.tooltip_text = "Usual price %s" % _fmt(snappedf(price / factor, 0.01));
        (ui["have"] as Label).text = str(have);
        (ui["qty"] as Label).text = str(qtys.get(item, 0));

func _change(item:StringName, buying:bool, delta:int) -> void:
    var t:Traders = _traders();
    var qtys:Dictionary = _buy_qty if buying else _sell_qty;
    var cap:int = t.visit["stock"].get(item, 0) if buying else _post.spare(item);
    qtys[item] = clampi(qtys.get(item, 0) + delta, 0, cap);
    if qtys[item] == 0:
        qtys.erase(item);
    _message.text = "";
    _update_totals();

func _zero(item:StringName, buying:bool) -> void:
    (_buy_qty if buying else _sell_qty).erase(item);
    _message.text = "";
    _update_totals();

func _set_max(item:StringName, buying:bool) -> void:
    var cap:int = _traders().visit["stock"].get(item, 0) if buying else _post.spare(item);
    _change(item, buying, cap);

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
        _bar.set_values(0.0, 0.0);
        return;
    var sums:Vector2 = _totals();
    _bar.set_values(sums.x, sums.y);
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
