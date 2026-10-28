# ----------------------------------------------------------------
# Sowing windows probe
#     Prints, for each crop, on which days of the (32-day) year it
#     can be sown with the default climate. # = yes, . = no.
#     godot --headless --path . --fixed-fps 60 res://tests/sow_windows.tscn
# ----------------------------------------------------------------
extends Node;

func _ready() -> void:
    Weather._day_offset = 0.0;
    var header:String = "";
    for d in 32:
        header += "SUAW"[d * 4 / 32];
    print("day        " + header);
    for id in Defs.CROPS:
        var row:String = "";
        for d in 32:
            GameClock.total_hours = d * GameClock.HOURS_PER_DAY + 12.0;
            row += "#" if Weather.can_sow(Defs.CROPS[id]) else ".";
        print("%-10s %s" % [Defs.CROPS[id]["name"], row]);
    get_tree().quit();
