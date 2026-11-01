# ----------------------------------------------------------------
# Model sets
#     Every model of the full set has a twin in the reduced set (the
#     `_low` folders): a model added without running its generator with
#     `--low` made the game fail on the "Reduced" model detail setting.
#     godot --headless --path . --fixed-fps 60 res://tests/model_sets.tscn
# ----------------------------------------------------------------
extends Node;

const ROOT:String = "res://assets/models/";

func _ready() -> void:
    var fails:int = 0;
    var checked:int = 0;
    var dir:DirAccess = DirAccess.open(ROOT);
    for sub in dir.get_directories():
        if sub.ends_with("_low"):
            continue;
        var low:String = "%s%s_low/" % [ROOT, sub];
        if not DirAccess.dir_exists_absolute(low):
            continue;
        for f in DirAccess.get_files_at("%s%s/" % [ROOT, sub]):
            if not f.ends_with(".obj"):
                continue;
            checked += 1;
            if not ResourceLoader.exists(low + f):
                print("FAIL %s%s has no reduced twin (run its generator with --low, then import)" % [sub, "/" + f]);
                fails += 1;
    print("checked %d models" % checked);
    print("MODEL SETS %s" % ("PASS" if fails == 0 else "FAIL"));
    get_tree().quit(1 if fails > 0 else 0);
