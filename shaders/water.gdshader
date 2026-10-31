// ----------------------------------------------------------------
// Water
//     The water surface: a grid at sea level whose vertex colour holds the
//     shallow to deep tint and, in alpha, how deep it is (0 at the shore,
//     up to 0.78 in deep water). On top of that colour it adds slow swells
//     (vertex), two scrolling ripple layers that tilt the normal so the
//     sun and moon glint on it (fragment), and a broken band of foam in
//     the shallows. `clock` is advanced by the script with the game's
//     speed, so the water stops when the game is paused.
// ----------------------------------------------------------------
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

uniform float clock = 0.0;
uniform float swell = 0.035;          // height of the swells in metres (deep water)
uniform float ripple = 0.55;          // how strongly the ripples tilt the surface
uniform float roughness_value = 0.16;
uniform float brightness = 1.3;       // the tint is lifted a little so the water stays a clear blue under the sun
uniform float glow = 0.12;
uniform vec3 foam_color : source_color = vec3(0.92, 0.96, 0.98);
uniform sampler2D ripples : repeat_enable, filter_linear_mipmap;      // a seamless noise, made in code

varying vec3 world_pos;
varying float depth01;

float swell_height(vec2 p, float t) {
	return sin(p.x * 0.55 + t * 0.9) * 0.5 + sin(p.y * 0.43 - t * 0.7 + p.x * 0.2) * 0.5;
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_pos = wp;
	depth01 = clamp(COLOR.a / 0.78, 0.0, 1.0);
	// no swell at the shore (so the ground never pokes through), full swell in deep water
	VERTEX.y += swell_height(wp.xz, clock) * swell * smoothstep(0.1, 0.8, depth01);
}

void fragment() {
	vec2 p = world_pos.xz;
	// two ripple layers drifting in different directions
	vec2 n1 = texture(ripples, p * 0.09 + vec2(clock * 0.012, clock * 0.007)).rg * 2.0 - 1.0;
	vec2 n2 = texture(ripples, p * 0.23 + vec2(-clock * 0.016, clock * 0.011)).rg * 2.0 - 1.0;
	vec2 tilt = (n1 * 0.6 + n2 * 0.4) * ripple;
	vec3 world_normal = normalize(vec3(tilt.x, 1.0, tilt.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);       // (NORMAL is in view space)

	// the vertex tint is stored as plain sRGB values, as the old material read it
	vec3 tint = pow(COLOR.rgb, vec3(2.2));
	float shore = 1.0 - smoothstep(0.0, 0.5, depth01);
	// foam: bits of the shallow band, drifting, brighter right at the edge
	float f = texture(ripples, p * 0.17 + vec2(clock * 0.02, -clock * 0.015)).b;
	float foam = shore * smoothstep(0.52, 0.8, f + shore * 0.35) * (0.35 + 0.65 * (1.0 - smoothstep(0.0, 0.18, depth01)));
	ALBEDO = mix(tint * brightness, foam_color, foam);
	EMISSION = tint * glow * (1.0 - foam);       // a little self-light keeps the stylised blue in dull weather and at dusk
	ALPHA = clamp(COLOR.a + foam * 0.5, 0.0, 0.92);
	ROUGHNESS = mix(roughness_value, 0.6, foam);
	METALLIC = 0.0;
	SPECULAR = 0.55;
}
