# ----------------------------------------------------------------
# Rowan probe (not pass/fail): loads a save from the test saves folder
# (slot "probe_rowan": copy a save to user://test_saves/probe_rowan.sav first, never read a live one) and logs one
# citizen's tasks, carry and needs as the game runs on.
#     godot --headless --path . --fixed-fps 60 res://tests/rowan_probe.tscn -- <first name> <hours>
# ----------------------------------------------------------------
extends Node;

var world:World;
var _name:String = "Rowan";
var _hours:float = 12.0;
var _p:Pawn;
var _start:float = 0.0;
var _last:String = "";
var _ready_done:bool = false;
var _q:int = -1;
var _tasks:Dictionary = {};

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0:
        _name = args[0];
    if args.size() > 1:
        _hours = float(args[1]);
    var error:Array = [];
    var data:Dictionary = SaveGame.read("probe_rowan", error);
    if data.is_empty():
        print("READ FAILED ", error);
        get_tree().quit();
        return;
    GameClock.restore_state(data["clock"]);
    Weather.restore_state(data["weather"]);
    World.pending_load = data;
    world = (load(SaveGame.MAIN_SCENE) as PackedScene).instantiate();
    add_child(world);

func _process(_d:float) -> void:
    if LoadingScreen.active or world.pawns.is_empty():
        return;
    if not _ready_done:
        _ready_done = true;
        for q in world.pawns:
            if q.first_name == _name:
                _p = q;
        if _p == null:
            print("NO SUCH CITIZEN; have: ", world.pawns.map(func(q:Pawn) -> String: return q.first_name));
            get_tree().quit();
            return;
        _start = GameClock.total_hours;
        GameClock.set_speed(1);
        Engine.time_scale = 4.0;
        for b in world.buildings:
            if b.is_storage():
                print("STORE ", b.display_name(), b.origin, " stored=", b.stored, " cap=", b.capacity() if b.has_method("capacity") else "?");
        print("STOCK wood=", Stock.amount(&"wood"), " room_for_wood=", Stock.has_room_for(&"wood"));
        print("START hour %.1f  %s" % [GameClock.total_hours, _desc()]);
    if _p.task != null:
        _tasks[_p.task.get_instance_id()] = true;
    var key:String = "%s|%s|%s|%d|%s|%s" % [_p.task.kind if _p.task else "-", _p.task.label if _p.task else "", _p.carry_item, _p.carry_amount, _p.indoors, _p.sleeping];
    if key != _last:
        _last = key;
        print("h%.2f  %s" % [GameClock.total_hours - _start, _desc()]);
    if _p.task != null and _p.task.kind == &"deliver" and int((GameClock.total_hours - _start) * 4.0) != _q:
        _q = int((GameClock.total_hours - _start) * 4.0);
        var sp:Building = _p.task.target as Building if _p.task.target is Building else null;
        if sp != null:
            print("  STORE ", sp.display_name(), " cap=", sp.capacity(), " used=", sp.used(), " in_res=", sp.in_reserved, " free=", sp.free_space(), " accepts=", sp.accepts(_p.carry_item), " stored=", sp.stored, " forbidden=", sp.forbidden);
        print("  tasks seen so far: ", _tasks.size());
        print("  .. h%.2f deliver at %s step=%s idx=%d n=%d keys=%s status=%s pos=%s" % [GameClock.total_hours - _start, _p.cell(), _p.task.current().get("type", "?"), _p.task.index, _p.task.steps.size(), _p.task.current().keys(), _p.status, _p.position]);
    if GameClock.total_hours - _start > _hours:
        get_tree().quit();

func _desc() -> String:
    var t:Task = _p.task;
    var step:String = "";
    var tgt:String = "";
    if t != null:
        var cur:Dictionary = t.current();
        step = str(cur.get("type", "")) if cur != null else "";
        tgt = (str(t.target.display_name()) + "@" + str(t.target.origin)) if t.target is Building and World.alive(t.target) else (t.target.get_class() if t.target != null else "");
    return "%s task=%s '%s' tgt=%s carry=%s x%d prof=%d energy=%.2f hunger=%.2f in=%s sl=%s hour=%.1f" % [_p.first_name, t.kind if t else "-", t.label if t else "", tgt, _p.carry_item, _p.carry_amount, _p.profession, _p.energy, _p.hunger, _p.indoors, _p.sleeping, fposmod(GameClock.total_hours, 24.0)];
