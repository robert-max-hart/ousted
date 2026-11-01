// ----------------------------------------------------------------
// Cloud bank
//     The clouds round the edge of the map (scripts/world/map_edge_clouds.gd): billows made of ellipsoids
//     (INSTANCE_CUSTOM.x is each one's phase, the instance colour its shade). Each surface is pushed out into
//     lumps (a few sine waves over the direction from the centre: a cauliflower shape instead of a smooth ball)
//     and shaded by those lumps and a noise texture instead of the sun, so crests are bright, creases grey and
//     the underside bluish. They swell and sink slowly so the bank is never still.
//     `tint` is the cloud colour of the moment (from the sky's horizon colour, so they go gold at dusk);
//     `clock` runs with the game (WindSway.track); `lumps` is the seamless noise made in code.
//     (Vertex and instance colours are used as they are: see terrain.gdshader.)
// ----------------------------------------------------------------
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, unshaded;

uniform float clock = 0.0;
uniform vec3 tint : source_color = vec3(0.9, 0.93, 0.97);
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform float soft_depth = 7.0;       // metres over which a cloud fades out as it meets the ground (no hard intersection line)
uniform sampler2D lumps : repeat_enable, filter_linear_mipmap;
uniform float wispy = 1.0;            // 1: the silhouette breaks up into dithered wisps (pixels dropped by a pattern, no blending); 0: solid
uniform float lump_depth = 0.3;       // how far the lumps stand out of the ball (as a share of its size)

varying float height01;               // 0 at the bottom of the billow and 1 at its top
varying float lump;                   // -1 to 1: the shape's own lumps, a crest is high
varying vec3 obj;                     // the point on the unit ball, for the texture
varying float phase;

float lumps_at(vec3 d, float ph) {
	float a = sin(d.x * 4.1 + ph) + sin(d.y * 5.3 - ph * 1.3) + sin(d.z * 4.7 + ph * 0.7);
	float b = sin(d.x * 9.0 - d.z * 7.0 + ph * 2.1) + sin(d.y * 8.0 + d.x * 6.0 - ph);
	float c = sin(d.x * 15.0 + d.y * 11.0 + ph * 3.1) + sin(d.z * 14.0 - d.y * 12.0 - ph * 1.7);
	return clamp(a * 0.2 + b * 0.2 + c * 0.14, -1.0, 1.0);
}

void vertex() {
	float ph = INSTANCE_CUSTOM.x;
	phase = ph;
	vec3 d = normalize(VERTEX);
	lump = lumps_at(d, ph);
	obj = d;
	height01 = clamp(VERTEX.y * 0.5 + 0.5, 0.0, 1.0);
	VERTEX *= 1.0 + lump_depth * lump;
	float swell = sin(clock * 0.21 + ph) * 0.5 + sin(clock * 0.13 + ph * 2.3) * 0.5;
	VERTEX.xz *= 1.0 + 0.045 * swell;
	VERTEX.y *= 1.0 + 0.06 * sin(clock * 0.17 + ph * 1.7);
}

void fragment() {
	vec2 drift = vec2(clock * 0.004, 0.0);
	float n1 = (texture(lumps, obj.xz * 0.8 + vec2(phase * 0.13) + drift).r + texture(lumps, obj.xy * 0.8 + vec2(phase * 0.29) - drift).r) * 0.5;
	float n2 = (texture(lumps, obj.xz * 2.6 + vec2(phase * 0.41)).r + texture(lumps, obj.zy * 2.6 + vec2(phase * 0.17)).r) * 0.5;
	float n = n1 * 0.6 + n2 * 0.4;
	float up = smoothstep(0.05, 0.95, height01);
	// crests lit, creases grey, the top bright and the underside bluish
	float shade = 0.74 + 0.32 * smoothstep(-0.6, 0.7, lump) + 0.26 * (n - 0.5) * 2.0;
	shade *= mix(0.72, 1.06, up);
	vec3 c = tint * COLOR.rgb * clamp(shade, 0.0, 1.15);
	c = mix(c * vec3(0.86, 0.92, 1.06), c, up);
	ALBEDO = c;
	// soft contact with the ground: fade by the distance between this surface and the terrain behind it
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 sv = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d * 2.0 - 1.0, 1.0);
	float scene_dist = -(sv.xyz / sv.w).z;
	float gap = scene_dist - (-VERTEX.z);
	float contact = smoothstep(0.0, soft_depth, gap);
	ALPHA = contact;
	if (wispy > 0.5) {
		// how much of the cloud is there: full where the surface faces us, thinning toward the silhouette and
		// where the noise is low, so the rim frays; the pixels that go are chosen by a screen pattern
		float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
		float body = smoothstep(0.05, 0.9, facing + (n - 0.5) * 1.1 + lump * 0.3);
		float dither = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		if (body < dither) {
			discard;
		}
	}
}
