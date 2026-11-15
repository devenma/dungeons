shader_type canvas_item;

// Luz de antorcha en bandas sobre un sprite con normal map. Dos modos:
// - En paleta (luz en modo Mix): lejos de la luz el sprite baja un tono de su rampa; la antorcha lo devuelve a su tono
//   o lo sube uno. No agrega colores. Lo que no está en la LUT (contorno, ojos) queda igual.
// - Teñida (luz en modo Add): suma el color de la luz en escalones, sin degradé.
// Banded torch light on a normal-mapped sprite. Two modes:
// - Palette (Mix light): away from the light the sprite drops one tone of its ramp; the torch brings it back to its
//   tone or one step lighter. Adds no colours. Whatever is missing from the LUT (outline, eyes) stays the same.
// - Tinted (Add light): adds the light colour in steps, without gradients.

// Columna = tono de una rampa; fila 0 = el tono, 1 = un paso más oscuro, 2 = un paso más claro
// Column = a ramp tone; row 0 = the tone, 1 = one step darker, 2 = one step lighter
uniform sampler2D tone_lut : filter_nearest;
// Modo en paleta (true) o teñido (false) / palette mode (true) or tinted (false)
uniform bool palette_only = true;
// Intensidad (alcance de la luz × cara hacia la luz) de la primera banda / intensity of the first band
uniform float first_band : hint_range(0.0, 1.0) = 0.2;
// Intensidad de la segunda banda / intensity of the second band
uniform float second_band : hint_range(0.0, 1.0) = 0.4;
// Modo teñido: cuánto color de luz suma cada banda / tinted mode: how much light colour each band adds
uniform float tint_per_band : hint_range(0.0, 1.0) = 0.3;

vec3 tone(vec3 colour, int row) {
	int count = textureSize(tone_lut, 0).x;
	for (int i = 0; i < count; i++) {
		if (distance(texelFetch(tone_lut, ivec2(i, 0), 0).rgb, colour) < 0.01) {
			return texelFetch(tone_lut, ivec2(i, row), 0).rgb;
		}
	}
	return colour;
}

void fragment() {
	COLOR = texture(TEXTURE, UV);
	if (palette_only) {
		COLOR.rgb = tone(COLOR.rgb, 1);
	}
}

void light() {
	float facing = max(dot(NORMAL, LIGHT_DIRECTION), 0.0);
	float peak = max(LIGHT_COLOR.r, max(LIGHT_COLOR.g, LIGHT_COLOR.b));
	float intensity = facing * peak * LIGHT_ENERGY;
	int bands = intensity >= second_band ? 2 : (intensity >= first_band ? 1 : 0);
	if (palette_only) {
		vec3 original = texture(TEXTURE, UV).rgb;
		LIGHT = vec4(bands == 2 ? tone(original, 2) : original, bands > 0 ? 1.0 : 0.0);
	} else {
		vec3 hue = LIGHT_COLOR.rgb / max(peak, 0.001);
		LIGHT = vec4(COLOR.rgb * hue * float(bands) * tint_per_band, 1.0);
	}
}
