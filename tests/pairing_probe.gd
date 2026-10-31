# ----------------------------------------------------------------
# Pairing probe
#     Loads a save slot and prints who is paired and who lives where,
#     then runs on a few days and prints it again.
#     godot --headless --path . --fixed-fps 60 res://tests/pairing_probe.tscn -- <slot> [days]
# ----------------------------------------------------------------
extends Node;

var world:World;
var _slot:String = "playtest2";       # one of the player's own saves, so the probe reads the real folder

var _days:int = 6;
var _start_day:int = 0;
var _last_day:int = -1;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    SaveGame.use_test_dir = false;
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0:
        _slot = args[0];
    if args.size() > 1:
        _days = args[1].to_int();
    var error:Array = [];
    var data:Dictionary = SaveGame.read(_slot, error);
    if data.is_empty():
        print("load failed: ", error);
        get_tree().quit();
        return;
    GameClock.restore_state(data["clock"]);
    Weather.restore_state(data["weather"]);
    World.pending_load = data;
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    Engine.time_scale = 4.0;
    GameClock.set_speed(3);
    _start_day = GameClock.day_index();

func _process(_delta:float) -> void:
    var d:int = GameClock.day_index();
    if d == _last_day:
        return;
    _last_day = d;
    if d == _start_day or d == _start_day + _days:
        _dump(d);
    if d >= _start_day + _days:
        get_tree().quit();

func _dump(d:int) -> void:
    print("==== day %d: %d citizens, %d buildings" % [d, world.pawns.size(), world.buildings.size()]);
    var houses:int = 0;
    for b in world.buildings:
        if b.def.has("beds"):
            houses += 1;
            print("  %s #%d %s residents: %s" % [b.def_id, houses, "done" if b.is_complete() else "SITE", ", ".join(PackedStringArray(b.residents.map(func(r:Pawn) -> String: return "%s(%d)" % [r.first_name, int(r.age)])))]);
    for p in world.pawns:
        var mate:String = p.partner.first_name if p.partner != null else "-";
        var kin:Array[String] = [];
        for q in world.pawns:
            if q != p and q.is_adult() and p.is_adult() and world.families.are_kin(p, q):
                kin.append(q.first_name);
        print("  %-9s age %2d %-5s partner %-9s home %s ready_in %.0fh mood %.2f kin %s" % [p.first_name, int(p.age), "adult" if p.is_adult() else "young", mate, "yes" if p.home != null else "NO", maxf(0.0, p.pair_ready_hour - GameClock.total_hours), p.mood, kin]);
