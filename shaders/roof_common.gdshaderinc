// Shared by the roof shaders (roof.gdshader, roof_double.gdshader): a building surface that takes the texture, tint and (optionally)
// vertex colours as the plain material did, plus snow. Snow lies on the faces that point up and, as the cover on the ground deepens
// (`snow`, set by WindSway.update), on steeper and steeper ones, so a low roof whitens first and a steep one last; the edge is
// ragged from a little noise over the world position, and the texture still shows through a little.
// Used for roofs, tower caps, props, fences, headstones, bridge rails, the market awning and the cart's load.
#include "res://shaders/sway_common.gdshaderinc"

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float tex_scale = 0.4;            // tiles per metre
uniform float tex_amount = 1.0;           // 0: no texture (loose parts in their own colours)
uniform float use_vertex = 0.0;           // 1: the mesh's vertex colours shade it (modelled parts)
uniform float world_tex = 0.0;            // 1: the texture is laid out in world space (fences: a rail stretched to the slope keeps its grain)
uniform float stripe_scale = 0.0;         // over 0: awning stripes along x instead of the texture, this many to the metre
uniform vec3 stripe_a : source_color = vec3(0.72, 0.2, 0.16);
uniform vec3 stripe_b : source_color = vec3(0.93, 0.87, 0.7);

varying vec3 lpos;
varying vec3 lnorm;
varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	lpos = VERTEX;
	lnorm = NORMAL;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 p = mix(lpos, wpos, world_tex);
	vec3 w = abs(normalize(mix(lnorm, wnorm, world_tex)));
	w /= (w.x + w.y + w.z);
	vec3 t = texture(tex, p.yz * tex_scale).rgb * w.x + texture(tex, p.xz * tex_scale).rgb * w.y + texture(tex, p.xy * tex_scale).rgb * w.z;
	if (stripe_scale > 0.0) {
		t = mix(stripe_a, stripe_b, step(0.5, fract(lpos.x * stripe_scale)));
	}
	vec3 base = albedo.rgb * mix(vec3(1.0), t, tex_amount) * mix(vec3(1.0), COLOR.rgb, use_vertex);
	float up = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y;
	float n = sin(wpos.x * 7.0 + wpos.z * 5.0) * sin(wpos.y * 9.0 + wpos.x * 4.0) * 0.5 + sin(wpos.z * 13.0 - wpos.y * 11.0) * 0.5;
	float edge = mix(0.95, 0.3, clamp(snow, 0.0, 1.0)) - n * 0.08;
	float lies = smoothstep(edge, edge + 0.1, up) * smoothstep(0.03, 0.14, snow);
	ALBEDO = mix(base, snow_color * (0.9 + 0.1 * t.r) * (0.94 + 0.06 * up), lies * 0.96);
	ROUGHNESS = mix(roughness_value, 0.8, lies);
}
