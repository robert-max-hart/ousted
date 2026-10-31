# ----------------------------------------------------------------
# Save slots test
#     Named slots: names are cleaned, saves are listed newest first with
#     their info, the panel saves into a typed name and deletes a slot.
#     godot --headless --path . --fixed-fps 60 res://tests/save_slots.tscn
# ----------------------------------------------------------------
extends Node;

var _fails:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    await get_tree().process_frame;
    _expect("tests use their own saves folder", SaveGame.path_for("x").begins_with(SaveGame.TEST_DIR));
    SaveGame.delete("slot test a");
    SaveGame.delete("slot test b");
    _expect("names are cleaned", SaveGame.clean_name("  a/b*c d.. ") == "abc d");
    _expect("an empty name stays empty", SaveGame.clean_name("///") == "");
    SaveGame.write(world, "slot test a");
    SaveGame.write(world, "slot test b");
    var found:Array = SaveGame.list_slots().filter(func(r:Dictionary) -> bool: return String(r["slot"]).begins_with("slot test"));
    _expect("both slots are listed", found.size() == 2);
    _expect("the slots are loadable and carry info", found.all(func(r:Dictionary) -> bool: return r["ok"] and r["date"] != "" and r["pawns"] == world.pawns.size()));
    var panel:SavePanel = SavePanel.new(true);
    world.hud.add_child(panel);
    var got:Array = [];
    panel.save_chosen.connect(func(s:String) -> void: got.append(s));
    panel._name.text = "slot test b";
    panel._on_action();
    _expect("saving over an existing name asks first, and saves nothing yet", got.is_empty() and panel._action.text == "Overwrite" and panel._status.text.contains("already exists"));
    panel._name.text = "slot test b";       # (a changed name would cancel the question; the same one keeps it)
    panel._on_action();
    _expect("a second press overwrites: the panel reports the name", got == ["slot test b"] and panel._action.text == "Save");
    got.clear();
    panel._name.text = "slot test fresh";
    panel._on_action();
    _expect("a new name saves at once", got == ["slot test fresh"]);
    panel._name.text = "slot test b";
    panel._on_action();
    panel._name.text = "something else";
    panel._name.text_changed.emit("something else");
    _expect("changing the name cancels the question", panel._confirming == "" and panel._action.text == "Save");
    panel._select("slot test a");
    panel._on_delete();
    _expect("delete removes the slot", not SaveGame.exists("slot test a"));
    SaveGame.delete("slot test b");
    panel.queue_free();
    print("SAVE SLOTS %s" % ("PASS" if _fails == 0 else "FAIL"));
    get_tree().quit(1 if _fails > 0 else 0);

func _expect(what:String, ok:bool) -> void:
    print("%s: %s" % ["PASS" if ok else "FAIL", what]);
    if not ok:
        _fails += 1;
