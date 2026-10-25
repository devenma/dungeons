// Sombra de contacto por pasos de tono: oscurece lo que hay debajo uno (anillo) o dos (centro) tonos
// a lo largo de las rampas de la paleta, sin mezcla alfa (BIBLIA_ARTE §2).
// Tone-step contact shadow: steps what is underneath one (ring) or two (core) tones down the palette
// ramps, no alpha blending (BIBLIA_ARTE §2).
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
// Fila 0 color de paleta, fila 1 un paso más oscuro, fila 2 dos pasos / Row 0 palette colour, row 1 one step darker, row 2 two
uniform sampler2D shade_lut : filter_nearest;
// Radios del centro de dos pasos, en px / Two-step core radii, in px
uniform vec2 core_radii = vec2(7.0, 1.6);

varying vec2 local_position;

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	vec3 below = texture(screen_texture, SCREEN_UV).rgb;
	vec2 core = local_position / core_radii;
	int row = dot(core, core) <= 1.0 ? 2 : 1;
	int count = textureSize(shade_lut, 0).x;
	vec3 result = below;
	// Colores fuera de la paleta (personajes, VFX) quedan igual / Off-palette colours (characters, VFX) stay as they are
	float best = 0.0004;
	for (int i = 0; i < count; i++) {
		vec3 delta = texelFetch(shade_lut, ivec2(i, 0), 0).rgb - below;
		float distance = dot(delta, delta);
		if (distance < best) {
			best = distance;
			result = texelFetch(shade_lut, ivec2(i, row), 0).rgb;
		}
	}
	COLOR = vec4(result, 1.0);
}
