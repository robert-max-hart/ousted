# ----------------------------------------------------------------
# Tutorial
#     A guide panel for a first game. It shows one step at a time (what
#     to do and why) and moves on by itself when the game shows the
#     player did it (a house exists, the speed changed, a game was
#     saved...). Text-only steps have a Next button; any step can be
#     skipped and the whole tutorial ended. The title screen's Tutorial
#     button sets up a mild, forgiving game and turns `active` on; the
#     HUD then attaches this to itself. Progress is not saved.
# ----------------------------------------------------------------
class_name Tutorial extends Node;

static var active:bool = false;        # set by the title screen for the next game, taken by the HUD

const DONE_PAUSE:float = 1.2;          # seconds a finished step stays up with its tick
const POLL      :float = 0.4;

# id: what the checks and baselines in _done and _enter know it by. manual: a Next button instead of a check.
const STEPS:Array[Dictionary] = [
    {"id": &"welcome", "manual": true, "title": "Welcome to Ousted",
     "text": "You lead a small band of settlers in the cold north. Keep them fed, warm and housed through the winter, and grow the colony. This tutorial walks through the basics on a mild map. It never stops the game: take your time, and press End tutorial when you have had enough."},
    {"id": &"look", "manual": false, "title": "Look around",
     "text": "Move the camera with W A S D or the arrow keys (hold Shift to go faster). Q and E turn it, the mouse wheel zooms, and dragging with the right mouse button pans. Try it now."},
    {"id": &"settle", "manual": false, "title": "Choose where to settle",
     "text": "Pick the spot for your Town Hall. Level ground near water and some forest does best: the note by the cursor rates the spot. Click to place it (R turns it)."},
    {"id": &"hall", "manual": false, "title": "Your Town Hall",
     "text": "The Town Hall is a well and your first store room. Click it to open its inspector on the right: it shows what is stored and the upgrades you can build."},
    {"id": &"time", "manual": false, "title": "Time",
     "text": "A day lasts three real minutes at normal speed. Change the speed with the buttons at the top right, or the keys 1 to 4 (space pauses). Try a different speed; you can pause any time to plan."},
    {"id": &"wood", "manual": false, "title": "Wood",
     "text": "Almost everything starts with wood. Choose the Harvest tool in the bottom bar and drag over some trees to mark them. Laborers will come and chop them."},
    {"id": &"house", "manual": false, "title": "A home",
     "text": "Settlers without a home sleep out in the cold. Open Housing in the bottom bar, pick House and click to place it. A green ghost fits, orange means you lack the materials for now, red cannot be built there."},
    {"id": &"built", "manual": false, "title": "Watch it go up",
     "text": "Builders carry the materials to the site and then build. The red mark over a site names what it is short of. Speed the game up while you wait, and select the site to see its progress."},
    {"id": &"road", "manual": false, "title": "Roads",
     "text": "Roads make everyone walk faster. Open Civic, pick Road and drag from your house to the Town Hall. Roads cost work, not materials, and trees in the way are marked for clearing first."},
    {"id": &"field", "manual": false, "title": "Food: a field",
     "text": "Open Food and pick Field, then drag out a plot at least 2 by 2 on level ground near water. Select it afterwards to choose its crop. Crops grow only when it is warm enough, and frost kills them, so watch the weather at the top."},
    {"id": &"overlay", "manual": false, "title": "Soil, water and slope",
     "text": "The Soil, Water and Slope buttons in the top bar colour the ground. Soil shows how fertile it is (green is rich), Water how close water is, and Slope where building is easy. Switch one on to see."},
    {"id": &"jobs", "manual": false, "title": "Jobs",
     "text": "Open Jobs in the top bar. Each profession has a target you set with + and -: give your farm a second Farmer. Citizens without a profession are laborers: they haul, build, chop and clear."},
    {"id": &"woodcutter", "manual": false, "title": "Firewood for winter",
     "text": "Houses burn firewood when it is cold. Open Industry and build a Woodcutter near the trees: it chops, plants and splits wood into firewood for the houses. Winter comes at the end of the year, and a cold house costs health."},
    {"id": &"save", "manual": false, "title": "Save your game",
     "text": "Press Esc to open the menu and choose Save game..., or press F5 to quicksave. The game also saves itself at every change of season."},
    {"id": &"finish", "manual": true, "title": "You are on your own",
     "text": "That is the basics. From here: Foragers and fishing huts bring in food besides crops, a School lets children learn, the Trading Post brings merchants with seeds and animals, and the Log and the inspectors explain what is going wrong. Good luck, and keep a store of food and firewood before winter."},
];

var hud:HUD;
var world:World;
var index:int = -1;
var _panel:PanelContainer;
var _count:Label;
var _title:Label;
var _body:Label;
var _status:Label;
var _next:Button;
var _skip:Button;
var _base:Dictionary = {};
var _done_for:float = -1.0;        # seconds the finished step has been showing, -1 while it is still being done
var _poll:float = 0.0;
var finished:bool = false;

static func attach(h:HUD, root:Control) -> Tutorial:
    var t:Tutorial = Tutorial.new();
    t.name = "Tutorial";
    t.hud = h;
    t.world = World.instance;
    h.add_child(t);
    t._build(root);
    t._go(0);
    return t;

# --------------------------------
func _build(root:Control) -> void:
    _panel = hud._panel(root, &"tutorial");
    _panel.anchor_left = 0.5;       # top centre, below the merchant banner
    _panel.anchor_right = 0.5;
    _panel.offset_left = -210.0;
    _panel.offset_right = 210.0;
    _panel.offset_top = 76.0;
    _panel.grow_vertical = Control.GROW_DIRECTION_END;
    var col:VBoxContainer = VBoxContainer.new();
    col.add_theme_constant_override("separation", 6);
    _panel.add_child(col);
    _count = Label.new();
    _count.add_theme_color_override("font_color", Color(0.9, 0.8, 0.45));
    col.add_child(_count);
    _title = Label.new();
    _title.add_theme_font_size_override("font_size", HUD.TITLE_FONT_SIZE);
    col.add_child(_title);
    _body = Label.new();
    _body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;
    _body.custom_minimum_size.x = 380;
    col.add_child(_body);
    _status = Label.new();
    _status.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5));
    col.add_child(_status);
    var row:HBoxContainer = HBoxContainer.new();
    row.add_theme_constant_override("separation", 6);
    col.add_child(row);
    _next = _button(row, "Next", func() -> void: _go(index + 1));
    _skip = _button(row, "Skip step", func() -> void: _go(index + 1));
    _button(row, "End tutorial", end);

func _button(row:Container, text:String, call:Callable) -> Button:
    var b:Button = Button.new();
    b.text = text;
    b.focus_mode = Control.FOCUS_NONE;
    b.pressed.connect(call);
    row.add_child(b);
    return b;

# --------------------------------
func _go(i:int) -> void:
    if i >= STEPS.size():
        end();
        return;
    index = i;
    _done_for = -1.0;
    var step:Dictionary = STEPS[i];
    _count.text = "Tutorial: step %d of %d" % [i + 1, STEPS.size()];
    _title.text = step["title"];
    _body.text = step["text"];
    _status.text = "";
    var manual:bool = step["manual"];
    _next.visible = manual;
    _next.text = "Finish" if i == STEPS.size() - 1 else "Next";
    _skip.visible = not manual;
    _enter(step["id"]);

# What a step compares against: the state when it begins.
func _enter(id:StringName) -> void:
    _base = {};
    match id:
        &"look":
            _base = {"pos": hud.world_camera().position, "zoom": hud.world_camera()._target_distance, "yaw": hud.world_camera()._yaw};
        &"time":
            _base = {"speed": GameClock.speed_index};
        &"wood":
            _base = {"marked": _marked_nodes()};
        &"save":
            _base = {"saves": SaveGame.saves_written};

func end() -> void:
    if finished:
        return;
    finished = true;
    if hud != null and is_instance_valid(_panel):
        hud.toast("Tutorial finished.");
        _panel.queue_free();
    queue_free();

# --------------------------------
func _process(delta:float) -> void:
    if finished or not is_instance_valid(world):
        return;
    if _done_for >= 0.0:
        _done_for += delta;
        if _done_for >= DONE_PAUSE:
            _go(index + 1);
        return;
    _poll += delta;
    if _poll < POLL:
        return;
    _poll = 0.0;
    var step:Dictionary = STEPS[index];
    if not step["manual"] and done(step["id"]):
        _done_for = 0.0;
        _status.text = "Done!";

# Whether the player has done what the step asks.
func done(id:StringName) -> bool:
    match id:
        &"look":
            var cam:RTSCamera = hud.world_camera();
            return cam.position.distance_to(_base["pos"]) > 8.0 or absf(cam._target_distance - _base["zoom"]) > 6.0 or absf(angle_difference(cam._yaw, _base["yaw"])) > 0.3;
        &"settle":
            return not world.awaiting_start;
        &"hall":
            return world.town_hall != null and world.tools.selected == world.town_hall;
        &"time":
            return GameClock.speed_index != _base["speed"];
        &"wood":
            return _marked_nodes() > _base["marked"];
        &"house":
            return _has_building(&"house", false);
        &"built":
            return _has_building(&"house", true);
        &"road":
            return not world.road_work.is_empty() or not world.pending_roads.is_empty();
        &"field":
            return _has_building(&"field", false);
        &"overlay":
            return world.terrain.soil_view or world.terrain.water_view or world.terrain.slope_view;
        &"jobs":
            return int(world.jobs.targets.get(JobManager.Profession.FARMER, 0)) >= 2;
        &"woodcutter":
            return _has_building(&"woodcutter", false);
        &"save":
            return SaveGame.saves_written > _base["saves"];
    return false;

func _has_building(def_id:StringName, finished_only:bool) -> bool:
    for b in world.buildings:
        if b.def_id == def_id and (not finished_only or b.is_complete()):
            return true;
    return false;

func _marked_nodes() -> int:
    var n:int = 0;
    for rn in world.nodes:
        if rn.designated:
            n += 1;
    return n;
