# ----------------------------------------------------------------
# Save/load round-trip test
#     Runs the soak scenario for a few days, saves, loads the save into a
#     fresh World, checks that the new world serializes to the same data,
#     then runs on for a couple of days to check it still works.
#     godot --headless --path . --fixed-fps 60 res://tests/save_load.tscn
# ----------------------------------------------------------------
extends "res://tests/sim_soak.gd";

const SAVE_DAY:int = 5;
const SAVE_HOUR:int = 14;         # mid-afternoon, so citizens are out working when it is saved
const END_DAY:int = 8;
const SLOT:String = "test_roundtrip";

var _before:Dictionary = {};
var _loaded:bool = false;
var _checked:bool = false;
var _reported:bool = false;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    super._ready();

func _process(delta:float) -> void:
    var d:int = GameClock.day_index();
    if not _loaded and GameClock.total_hours >= SAVE_DAY * 24 + SAVE_HOUR:
        _loaded = true;
        _before = world.serialize();
        print("SAVE: ", SaveGame.write(world, SLOT), " pawns ", world.pawns.size(), " nodes ", world.nodes.size(), " buildings ", world.buildings.size(), " piles ", world.piles.size());
        SaveGame.load_slot(world, SLOT);
        return;
    if _loaded and not _checked and World.instance != world and is_instance_valid(World.instance) and World.instance.is_inside_tree():
        _checked = true;
        world = World.instance;
        _compare(_before, world.serialize());
        _last_day = -1;
    if _checked:
        super._process(delta);
        if d >= END_DAY and not _reported:
            _reported = true;
            print("SAVE_LOAD: continued to day ", d, " ok, pawns ", world.pawns.size());

# Prints every top-level section that differs (citizens' positions are expected to move: they are put on
# a walkable cell, and the clock keeps running for a frame or two).
func _compare(a:Dictionary, b:Dictionary) -> void:
    var bad:int = 0;
    for key in a:
        if key in ["summary", "camera", "clock", "rng_state", "weather"]:
            continue;
        var same:bool;
        if key == "pawns":
            same = _pawns_equal(a[key], b[key]);
        else:
            same = hash(a[key]) == hash(b[key]) and a[key] == b[key];
        if not same:
            bad += 1;
            print("SAVE_LOAD MISMATCH in '", key, "'");
    print("SAVE_LOAD: round trip ", "identical" if bad == 0 else "DIFFERS in %d sections" % bad);

func _pawns_equal(a:Array, b:Array) -> bool:
    if a.size() != b.size():
        return false;
    for i in a.size():
        for k in a[i]:
            if k == "position":
                continue;
            if a[i][k] != b[i][k]:
                print("  pawn ", i, " field ", k, ": ", a[i][k], " vs ", b[i][k]);
                return false;
    return true;
