# ----------------------------------------------------------------
# FillBar
#     A small bar that floats over a store (a billboard, not part of the
#     building's model) showing how full it is: green, yellow from 70%
#     and red from 90%, filling from the left. One quad and a small
#     shader. FillBars (scripts/ui/fill_bars.gd) decides which stores
#     show one.
# ----------------------------------------------------------------
class_name FillBar extends Node3D;

const WIDTH :float = 1.7;
const HEIGHT:float = 0.24;

const SHADER:String = """
shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled;
uniform float fill = 0.5;
uniform vec3 tint = vec3(0.4, 0.8, 0.35);
void vertex() {
    MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
    vec2 edge = min(UV, 1.0 - UV);
    float rim = step(min(edge.x * 7.0, edge.y), 0.07);
    vec3 inner = mix(vec3(0.1, 0.1, 0.12), tint, step(UV.x, fill));
    ALBEDO = mix(inner, vec3(0.03, 0.03, 0.04), rim);
    ALPHA = 0.92;
}
""";

var _mat:ShaderMaterial;

func _init() -> void:
    visible = false;
    var mi:MeshInstance3D = MeshInstance3D.new();
    var q:QuadMesh = QuadMesh.new();
    q.size = Vector2(WIDTH, HEIGHT);
    mi.mesh = q;
    var sh:Shader = Shader.new();
    sh.code = SHADER;
    _mat = ShaderMaterial.new();
    _mat.shader = sh;
    _mat.render_priority = 2;
    mi.material_override = _mat;
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
    add_child(mi);

# Shows `used` of `capacity`.
func set_fill(used:int, capacity:int) -> void:
    var f:float = clampf(float(used) / float(maxi(capacity, 1)), 0.0, 1.0);
    _mat.set_shader_parameter("fill", f);
    _mat.set_shader_parameter("tint", color_for(f));

static func color_for(f:float) -> Color:
    if f >= 0.9:
        return Color(0.9, 0.3, 0.25);
    if f >= 0.7:
        return Color(0.95, 0.8, 0.3);
    return Color(0.4, 0.8, 0.35);
