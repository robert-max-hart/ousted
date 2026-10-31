// ----------------------------------------------------------------
// Goods
//     The goods stacked in a stockpile (assets/models/goods). The mesh's
//     vertex colours are used as they are, except parts coloured light
//     (every channel 0.8 or more): those take the item's colour, which the
//     script puts in each instance's custom data. So a crate keeps its
//     wooden frame and shows the item on top, a sack is the item's colour
//     with a tan knot. (Vertex colours are not converted from sRGB in the
//     Compatibility renderer: see terrain.gdshader.)
// ----------------------------------------------------------------
shader_type spatial;
render_mode cull_back;

varying vec3 shown;

void vertex() {
	float tinted = step(0.8, min(COLOR.r, min(COLOR.g, COLOR.b)));
	shown = mix(COLOR.rgb, COLOR.rgb * INSTANCE_CUSTOM.rgb, tinted);
}

void fragment() {
	ALBEDO = shown;
	ROUGHNESS = 0.9;
}
