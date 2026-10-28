# ----------------------------------------------------------------
# Stone probe
#     For a number of map seeds, counts the loose rocks (and their
#     stone) and iron deposits near the start (within 15 and 30
#     cells of the Town Hall) and on the whole map.
#     godot --headless --path . --fixed-fps 60 res://tests/stone_probe.tscn -- <seeds>
# ----------------------------------------------------------------
extends Node;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    var args:PackedStringArray = OS.get_cmdline_user_args();
    var seeds:int = args[0].to_int() if args.size() > 0 else 12;
    var totals:Array[float] = [0, 0, 0, 0, 0, 0];
    print("seed   rocks<15 stone<15 | rocks<30 stone<30 | ore<30 | map rocks  map ore");
    for s in seeds:
        World.new_game_seed = 1000 + s;
        var world:World = (load("res://scenes/main.tscn") as PackedScene).instantiate();
        add_child(world);
        var th:Vector2i = world.town_hall.origin;
        var r15:int = 0; var st15:int = 0; var r30:int = 0; var st30:int = 0; var o30:int = 0; var mr:int = 0; var mo:int = 0;
        for rn in world.nodes:
            var d:float = Vector2(rn.cell - th).length();
            if rn.kind == &"rock":
                mr += 1;
                if d <= 15.0: r15 += 1; st15 += rn.amount;
                if d <= 30.0: r30 += 1; st30 += rn.amount;
            elif rn.kind == &"ore":
                mo += 1;
                if d <= 30.0: o30 += 1;
        var ring:int = 0;
        for rn in world.nodes:
            var dd:float = Vector2(rn.cell - th).length();
            if rn.kind == &"rock" and dd >= 10.0 and dd <= 22.0:
                ring += 1;
        print("ring 10-22: %d rocks" % ring);
        print("%-6d %8d %8d | %8d %8d | %6d | %9d %7d" % [1000 + s, r15, st15, r30, st30, o30, mr, mo]);
        totals[0] += st15; totals[1] += st30; totals[2] += o30; totals[3] += mr; totals[4] += mo;
        world.queue_free();
        await get_tree().process_frame;
    print("average stone within 15: %.1f, within 30: %.1f, ore within 30: %.1f, map rocks %.0f, map ore %.0f" % [totals[0] / seeds, totals[1] / seeds, totals[2] / seeds, totals[3] / seeds, totals[4] / seeds]);
    get_tree().quit();
