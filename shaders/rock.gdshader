// ----------------------------------------------------------------
// Rock
//     Rocks and ore outcrops (assets/models/plants): albedo times the vertex colour, as the plain material
//     was, plus snow. Snow lies on the faces that point up and, as it gets deeper (`snow`, the colour of the
//     ground cover, set by WindSway.update like the trees'), on steeper and steeper ones, with a ragged edge
//     from a little noise over the world position so it is patchy instead of a clean line.
// ----------------------------------------------------------------
shader_type spatial;
render_mode cull_back;
#include "res://shaders/sway_common.gdshaderinc"

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	fade_out(VERTEX, FRAGCOORD.xy);
	vec3 base = sway_colour(COLOR);
	float up = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y;
	float n = sin(wpos.x * 9.0 + wpos.z * 7.0) * sin(wpos.y * 11.0 + wpos.x * 5.0) * 0.5 + sin(wpos.z * 17.0 - wpos.y * 13.0) * 0.5;
	float edge = mix(0.92, 0.22, clamp(snow, 0.0, 1.0)) - n * 0.12;
	float lies = smoothstep(edge, edge + 0.14, up) * smoothstep(0.03, 0.16, snow);
	ALBEDO = mix(base, snow_color * (0.92 + 0.08 * up), lies);
	ROUGHNESS = mix(roughness_value, 0.8, lies);
}
