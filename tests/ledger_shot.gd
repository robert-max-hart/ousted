# ----------------------------------------------------------------
# Ledger screenshot
#     Made-up records, the Town Hall with Governance selected, and the
#     ledger panel on its graphs and then its history.
#     godot --path . res://tests/ledger_shot.tscn -- <out_dir>
# ----------------------------------------------------------------
extends Node;

var world:World;
var _frame:int = 0;
var _out:String = "user://";

func _ready() -> void:
    var args:PackedStringArray = OS.get_cmdline_user_args();
    if args.size() > 0:
        _out = args[0];
    SaveGame.autosave_enabled = false;
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    GameClock.set_speed(0);
    world.town_hall.upgrades_done[&"governance"] = true;
    var led:Ledger = world.ledger;
    for d in 70:
        led.samples.append({"day": d, "pop": 6 + d / 9, "babies": d / 20, "children": d / 14, "adults": 6, "food": maxi(0, 160 - d * 3 + (d / 12) * 120), "firewood": 30 + (d % 20),
            "mood": 62.0 + 8.0 * sin(d * 0.3), "births": 1 if d % 11 == 0 else 0, "deaths": 1 if d % 29 == 5 else 0});
    for t in ["Your settlers have arrived. Spring has begun.", "Wooden House completed.", "Alden and Hal are now a couple.", "A baby, Rowan, was born to Alden and Hal.", "Godric has died of old age."]:
        led.record_event(t);
    world.tools.select(world.town_hall);
    world.camera_rig.focus_on(world.town_hall.position);

func _process(_delta:float) -> void:
    _frame += 1;
    if _frame == 10:
        world.hud._ledger_panel.open();
    elif _frame == 40:
        _shot("ledger_01.png");
        world.hud._ledger_panel._graph_btns[3].pressed.emit();
    elif _frame == 50:
        world.hud._ledger_panel.get_child(0).get_child(1).current_tab = 1;
    elif _frame == 60:
        _shot("ledger_02.png");
        world.hud._ledger_panel.get_child(0).get_child(1).current_tab = 1;
        get_tree().quit();

func _shot(file:String) -> void:
    get_viewport().get_texture().get_image().save_png(_out.path_join(file));
    print("saved ", file);
