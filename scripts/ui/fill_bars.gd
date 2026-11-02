# ----------------------------------------------------------------
# FillBars
#     Decides which stores show their fill bar: the one under the
#     cursor and the selected one, or every store while the top bar's
#     Stores toggle is on, and the progress bar over a building that is
#     being upgraded. Checked ten times a second.
# ----------------------------------------------------------------
class_name FillBars extends Node;

const CHECK_EVERY:float = 0.1;
const LIFT:float = 1.7;         # above the building's height

var show_all:bool = false;
var _acc:float = 0.0;

func _process(delta:float) -> void:
    _acc += delta;
    if _acc < CHECK_EVERY:
        return;
    _acc = 0.0;
    var w:World = World.instance;
    if w == null or w.tools == null:
        return;
    var near:Variant = w.tools._pick() if w.tools.hover_valid() else null;
    for b in w.buildings:
        var want:bool = b.is_storage() and (show_all or is_same(b, near) or is_same(b, w.tools.selected));
        update_for(b, want);
        update_progress(b);

# The bar over a building being upgraded or expanded (always shown, not only on hover): materials in amber, then work in blue.
func update_progress(b:Building) -> void:
    if b.upgrading == &"" or b.state != Building.State.COMPLETE:
        if b.progress_bar != null:
            b.progress_bar.visible = false;
        return;
    if b.progress_bar == null:
        b.progress_bar = FillBar.new();
        b.add_child(b.progress_bar);
    var bar:Dictionary = b.build_bar();
    b.progress_bar.position = Vector3(0, b.def.get("height", 2.0) + LIFT + (0.35 if b.fill_bar != null and b.fill_bar.visible else 0.0), 0);
    b.progress_bar.set_progress(bar["fill"], bar["working"]);
    b.progress_bar.visible = true;

# Makes or shows the building's bar with its current fill, or hides it.
func update_for(b:Building, want:bool) -> void:
    if not want:
        if b.fill_bar != null:
            b.fill_bar.visible = false;
        return;
    if b.fill_bar == null:
        b.fill_bar = FillBar.new();
        b.add_child(b.fill_bar);
    b.fill_bar.position = Vector3(0, b.def.get("height", 2.0) + LIFT, 0);
    b.fill_bar.set_fill(b.used(), b.capacity());
    b.fill_bar.visible = true;
