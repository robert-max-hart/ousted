// A material that sways in the wind (see sway_common.gdshaderinc). Closed meshes: trees, bushes, trunks.
shader_type spatial;
render_mode cull_back;
#include "res://shaders/sway_common.gdshaderinc"

void vertex() {
	if (sway_on > 0.5) {       // off in the settings: the mesh stands still and costs nothing here
		vec3 d = sway_offset(MODEL_MATRIX[3].xyz, max(VERTEX.y, 0.0));
		VERTEX += inverse(mat3(MODEL_MATRIX)) * d;       // the push is in world space; the vertex is in the mesh's own
	}
}

void fragment() {
	fade_out(VERTEX, FRAGCOORD.xy);
	float up = smoothstep(0.3, 0.85, (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y);       // snow lies on what faces up
	ALBEDO = mix(sway_colour(COLOR), snow_color, snow * snow_hold * up);
	ROUGHNESS = roughness_value;
}
