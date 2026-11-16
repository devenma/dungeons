shader_type canvas_item;

// Luz de props del pueblo con normal map facetado (Pixel Art Lighter): la luz directa se multiplica por la máscara
// con un piso, y los píxeles emisivos se dividen por el tinte de noche para que el CanvasModulate los deje como estaban.
// Town prop lighting with a faceted normal map (Pixel Art Lighter): direct light is scaled by the light mask with a
// floor, and emissive pixels are divided by the night tint so the CanvasModulate leaves them as they were.

// Cuánta luz directa recibe cada píxel (blanco = toda) / how much direct light each pixel takes (white = all)
uniform sampler2D light_mask_tex : filter_nearest;
// Lo mínimo que deja pasar la máscara: 0 = como sale de la herramienta / the least light the mask lets through
uniform float mask_floor : hint_range(0.0, 1.0) = 0.5;
// Píxeles que brillan solos (fragua, vidrio del farol) / pixels that glow on their own (forge, lamp glass)
uniform sampler2D emission_tex : filter_nearest;
uniform bool has_emission = false;
// El color del NightTint / the NightTint colour
uniform vec3 night_tint = vec3(1.0);

void fragment() {
	COLOR = texture(TEXTURE, UV);
	if (has_emission) {
		COLOR.rgb = mix(COLOR.rgb, COLOR.rgb / night_tint, texture(emission_tex, UV).r);
	}
}

void light() {
	float facing = max(dot(NORMAL, LIGHT_DIRECTION), 0.0);
	float mask = mix(mask_floor, 1.0, texture(light_mask_tex, UV).r);
	LIGHT = vec4(COLOR.rgb * LIGHT_COLOR.rgb * LIGHT_ENERGY * facing * mask, LIGHT_COLOR.a);
}
