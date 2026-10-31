// ----------------------------------------------------------------
// Terrain
//     The ground. The base colour is still the vertex colour (grass by
//     season, sand, rock, roads, fields...), as the soil, water and slope
//     overlays also paint it. Alpha is not opacity here: it says how well
//     snow lies on that ground (1 open ground, less on roads and fields,
//     none in a channel). On top of the colour this adds:
//       - ground grain: two scales of noise that break up flat colour
//       - rock strata on steep ground: bands that follow the height
//       - snow cover (`snow`, 0 to 1, set by the script from the weather):
//         it settles on up-facing ground first and on the heights first,
//         in patches at low cover and over everything at full cover.
//     With an overlay on (`overlay_view`) the colour is shown plain.
// ----------------------------------------------------------------
shader_type spatial;
render_mode cull_back;

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;      // red: fine grain, green: patches, blue: snow edge; made in code
uniform float snow = 0.0;
uniform float overlay_view = 0.0;
uniform float grain = 0.35;           // how strongly the ground grain shows
uniform vec3 snow_color : source_color = vec3(0.9, 0.93, 0.97);

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 base = COLOR.rgb;            // used as it is: the standard material this replaces did not convert it either (in the Compatibility renderer)
	float roughness = 1.0;
	if (overlay_view < 0.5) {
		float fine = texture(noise_tex, world_pos.xz * 0.9).g - 0.5;
		float patch = texture(noise_tex, world_pos.xz * 0.2).r - 0.5;
		base *= 1.0 + (fine * 0.55 + patch * 0.7) * grain;

		// steep ground: bands that follow the height, rock-like
		float steep = 1.0 - smoothstep(0.6, 0.86, world_normal.y);
		float strata = texture(noise_tex, vec2((world_pos.x + world_pos.z) * 0.045, world_pos.y * 0.6)).g;
		base = mix(base, base * (0.78 + strata * 0.44), steep * 0.85);

		// snow: up-facing ground and the heights first, patchy edges at low cover
		float edge = texture(noise_tex, world_pos.xz * 0.15).b - 0.5;
		float up = smoothstep(0.4, 0.8, world_normal.y);
		float cover = snow * (up + clamp((world_pos.y - 6.0) * 0.03, 0.0, 0.35));
		float s = smoothstep(0.42, 0.6, cover * COLOR.a * 1.2 + edge * 0.75);
		base = mix(base, snow_color * (0.94 + fine * 0.1), s);
		roughness = mix(1.0, 0.85, s);
	}
	ALBEDO = base;
	ROUGHNESS = roughness;
}
