# ----------------------------------------------------------------
# ScenarioPanel
#     The goals of the scenario being played: a small panel at the top
#     centre with the story, each goal and how far along it is, and the
#     victory line once all are reached. Can be folded away. Attached to
#     the HUD when the world has a scenario.
# ----------------------------------------------------------------
class_name ScenarioPanel extends Node;

const REFRESH:float = 0.5;

var hud:HUD;
var world:World;
var run:ScenarioRun;
var _panel:PanelContainer;
var _body:VBoxContainer;
var _story:Label;
var _goals:VBoxContainer;
var _status:Label;
var _fold:Button;
var _t:float = 0.0;

static func attach(h:HUD, root:Control) -> ScenarioPanel:
    var p:ScenarioPanel = ScenarioPanel.new();
    p.name = "ScenarioPanel";
    p.hud = h;
    p.world = World.instance;
    p.run = p.world.scenario;
    h.add_child(p);
    p._build(root);
    p.refresh();
    return p;

func _build(root:Control) -> void:
    _panel = hud._panel(root, &"goals");
    _panel.anchor_left = 0.5;
    _panel.anchor_right = 0.5;
    _panel.offset_left = -190.0;
    _panel.offset_right = 190.0;
    _panel.offset_top = 76.0;
    _panel.grow_vertical = Control.GROW_DIRECTION_END;
    var col:VBoxContainer = VBoxContainer.new();
    col.add_theme_constant_override("separation", 4);
    _panel.add_child(col);
    var head:HBoxContainer = HBoxContainer.new();
    col.add_child(head);
    var title:Label = Label.new();
    title.text = run.data()["name"];
    title.add_theme_font_size_override("font_size", HUD.TITLE_FONT_SIZE);
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
    head.add_child(title);
    _fold = Button.new();
    _fold.text = "Hide";
    _fold.focus_mode = Control.FOCUS_NONE;
    _fold.pressed.connect(_on_fold);
    head.add_child(_fold);
    _body = VBoxContainer.new();
    _body.add_theme_constant_override("separation", 4);
    col.add_child(_body);
    _story = Label.new();
    _story.text = run.data()["story"];
    _story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;
    _story.custom_minimum_size.x = 360;
    _story.add_theme_color_override("font_color", Color(0.85, 0.8, 0.65));
    _body.add_child(_story);
    _goals = VBoxContainer.new();
    _body.add_child(_goals);
    _status = Label.new();
    _status.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5));
    _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;
    _body.add_child(_status);

func _on_fold() -> void:
    _body.visible = not _body.visible;
    _fold.text = "Hide" if _body.visible else "Goals";

func _process(delta:float) -> void:
    if run == null or not is_instance_valid(world):
        return;
    _t += delta;
    if _t >= REFRESH:
        _t = 0.0;
        refresh();

# Redraws the goal list with the current numbers.
func refresh() -> void:
    for c in _goals.get_children():
        c.queue_free();
    for i in run.goals().size():
        var p:Vector2i = run.progress(world, i);
        var done:bool = run.reached[i];
        var l:Label = Label.new();
        l.text = "%s %s%s" % ["[x]" if done else "[ ]", run.goal_text(i), "" if done else "  (%d / %d)" % [mini(p.x, p.y), p.y]];
        l.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5) if done else Color.WHITE);
        _goals.add_child(l);
    _status.text = "Victory! You may keep playing." if run.won else "Everyone is gone: the scenario is lost." if run.lost else "";
    _status.visible = _status.text != "";
    _story.visible = not run.won and not run.lost;
