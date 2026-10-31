# ----------------------------------------------------------------
# UI icons sheet
#     Checks that every glyph and stock icon file loads, then paints every UIIcons glyph on a button-coloured background,
#     enlarged, and saves it as a PNG to look at.
#     godot --headless --path . res://tests/ui_icons_sheet.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

func _ready() -> void:
    var out:String = "user://";
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0:
        out = args[0];
    var scale:int = 6;
    var cell:int = UIIcons.SIZE * scale + 16;
    var ids:Array[StringName] = UIIcons.IDS;
    var sheet:Image = Image.create(cell * 8, cell * ((ids.size() + 7) / 8), false, Image.FORMAT_RGBA8);
    sheet.fill(Color(0.15, 0.125, 0.095));
    var missing:int = 0;
    for id in ids:
        if not UIIcons.has(id):
            missing += 1;
            print("FAIL: no glyph file for ", id);
    for id in UIIcons.STOCK_IDS:
        if UIIcons.texture(id) == null:
            missing += 1;
            print("FAIL: no stock icon file for ", id);
    for i in ids.size():
        var img:Image = UIIcons.texture(ids[i]).get_image();
        img.resize(UIIcons.SIZE * scale, UIIcons.SIZE * scale, Image.INTERPOLATE_NEAREST);
        sheet.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i((i % 8) * cell + 8, (i / 8) * cell + 8));
    sheet.save_png(out.path_join("ui_icons.png"));
    print("UI ICONS %s (%d icons)" % ["PASS" if missing == 0 else "FAIL", ids.size()]);
    get_tree().quit(1 if missing > 0 else 0);
