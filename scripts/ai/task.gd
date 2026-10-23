# ----------------------------------------------------------------
# Task
#     A short script of steps a pawn runs in order:
#       MOVE  - walk to a cell, or next to/inside a rect
#       WORK  - tick(pawn, game_hours) -> bool done, called every frame
#       ACT   - fn(pawn) -> bool success, called once
#     on_cancel runs if the task ends early; on_end always runs.
# ----------------------------------------------------------------
class_name Task extends RefCounted;

enum Step { MOVE, WORK, ACT };

var kind            :StringName;
var label           :String;
var interruptible   :bool = true;
var target          :Variant = null;     # what to avoid retrying if it fails
var workplace       :Variant = null;     # job building this task serves; ends if it is demolished
var steps           :Array[Dictionary] = [];
var index           :int = 0;
var on_cancel       :Callable;
var on_end          :Callable;

func _init(k:StringName, l:String, can_interrupt:bool = true) -> void:
    kind = k;
    label = l;
    interruptible = can_interrupt;

func move_cell(c:Vector2i, status:String = "") -> Task:
    steps.append({"type": Step.MOVE, "cell": c, "status": status if status != "" else label});
    return self;

# Walk next to rect, or into it when inside_ok (walkable buildings, fields).
func move_rect(r:Rect2i, inside_ok:bool = false, status:String = "") -> Task:
    steps.append({"type": Step.MOVE, "rect": r, "inside": inside_ok, "status": status if status != "" else label});
    return self;

func work(tick:Callable, status:String = "") -> Task:
    steps.append({"type": Step.WORK, "tick": tick, "status": status if status != "" else label});
    return self;

# Convenience: work for a fixed number of game hours, then call done(pawn).
func work_for(hours:float, status:String = "", done:Callable = Callable()) -> Task:
    var state:Dictionary = {"t": 0.0};
    var tick:Callable = func(p:Pawn, dh:float) -> bool:
        state["t"] += dh;
        if state["t"] < hours:
            return false;
        if done.is_valid():
            done.call(p);
        return true;
    return work(tick, status);

func act(fn:Callable) -> Task:
    steps.append({"type": Step.ACT, "fn": fn, "status": label});
    return self;

func current() -> Dictionary:
    return steps[index] if index < steps.size() else {};

func finish(p:Pawn, success:bool) -> void:
    if not success and on_cancel.is_valid():
        on_cancel.call(p);
    if on_end.is_valid():
        on_end.call(p);
