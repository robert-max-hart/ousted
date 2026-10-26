# ----------------------------------------------------------------
# Policies
#     The colony-wide on/off rules (see Defs.POLICIES). Owned by
#     World, saved with the game, changed from the HUD.
# ----------------------------------------------------------------
class_name Policies extends RefCounted;

signal changed(id:StringName);

var _on:Dictionary = {};       # id -> bool, only the rules the player has changed

func is_on(id:StringName) -> bool:
    return _on.get(id, Defs.POLICIES[id]["default"]);

func set_on(id:StringName, on:bool) -> void:
    if is_on(id) == on:
        return;
    _on[id] = on;
    changed.emit(id);

func to_dict() -> Dictionary:
    return _on.duplicate();

# Rules saved by an older version are missing and keep their default; rules that no longer exist are dropped.
func restore(d:Dictionary) -> void:
    _on.clear();
    for id in d:
        if Defs.POLICIES.has(id):
            _on[id] = d[id];
