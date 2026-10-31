// ----------------------------------------------------------------
// Animal
//     Moves the parts of a farm animal (assets/models/animals, made by tools/make_animals.py).
//     `mode` 0 is the legs: they swing about the hip height, a biped's one against the other,
//     a quadruped's in diagonal pairs (front left with back right). `mode` 1 is the head: it
//     nods about a pivot, down to the ground and back (pecking, grazing). Each animal in the
//     multimesh brings its own timing in INSTANCE_CUSTOM: x a phase, y how much it is walking
//     (0 to 1), z how much it is grazing (0 to 1). `clock` is advanced by the script with the
//     game's speed (WindSway.update), so the animals stop when the game is paused.
//     (The vertex and instance colours are used as they are: see terrain.gdshader.)
// ----------------------------------------------------------------
shader_type spatial;
render_mode cull_back;

uniform float clock = 0.0;
uniform int mode = 0;
uniform float hip_y = 0.3;
uniform float leg_x = 0.0;            // where a leg's pivot is along the body (a quadruped's front legs at +leg_x, the back at -leg_x)
uniform float quadruped = 1.0;        // 1 for four legs, 0 for two
uniform float leg_amp = 0.35;         // how far a leg swings, in radians
uniform float leg_speed = 4.0;
uniform vec3 head_pivot = vec3(0.3, 0.5, 0.0);
uniform float nod_amp = 0.7;          // how far the head dips, in radians
uniform float nod_speed = 1.5;

void vertex() {
	float phase = INSTANCE_CUSTOM.x;
	if (mode == 0) {
		float side = quadruped > 0.5 ? (VERTEX.x * VERTEX.z > 0.0 ? 0.0 : 3.14159) : (VERTEX.z > 0.0 ? 0.0 : 3.14159);
		float a = leg_amp * sin(clock * leg_speed + phase + side) * INSTANCE_CUSTOM.y;
		vec3 piv = vec3(quadruped > 0.5 ? (VERTEX.x > 0.0 ? leg_x : -leg_x) : 0.0, hip_y, 0.0);
		float c = cos(a);
		float s = sin(a);
		vec3 rel = VERTEX - piv;
		VERTEX = piv + vec3(rel.x * c - rel.y * s, rel.x * s + rel.y * c, rel.z);
		NORMAL = vec3(NORMAL.x * c - NORMAL.y * s, NORMAL.x * s + NORMAL.y * c, NORMAL.z);
	} else {
		float dip = smoothstep(0.1, 0.95, sin(clock * nod_speed + phase * 1.7) * 0.5 + 0.5);
		float a = -nod_amp * (0.12 + 0.88 * dip * INSTANCE_CUSTOM.z) ;
		float c = cos(a);
		float s = sin(a);
		vec3 rel = VERTEX - head_pivot;
		VERTEX = head_pivot + vec3(rel.x * c - rel.y * s, rel.x * s + rel.y * c, rel.z);
		NORMAL = vec3(NORMAL.x * c - NORMAL.y * s, NORMAL.x * s + NORMAL.y * c, NORMAL.z);
	}
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.9;
}
