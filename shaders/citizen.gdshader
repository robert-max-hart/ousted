// ----------------------------------------------------------------
// Citizen
//     The colouring of a citizen's body parts (assets/models/citizens,
//     made by tools/make_citizens.py). The mesh's vertex colour says what
//     a surface is: a colour with a single channel marks a region that
//     takes this citizen's own colour, and its brightness is the shading
//     within the mesh: red is the shirt, green the trousers, blue the
//     skin, red and green together the hair. Any other vertex colour
//     (boots, belt, eyes, tool heads) is used as it is. (Vertex colours
//     are not converted from sRGB in the Compatibility renderer: see
//     terrain.gdshader.)
// ----------------------------------------------------------------
shader_type spatial;
render_mode cull_back;

uniform vec3 shirt : source_color = vec3(0.4, 0.4, 0.6);
uniform vec3 trousers : source_color = vec3(0.3, 0.25, 0.2);
uniform vec3 skin : source_color = vec3(0.9, 0.75, 0.62);
uniform vec3 hair : source_color = vec3(0.3, 0.2, 0.1);

varying vec3 shown;

void vertex() {
	vec3 c = COLOR.rgb;
	float s = max(c.r, max(c.g, c.b));
	bool r = c.r > 0.04;
	bool g = c.g > 0.04;
	bool b = c.b > 0.04;
	shown = c;
	if (r && !g && !b) {
		shown = shirt * s;
	} else if (!r && g && !b) {
		shown = trousers * s;
	} else if (!r && !g && b) {
		shown = skin * s;
	} else if (r && g && !b) {
		shown = hair * s;
	}
}

void fragment() {
	ALBEDO = shown;
	ROUGHNESS = 0.9;
}
