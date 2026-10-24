# ----------------------------------------------------------------
# Time budget test
#     Runs the soak scenario and reports, per profession, how the
#     waking hours split between working, walking and idling. Used to
#     judge how much a work-speed bonus really changes throughput.
#     godot --headless --path . --fixed-fps 60 res://tests/time_budget.tscn
# ----------------------------------------------------------------
extends "res://tests/sim_soak.gd";

const BUDGET_DAYS:int = 12;
var _frames:Dictionary = {};    # profession -> {"work": n, "walk": n, "other": n, "idle": n}

func _ready() -> void:
    super._ready();
    for p in world.pawns:
        p.energy = 1.0;

func _process(delta:float) -> void:
    for p in world.pawns:
        var row:Dictionary = _frames.get_or_add(p.profession_name(), {"work": 0, "walk": 0, "act": 0, "idle": 0, "needs": 0});
        if GameClock.is_night():
            continue;
        if p.task == null:
            row["idle"] += 1;
        elif p.task.kind == &"idle":
            row["idle"] += 1;
        elif p.task.kind in [&"drink", &"eat", &"warm", &"sleep"]:
            row["needs"] += 1;
        else:
            var s:Dictionary = p.task.current();
            match s.get("type", -1):
                Task.Step.WORK: row["work"] += 1;
                Task.Step.MOVE: row["walk"] += 1;
                _: row["act"] += 1;
    if GameClock.day_index() >= BUDGET_DAYS:
        for k in _frames:
            var r:Dictionary = _frames[k];
            var total:float = 0.0;
            for v in r.values():
                total += v;
            print("%-9s work %.0f%%  walk %.0f%%  act %.0f%%  needs %.0f%%  idle %.0f%%" % [k, 100.0 * r["work"] / total, 100.0 * r["walk"] / total, 100.0 * r["act"] / total, 100.0 * r["needs"] / total, 100.0 * r["idle"] / total]);
        get_tree().quit();
