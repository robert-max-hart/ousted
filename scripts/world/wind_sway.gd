# ----------------------------------------------------------------
# WindSway
#     Makes the swaying materials (shaders/sway.gdshader) and keeps them
#     in step: one clock and one wind strength for all of them, set from
#     WorldVisuals each frame. The shader needs the wind to move the
#     vertices, so the colour is set through set_color, not albedo_color.
# ----------------------------------------------------------------
class_name WindSway extends RefCounted;

static var _materials:Array[ShaderMaterial] = [];
static var enabled:bool = true;         # from Settings.sway: off leaves trees, bushes and hazel standing still
static var grass_enabled:bool = true;   # from Settings.grass_sway: the same for the grass tufts

# A swaying material: `color` is the albedo (times the vertex and instance colours), `sway` the metres it bends at
# `height_ref` (in the mesh's own units) in calm weather, `double_sided` for thin blades (the grass: its own setting).
static func make(color:Color, sway:float, height_ref:float, double_sided:bool = false) -> ShaderMaterial:
    var m:ShaderMaterial = ShaderMaterial.new();
    m.shader = load("res://shaders/sway_double.gdshader" if double_sided else "res://shaders/sway.gdshader") as Shader;
    m.set_shader_parameter("albedo", color);
    m.set_shader_parameter("sway", sway);
    m.set_shader_parameter("height_ref", height_ref);
    m.set_meta(&"grass", double_sided);       # grass has its own switch
    _materials.append(m);
    return m;

# Snow settles on this material's surfaces that face up (pine boughs, bushes) when the ground is snowy.
static func hold_snow(m:ShaderMaterial) -> void:
    m.set_shader_parameter("snow_hold", 1.0);

# Also give this shader material the shared clock (the animals' legs and heads use it).
static func track(m:ShaderMaterial) -> void:
    _materials.append(m);

static func set_color(m:ShaderMaterial, color:Color) -> void:
    m.set_shader_parameter("albedo", color);

# The clock (seconds of game-speed time), the wind strength and the snow cover, for every material still in use.
static func update(clock:float, wind:float, snow:float = 0.0) -> void:
    var i:int = _materials.size() - 1;
    while i >= 0:
        var m:ShaderMaterial = _materials[i];
        if m.get_reference_count() <= 2:        # only this list and the local `m` hold it: its world is gone
            _materials.remove_at(i);
        else:
            m.set_shader_parameter("clock", clock);
            m.set_shader_parameter("wind", wind);
            m.set_shader_parameter("snow", snow);
            m.set_shader_parameter("sway_on", 1.0 if (grass_enabled if m.get_meta(&"grass", false) else enabled) else 0.0);
        i -= 1;

static func count() -> int:
    return _materials.size();
