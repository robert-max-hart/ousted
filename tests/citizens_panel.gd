# ----------------------------------------------------------------
# CitizensPanel
#     Every column sorts, both ways, however many times and in whatever
#     order the headings are clicked; the headings and rows are not
#     replaced while the order changes underneath; the Sick column shows
#     illness; a sick citizen has a marker.
#     godot --headless --path . --fixed-fps 60 res://tests/citizens_panel.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Weather.drought_enabled = false;
    GameRules.reset();
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    var i:int = 0;
    for p in world.pawns:                  # distinct, shuffled values in every column (two share a name)
        p.age = 18.0 + float((i * 7) % 11);
        p.mood = float((i * 5) % 12) / 12.0;
        p.status = "Doing %d" % ((i * 3) % 7);
        p.illness = 0.0 if i % 3 != 0 else 0.1 + 0.05 * i;
        i += 1;
    world.pawns[1].first_name = world.pawns[0].first_name;
    var panel:CitizensPanel = CitizensPanel.new();
    add_child(panel);
    panel.setup();
    panel.visible = true;
    panel._refresh();
    var heads:Array = panel._heads.duplicate();
    _expect("a heading for each column", heads.size() == CitizensPanel.COLUMNS.size() and CitizensPanel.COLUMNS.has("Sick"));
    var rows_first:Array = panel._cells.map(func(r:Array) -> Node: return r[1]);
    # every column, ascending then descending, then jump around
    var clicks:Array[int] = [1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 0, 0, 4, 1, 5, 2, 3, 0, 1, 1, 1, 5, 4, 4];
    for col in clicks:
        panel._heads[col].pressed.emit();
        panel._refresh();
        _check_order(panel, col);
    _expect("the headings were never replaced", panel._heads == heads and heads.all(func(h:Button) -> bool: return is_instance_valid(h) and h.get_parent() == panel._grid));
    _expect("the rows were not replaced either", panel._cells.map(func(r:Array) -> Node: return r[1]).all(func(n:Node) -> bool: return rows_first.has(n)));
    # values that change while a sort is active
    panel._heads[4].pressed.emit();
    panel._refresh();
    for k in 6:
        var q:Pawn = world.pawns[k];
        q.mood = float((k * 7 + 3) % 10) / 10.0;
        panel._refresh();
        _check_order(panel, 4);
    # the grid holds the headings and one node per cell, in row order
    _expect("the grid has every cell once (%d)" % panel._grid.get_child_count(), panel._grid.get_child_count() == CitizensPanel.COLUMNS.size() * (world.pawns.size() + 1));
    for r in panel._cells.size():
        var row:Array = panel._cells[r];
        for c in 6:
            if panel._grid.get_child(CitizensPanel.COLUMNS.size() * (r + 1) + c) != row[1 + c]:
                _expect("row %d keeps its cells in the grid order" % r, false);
                break;
    # the Sick column and the marker
    var sick:Pawn = null;
    for p in world.pawns:
        if p.illness > 0.0:
            sick = p;
            break;
    for row in panel._cells:
        if row[0] == sick:
            _expect("the Sick column shows the case (%s)" % (row[6] as Label).text, (row[6] as Label).text == "%d%%" % roundi(sick.illness * 100.0));
        elif (row[0] as Pawn).illness <= 0.0:
            _expect("a well citizen shows a dash", (row[6] as Label).text == "-");
    sick._ill_mark.visible = false;
    GameClock.set_speed(1);
    sick._animate(0.1);
    _expect("a sick citizen has a marker", sick._ill_mark.visible);
    var well:Pawn = world.pawns[1];
    well.illness = 0.0;
    well._animate(0.1);
    _expect("a well one has none", not well._ill_mark.visible);
    # merchants can bring and want herbs
    _expect("herbs are on the merchants' lists", Traders.BRINGS.has(&"herbs") and Traders.WANTS.has(&"herbs"));
    var bringers:int = 0;
    var wanters:int = 0;
    for t in Traders.TYPES.values():
        bringers += 1 if (t["brings"] as Array).has(&"herbs") else 0;
        wanters += 1 if (t["wants"] as Array).has(&"herbs") else 0;
    _expect("some merchant types sell herbs (%d) and some ask for them (%d)" % [bringers, wanters], bringers >= 2 and wanters >= 2);
    print("CITIZENS_PANEL %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _check_order(panel:CitizensPanel, col:int) -> void:
    var keys:Array = panel._cells.map(func(r:Array) -> Variant: return panel._key(r[0]));
    var ok:bool = true;
    for i in range(1, keys.size()):
        if panel._sort_desc:
            ok = ok and keys[i - 1] >= keys[i];
        else:
            ok = ok and keys[i - 1] <= keys[i];
    _expect("column %d %s sorts (%s)" % [col, "down" if panel._sort_desc else "up", str(keys)], ok and panel._sort_col == col);

func _expect(what:String, ok:bool) -> void:
    if not ok:
        print("FAIL " + what);
        _fails += 1;
