// ----------------------------------------------------------------
// Roof
//     Shingle roofs (SurfaceTextures.roof_material): the same triplanar texture, tint and (for modelled roofs)
//     vertex-colour shading the plain material gave, plus snow. Snow lies on the faces that point up and, as the
//     cover on the ground deepens (`snow`, set by WindSway.update), on steeper and steeper ones, so a low roof
//     whitens first and a steep one last; the edge is ragged from a little noise over the world position, and the
//     shingles still show through a little.
// ----------------------------------------------------------------
shader_type spatial;
render_mode cull_back;
#include "res://shaders/sway_common.gdshaderinc"

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float tex_scale = 0.4;            // tiles per metre
uniform float tex_amount = 1.0;           // 0: no texture (loose parts in their own colours: towers, props)
uniform float use_vertex = 0.0;           // 1: the mesh's vertex colours shade it (modelled roofs)

varying vec3 lpos;
varying vec3 lnorm;
varying vec3 wpos;

void vertex() {
	lpos = VERTEX;
	lnorm = NORMAL;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 w = abs(normalize(lnorm));
	w /= (w.x + w.y + w.z);
	vec3 t = texture(tex, lpos.yz * tex_scale).rgb * w.x + texture(tex, lpos.xz * tex_scale).rgb * w.y + texture(tex, lpos.xy * tex_scale).rgb * w.z;
	vec3 base = albedo.rgb * mix(vec3(1.0), t, tex_amount) * mix(vec3(1.0), COLOR.rgb, use_vertex);
	float up = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y;
	float n = sin(wpos.x * 7.0 + wpos.z * 5.0) * sin(wpos.y * 9.0 + wpos.x * 4.0) * 0.5 + sin(wpos.z * 13.0 - wpos.y * 11.0) * 0.5;
	float edge = mix(0.95, 0.3, clamp(snow, 0.0, 1.0)) - n * 0.08;
	float lies = smoothstep(edge, edge + 0.1, up) * smoothstep(0.03, 0.14, snow);
	ALBEDO = mix(base, snow_color * (0.9 + 0.1 * t.r) * (0.94 + 0.06 * up), lies * 0.96);
	ROUGHNESS = mix(roughness_value, 0.8, lies);
}
