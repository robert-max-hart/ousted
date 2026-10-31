// ----------------------------------------------------------------
// Cloud bank
//     The clouds round the edge of the map (scripts/world/map_edge_clouds.gd): soft billows made of ellipsoids
//     (INSTANCE_CUSTOM.x is each one's phase, the instance colour its shade), which swell and sink slowly so the
//     bank is never still. `tint` is the cloud colour of the moment, set from the sky's horizon colour by the
//     script (so they go gold at dusk and dark at night); `clock` runs with the game (WindSway.track).
//     (Vertex and instance colours are used as they are: see terrain.gdshader.)
// ----------------------------------------------------------------
shader_type spatial;
render_mode cull_back;

uniform float clock = 0.0;
uniform vec3 tint : source_color = vec3(0.9, 0.93, 0.97);
uniform float glow = 0.08;            // how much of the cloud's colour it gives off itself, so the shaded side is not black

varying float height01;            // 0 at the bottom of the billow and 1 at its top

void vertex() {
	height01 = clamp(VERTEX.y * 0.5 + 0.5, 0.0, 1.0);
	float ph = INSTANCE_CUSTOM.x;
	float swell = sin(clock * 0.21 + ph) * 0.5 + sin(clock * 0.13 + ph * 2.3) * 0.5;
	VERTEX.xz *= 1.0 + 0.045 * swell;
	VERTEX.y *= 1.0 + 0.06 * sin(clock * 0.17 + ph * 1.7);
}

void fragment() {
	vec3 c = tint * COLOR.rgb * 0.86 * mix(0.6, 1.0, smoothstep(0.1, 0.9, height01));       // greyer and bluer underneath, bright on top
	c = mix(c, c * vec3(0.9, 0.95, 1.05), 1.0 - height01);
	ALBEDO = c;
	EMISSION = c * glow;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
