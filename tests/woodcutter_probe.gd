# ----------------------------------------------------------------
# Woodcutter probe (not pass/fail): loads the test-saves slot
# "probe_rowan" (copy a save there first) and reports every woodcutter
# hut: its settings, how many trees and saplings stand in its circle,
# how many cells are free to plant, and then which tasks its woodcutters
# take over a stretch of game time.
#     godot --headless --path . --fixed-fps 60 res://tests/woodcutter_probe.tscn -- <hours>
# ----------------------------------------------------------------
extends Node;

var world:World;
var _hours:float = 24.0;
var _start:float = 0.0;
var _ready_done:bool = false;
var _kinds:Dictionary = {};

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0:
        _hours = float(args[0]);
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
        print("DATE ", GameClock.date_string(), " ", GameClock.time_string(), " season ", GameClock.season(), " dormant ", Climate.is_dormant(), " climate ", Climate.current);
        for b in world.buildings:
            if b.def.get("profession", "") == "WOODCUTTER":
                _report(b);
        GameClock.set_speed(1);
        Engine.time_scale = 4.0;
        _start = GameClock.total_hours;
    for p in world.pawns:
        if p.profession == JobManager.Profession.WOODCUTTER and p.task != null:
            var k:String = "%s: %s" % [p.first_name, p.task.kind];
            _kinds[k] = _kinds.get(k, 0) + 1;
    if GameClock.total_hours - _start > _hours:
        print("TASK FRAMES (woodcutters) ", _kinds);
        get_tree().quit();

func _report(b:Building) -> void:
    var trees:int = 0;
    var mature:int = 0;
    var saplings:int = 0;
    for rn in world.nodes:
        if rn.is_tree() and b.center_cell().distance_to(Vector2(rn.cell) + Vector2(0.5, 0.5)) <= b.radius():
            trees += 1;
            if rn.is_mature():
                mature += 1;
    for rn in world.saplings:
        if b.center_cell().distance_to(Vector2(rn.cell) + Vector2(0.5, 0.5)) <= b.radius():
            saplings += 1;
    var free:int = 0;
    var cells:int = 0;
    var why:Dictionary = {};
    var r:int = ceili(b.radius());
    var center:Vector2i = Vector2i(b.center_cell());
    for dz in range(-r, r + 1):
        for dx in range(-r, r + 1):
            var c:Vector2i = center + Vector2i(dx, dz);
            if b.center_cell().distance_to(Vector2(c) + Vector2(0.5, 0.5)) > b.radius():
                continue;
            cells += 1;
            if world.can_plant_tree(c, ProductionTasks.PLANT_SPACING):
                free += 1;
    print("WOODCUTTER ", b.display_name(), b.origin, " settings=", b.settings, " radius=", b.radius(), " cells=", cells, " free_to_plant=", free, " trees=", trees, " mature=", mature, " saplings=", saplings, " world.saplings=", world.saplings.size(), " planting=", world.planting.size(), " stored=", b.stored, " inputs=", b.inputs);
    var crew:Array = [];
    for p in world.pawns:
        if p.profession == JobManager.Profession.WOODCUTTER:
            crew.append("%s(%s)" % [p.first_name, p.task.kind if p.task else "-"]);
    print("  woodcutters: ", crew, " target ", world.jobs.target(JobManager.Profession.WOODCUTTER));
