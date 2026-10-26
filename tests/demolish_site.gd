# ----------------------------------------------------------------
# Demolish a building under construction test
#     A crop field (and a house) is demolished while builders are on it,
#     with the field selected. Nothing may crash, leave a task behind or
#     leave the freed building selected (a freed object equals null, so
#     the old selection guard skipped itself and `is` then failed).
#     godot --headless --path . --fixed-fps 60 res://tests/demolish_site.tscn
# ----------------------------------------------------------------
extends Node;

var world:World;
var field:Building;
var house:Building;
var _frames:int = 0;
var _done:bool = false;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    Defs.difficulty = &"easy";
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    Engine.time_scale = 4.0;
    GameClock.set_speed(3);
    var th:Building = world.town_hall;
    field = _site(&"field", Vector2i(8, 8));
    house = _site(&"house", Vector2i(-10, 4));
    _expect("both sites were placed", field != null and house != null);

func _site(id:StringName, near:Vector2i) -> Building:
    var size:Vector2i = Defs.BUILDINGS[id]["size"];
    for r in range(0, 25):
        for dz in range(-r, r + 1):
            for dx in range(-r, r + 1):
                var o:Vector2i = world.town_hall.origin + near + Vector2i(dx, dz);
                if maxi(absi(dx), absi(dz)) == r and world.can_place(id, o, size) == "" and world._rect_free_of_nodes(Rect2i(o, size)):
                    return world.place_building(id, o, size);
    return null;

func _busy_on(b:Building) -> bool:
    for p in world.pawns:
        if p.task != null and is_same(p.task.target, b):
            return true;
    return false;

func _process(_delta:float) -> void:
    if _done:
        return;
    _frames += 1;
    if (field.work_done > 1.0 and _busy_on(field) and _busy_on(house)) or _frames > 3000:
        _done = true;
        _expect("builders were working on the field (%d frames)" % _frames, _busy_on(field));
        print("field progress %.0f%%, builders %d" % [field.progress() * 100.0, field.builders]);
        world.tools.select(field);
        var tools:PlayerTools = world.tools;
        tools.set_mode(PlayerTools.Mode.DEMOLISH);
        tools._dragging = true;
        tools._drag_start = field.origin - Vector2i(1, 1);
        tools._hover_cell = field.origin + field.size;
        tools._on_release();
        world.remove_building(house, true);
        _expect("the sites are gone", not world.buildings.has(field) and not world.buildings.has(house));
        _expect("the demolished field is no longer selected", world.tools.selected == null);
        world.tools.set_mode(PlayerTools.Mode.SELECT);
        _expect("nobody still has a task aimed at them", not world.pawns.any(func(p:Pawn) -> bool: return p.task != null and (is_same(p.task.target, field) or is_same(p.task.target, house))));
        # a selection freed behind the tools' back is dropped, not tripped over
        var stray:Node3D = Node3D.new();
        add_child(stray);
        world.tools.selected = stray;
        stray.free();
        get_tree().create_timer(3.0).timeout.connect(func() -> void:
            _expect("a stray freed selection was dropped", typeof(world.tools.selected) != TYPE_OBJECT);
            _expect("the game ran on", world.pawns.size() > 0);
            get_tree().quit());

func _expect(what:String, ok:bool) -> void:
    print(("PASS " if ok else "FAIL ") + what);
