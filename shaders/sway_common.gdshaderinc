// Shared by the swaying materials (trees, bushes, grass): the uniforms, the wind, and the colour.
// The offset grows with the square of the height over the instance's base (roots and feet stay put, crowns and
// blade tips move most), and its phase comes from where the instance stands, so neighbours do not move in step.
uniform vec4 albedo : source_color = vec4(1.0);
uniform float clock = 0.0;            // advanced by the script with the game's speed: the sway pauses with the game
uniform float snow = 0.0;             // how much of the ground is under snow (set by WindSway.update)
uniform float snow_hold = 0.0;        // 1 for things snow lies on: pine boughs, bushes
uniform vec3 snow_color : source_color = vec3(0.92, 0.95, 1.0);
uniform float sway_on = 1.0;          // 0 when the player turned wind sway off (Settings)
uniform float wind = 1.0;             // how hard it blows now: 1 in calm weather, more in rain
uniform vec2 wind_dir = vec2(0.8, 0.6);
uniform float sway = 0.1;             // metres of sway at height_ref in calm weather
uniform float height_ref = 3.0;       // the height (in the mesh's own units) the sway is measured at
uniform float flutter = 0.35;         // the share of fast small movement on top of the slow big waves
uniform float roughness_value = 0.95;
uniform float fade_end = 0.0;         // metres from the camera at which this thing is gone (0: never): set by WindSway.update from the draw distance
uniform float fade_band = 14.0;       // it thins out over this many metres before that, as a dither

// Thins the thing out toward its draw distance: pixels are dropped by a pattern that gets sparser with the distance from the camera,
// so trees melt away at the edge instead of the whole block of them popping out (use in fragment(); `view` is VERTEX there).
void fade_out(vec3 view, vec2 frag) {
	if (fade_end > 0.0) {
		float t = clamp((length(view) - (fade_end - fade_band)) / fade_band, 0.0, 1.0);
		float dither = fract(52.9829189 * fract(dot(frag, vec2(0.06711056, 0.00583715))));
		if (t > dither) {
			discard;
		}
	}
}

vec3 sway_offset(vec3 base, float h) {
	float k = clamp(h / height_ref, 0.0, 1.5);
	k *= k;
	float gust = sin(clock * 0.9 + dot(base.xz, vec2(0.045, 0.031))) * 0.6 + 0.5;
	float flap = sin(clock * 2.7 + dot(base.xz, vec2(1.3, 0.9)) + h * 3.0) * flutter;
	return vec3(wind_dir.x, 0.0, wind_dir.y) * (sway * wind * k * (gust + flap));
}

// albedo times the vertex and instance colour, used as they are (the standard material these replace did not convert them
// from sRGB in the Compatibility renderer, so converting here made everything darker)
vec3 sway_colour(vec4 vertex_colour) {
	return albedo.rgb * vertex_colour.rgb;
}
