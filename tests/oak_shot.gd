# ----------------------------------------------------------------
# Oak seasons screenshot
#     Looks at the forest through the year: one picture per season
#     point, saved to <out_dir>. Checks oaks exist and the leaves
#     are gone in winter.
#     godot --path . res://tests/oak_shot.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

const POINTS:Array[float] = [0.3, 1.5, 2.5, 3.5];

var world:World;
var _out:String = "user://";
var _frame:int = 0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0:
        _out = args[0];
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    var oaks:Array = world.nodes.filter(func(n:ResourceNode) -> bool: return n.kind == &"oak");
    var pines:Array = world.nodes.filter(func(n:ResourceNode) -> bool: return n.kind == &"tree");
    print("oaks %d, pines %d" % [oaks.size(), pines.size()]);
    _expect("oaks and pines both grow", oaks.size() > 50 and pines.size() > 50);
    var o:ResourceNode = oaks[oaks.size() / 2];
    world.camera_rig.focus_on(Vector3(o.cell.x, 0, o.cell.y));

func _process(_delta:float) -> void:
    _frame += 1;
    var step:int = _frame / 10;
    if _frame % 10 == 1 and step < POINTS.size():
        GameClock.total_hours = POINTS[step] * GameClock.HOURS_PER_DAY * GameClock.DAYS_PER_SEASON + 12.0;
        world.renderer.update_foliage();
        world.renderer.mark_dirty();
    if _frame % 10 == 8 and step < POINTS.size():
        get_viewport().get_texture().get_image().save_png(_out.path_join("oak_%d.png" % step));
        if step == 3:
            _expect("leaves are gone in winter", not world.renderer._oak_leaves.visible);
    if step >= POINTS.size():
        get_tree().quit();

func _expect(what:String, ok:bool) -> void:
    print(("PASS " if ok else "FAIL ") + what);
