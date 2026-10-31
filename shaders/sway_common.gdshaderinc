// Shared by the swaying materials (trees, bushes, grass): the uniforms, the wind, and the colour.
// The offset grows with the square of the height over the instance's base (roots and feet stay put, crowns and
// blade tips move most), and its phase comes from where the instance stands, so neighbours do not move in step.
uniform vec4 albedo : source_color = vec4(1.0);
uniform float clock = 0.0;            // advanced by the script with the game's speed: the sway pauses with the game
uniform float wind = 1.0;             // how hard it blows now: 1 in calm weather, more in rain
uniform vec2 wind_dir = vec2(0.8, 0.6);
uniform float sway = 0.1;             // metres of sway at height_ref in calm weather
uniform float height_ref = 3.0;       // the height (in the mesh's own units) the sway is measured at
uniform float flutter = 0.35;         // the share of fast small movement on top of the slow big waves
uniform float roughness_value = 0.95;

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
