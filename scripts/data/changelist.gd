# ----------------------------------------------------------------
# Changelist
#     Reads data/changelist.txt: one section per push to main, newest
#     first. The newest section's version is the build id the title
#     screen shows, so the two never drift apart.
#
#     Version numbers are  0.M.N  (a pre-release game):
#       M = milestones completed (M1 to M3 done is 0.3), so it goes up when a milestone is finished;
#       N = pushes since M last went up (0 for the push that finished the milestone).
#     A section not pushed yet carries the next number with "-dev" on the end; drop the "-dev" when it is pushed.
# ----------------------------------------------------------------
class_name Changelist extends RefCounted;

const PATH:String = "res://data/changelist.txt";

# [{version, date, title, items}] in file order (newest first). A missing file gives [].
static func parse(path:String = PATH) -> Array:
    var out:Array = [];
    if not FileAccess.file_exists(path):
        return out;
    for raw in FileAccess.get_file_as_string(path).split("\n"):
        var line:String = raw.strip_edges();
        if line.begins_with("# ") and line.count("|") == 2:
            var parts:PackedStringArray = line.substr(2).split("|");
            out.append({"version": parts[0].strip_edges(), "date": parts[1].strip_edges(), "title": parts[2].strip_edges(), "items": []});
        elif line.begins_with("- ") and not out.is_empty():
            (out[out.size() - 1]["items"] as Array).append(line.substr(2));
    return out;

# The newest version ("0.4.0-dev"), or "0.0.0" without a changelist.
static func version(sections:Array = []) -> String:
    var list:Array = sections if not sections.is_empty() else parse();
    return list[0]["version"] if not list.is_empty() else "0.0.0";

# What the title screen shows in the corner.
static func build_id() -> String:
    return "Build " + version();
