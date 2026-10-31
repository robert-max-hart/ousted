// A material that sways in the wind (see sway_common.gdshaderinc). Closed meshes: trees, bushes, trunks.
shader_type spatial;
render_mode cull_back;
#include "res://shaders/sway_common.gdshaderinc"

void vertex() {
	vec3 d = sway_offset(MODEL_MATRIX[3].xyz, max(VERTEX.y, 0.0));
	VERTEX += inverse(mat3(MODEL_MATRIX)) * d;       // the push is in world space; the vertex is in the mesh's own
}

void fragment() {
	ALBEDO = sway_colour(COLOR);
	ROUGHNESS = roughness_value;
}
