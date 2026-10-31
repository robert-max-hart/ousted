# ----------------------------------------------------------------
# SaveGame
#     Writes the world to a file and loads it back by building a fresh
#     World from the saved data. A save is a compressed Variant
#     dictionary (see World.serialize) with a version number.
# ----------------------------------------------------------------
class_name SaveGame extends RefCounted;

const VERSION   :int = 2;
const MIN_VERSION:int = 2;        # version 1 saves are from the 128-cell map (the map is 160 now) and cannot be loaded
const DIR       :String = "user://saves";
const QUICKSAVE :String = "quicksave";
const AUTOSAVE  :String = "autosave";
const MAIN_SCENE:String = "res://scenes/main.tscn";

static var autosave_enabled:bool = true;
static var saves_written:int = 0;          # how many times a game was written this session (the tutorial watches it)

static func path_for(slot:String) -> String:
    return "%s/%s.sav" % [DIR, slot];

static func exists(slot:String) -> bool:
    return FileAccess.file_exists(path_for(slot));

# Returns "" on success, otherwise a reason.
static func write(world:World, slot:String) -> String:
    DirAccess.make_dir_recursive_absolute(DIR);
    var f:FileAccess = FileAccess.open_compressed(path_for(slot), FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD);
    if f == null:
        return "Couldn't write the save file (error %d)." % FileAccess.get_open_error();
    var data:Dictionary = world.serialize();
    data["version"] = VERSION;
    data["meta"] = {
        "name": slot,
        "date": GameClock.date_string(),
        "pawns": world.pawns.size(),
        "seed": world.world_seed,
        "saved_at": Time.get_unix_time_from_system(),
    };
    f.store_var(data);
    f.close();
    saves_written += 1;
    return "";

# Returns the saved data, or an empty dictionary (with the reason in `error`).
static func read(slot:String, error:Array) -> Dictionary:
    if not exists(slot):
        error.append("There is no saved game in slot '%s'." % slot);
        return {};
    var f:FileAccess = FileAccess.open_compressed(path_for(slot), FileAccess.READ, FileAccess.COMPRESSION_ZSTD);
    if f == null:
        error.append("Couldn't open the save file (error %d)." % FileAccess.get_open_error());
        return {};
    var data:Variant = f.get_var();
    f.close();
    if not (data is Dictionary) or not (data as Dictionary).has("version"):
        error.append("That file is not a valid save.");
        return {};
    if data["version"] > VERSION:
        error.append("That save is from a newer version of the game.");
        return {};
    if data["version"] < MIN_VERSION:
        error.append("That save was made on a smaller map and cannot be loaded.");
        return {};
    return data;

# A save that exists and can be loaded by this version (an old one from the smaller map cannot).
static func loadable(slot:String) -> bool:
    var error:Array = [];
    return not read(slot, error).is_empty();

# Slot names become file names, so keep letters, digits, spaces, dashes and underscores.
static func clean_name(text:String) -> String:
    var out:String = "";
    for ch in text.strip_edges():
        if ch == " " or ch == "-" or ch == "_" or (ch >= "0" and ch <= "9") or (ch.to_lower() != ch.to_upper()):
            out += ch;
    return out.substr(0, 32).strip_edges();

# Every save on disk, newest first: {slot, date, pawns, seed, saved_at, ok}. Old saves have no meta.
static func list_slots() -> Array:
    var rows:Array = [];
    var dir:DirAccess = DirAccess.open(DIR);
    if dir == null:
        return rows;
    for file in dir.get_files():
        if not file.ends_with(".sav"):
            continue;
        var slot:String = file.get_basename();
        var error:Array = [];
        var data:Dictionary = read(slot, error);
        var meta:Dictionary = data.get("meta", {}) as Dictionary;
        rows.append({
            "slot": slot,
            "ok": not data.is_empty(),
            "date": meta.get("date", ""),
            "pawns": meta.get("pawns", 0),
            "seed": meta.get("seed", 0),
            "saved_at": meta.get("saved_at", FileAccess.get_modified_time(path_for(slot))),
        });
    rows.sort_custom(func(a:Dictionary, b:Dictionary) -> bool: return a["saved_at"] > b["saved_at"]);
    return rows;

static func delete(slot:String) -> void:
    if exists(slot):
        DirAccess.remove_absolute(path_for(slot));

static func save(world:World, slot:String = QUICKSAVE) -> void:
    if world.awaiting_start:
        world.hud.toast("Choose where to settle first.");
        return;
    var err:String = write(world, slot);
    world.notify("Game saved." if err == "" else err);
    if world.hud != null:
        world.hud.toast("Game saved." if err == "" else err);

static func autosave(world:World) -> void:
    if autosave_enabled and not world.pawns.is_empty():
        write(world, AUTOSAVE);

# From the title screen: starts the main scene from a saved game. Returns "" or the reason it failed.
static func start_from_slot(tree:SceneTree, slot:String) -> String:
    var error:Array = [];
    var data:Dictionary = read(slot, error);
    if data.is_empty():
        return error[0];
    GameClock.restore_state(data["clock"]);
    Weather.restore_state(data["weather"]);
    World.pending_load = data;
    tree.change_scene_to_file(MAIN_SCENE);
    return "";

# Replaces the running world with the saved one. Done between frames so nothing is freed while one of
# its own callbacks (a button press) is still running.
static func load_slot(world:World, slot:String = QUICKSAVE) -> void:
    var error:Array = [];
    var data:Dictionary = read(slot, error);
    if data.is_empty():
        world.notify(error[0]);
        return;
    var tree:SceneTree = world.get_tree();
    var parent:Node = world.get_parent();
    var swap:Callable = func() -> void:
        if not is_instance_valid(world):
            return;
        parent.remove_child(world);
        world.queue_free();
        GameClock.restore_state(data["clock"]);
        Weather.restore_state(data["weather"]);
        World.pending_load = data;
        parent.add_child((load(MAIN_SCENE) as PackedScene).instantiate());
    tree.process_frame.connect(swap, CONNECT_ONE_SHOT);
