# ----------------------------------------------------------------
# WindSway
#     Makes the swaying materials (shaders/sway.gdshader) and keeps them
#     in step: one clock and one wind strength for all of them, set from
#     WorldVisuals each frame. The shader needs the wind to move the
#     vertices, so the colour is set through set_color, not albedo_color.
# ----------------------------------------------------------------
class_name WindSway extends RefCounted;

static var _materials:Array[ShaderMaterial] = [];

# A swaying material: `color` is the albedo (times the vertex and instance colours), `sway` the metres it bends at
# `height_ref` (in the mesh's own units) in calm weather, `double_sided` for thin blades.
static func make(color:Color, sway:float, height_ref:float, double_sided:bool = false) -> ShaderMaterial:
    var m:ShaderMaterial = ShaderMaterial.new();
    m.shader = load("res://shaders/sway_double.gdshader" if double_sided else "res://shaders/sway.gdshader") as Shader;
    m.set_shader_parameter("albedo", color);
    m.set_shader_parameter("sway", sway);
    m.set_shader_parameter("height_ref", height_ref);
    _materials.append(m);
    return m;

static func set_color(m:ShaderMaterial, color:Color) -> void:
    m.set_shader_parameter("albedo", color);

# The clock (seconds of game-speed time) and the wind strength, for every material still in use.
static func update(clock:float, wind:float) -> void:
    var i:int = _materials.size() - 1;
    while i >= 0:
        var m:ShaderMaterial = _materials[i];
        if m.get_reference_count() <= 2:        # only this list and the local `m` hold it: its world is gone
            _materials.remove_at(i);
        else:
            m.set_shader_parameter("clock", clock);
            m.set_shader_parameter("wind", wind);
        i -= 1;

static func count() -> int:
    return _materials.size();
