// ----------------------------------------------------------------
// Cloud floor
//     A sea of cloud far under and round the map (scripts/world/map_edge_clouds.gd): one huge flat sheet of lumpy
//     cloud colour, drifting slowly, that thins out to nothing far away so it melts into the sky at the horizon. It
//     is what you see past the map's edge instead of the empty sky.
// ----------------------------------------------------------------
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, unshaded;

uniform float clock = 0.0;
uniform vec3 tint : source_color = vec3(0.85, 0.89, 0.94);
uniform vec2 centre = vec2(80.0, 80.0);
uniform float fade_from = 250.0;
uniform float fade_to = 640.0;
uniform sampler2D lumps : repeat_enable, filter_linear_mipmap;      // a seamless noise, made in code

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float a = texture(lumps, p * 0.0035 + vec2(clock * 0.0012, clock * 0.0007)).r;
	float b = texture(lumps, p * 0.011 + vec2(-clock * 0.002, clock * 0.0015)).r;
	float c = texture(lumps, p * 0.03 + vec2(clock * 0.003, -clock * 0.002)).r;
	float n = a * 0.5 + b * 0.32 + c * 0.18;
	float shade = 0.78 + 0.32 * smoothstep(0.3, 0.75, n);
	ALBEDO = tint * shade;
	float d = length(p - centre);
	ALPHA = 1.0 - smoothstep(fade_from, fade_to, d);
}
