shader_type canvas_item;

// Luz propia de un personaje con normal map (estilo anime): el color de la hoja es el piso y el ambiente
// (CanvasModulate) no lo oscurece, o lo oscurece de a poco con ambient_strength. Cada antorcha (luz en modo Mix) mira
// la normal en el plano del piso: el lado que la mira sube uno o dos tonos de su rampa, en bandas, y en ambiente oscuro
// el lado contrario baja un tono, así la luz se lee por contraste. Todos los tonos salen de tone_lut.
// Character own-light with a normal map (anime style): the sheet colour is the floor and the ambient (CanvasModulate)
// does not darken it, or only partly with ambient_strength. Each torch (Mix light) reads the normal on the floor plane:
// the side facing it lifts one or two tones of its ramp, in bands, and in a dark ambient the far side drops one tone,
// so the light reads by contrast. Every tone comes from tone_lut.

// Columna = color de la hoja; fila 0 = el color, 1 = un tono más claro, 2 = dos tonos más claros, 3 = un tono más
// oscuro, 4 = la versión cálida de la fila 2 con un color de la paleta (pelo, piel u oro)
// Column = sheet colour; row 0 = the colour, 1 = one tone lighter, 2 = two lighter, 3 = one darker, 4 = row 2's warm
// palette version (hair, skin or gold)
uniform sampler2D tone_lut : filter_nearest;
// Color del CanvasModulate de la escena; blanco si no hay / the scene's CanvasModulate colour; white if none
uniform vec3 ambient_color = vec3(1.0);
// Cuánto oscurece el ambiente (0 = la hoja tal cual, 1 = como cualquier sprite) / how much the ambient darkens
uniform float ambient_strength : hint_range(0.0, 1.0) = 0.0;
// Intensidad (lado hacia la luz × anillo × energía) que sube un tono / intensity (side facing × ring × energy) that
// lifts one tone
uniform float first_band : hint_range(0.0, 2.0) = 0.1;
// Intensidad que sube dos tonos (el borde que mira a la luz); más de 2 la apaga / intensity that lifts two tones (the
// edge facing the light); above 2 disables it
uniform float second_band : hint_range(0.0, 3.0) = 0.4;
// Cuánto tiene que dar la espalda a la luz un píxel para bajar un tono (0 = medio lado, 1 = solo el borde)
// How far a pixel must face away from the light to drop one tone (0 = half the side, 1 = only the edge)
uniform float shadow_side : hint_range(0.0, 1.0) = 0.1;
// Anillo × energía mínimo para que la antorcha haga sombra: solo cerca (con la antorcha de la cripta, energía 0,6, los
// dos anillos de adentro) / min ring × energy for the torch to cast shadow: only when close (crypt torch, energy 0.6:
// the two inner rings)
uniform float shadow_reach : hint_range(0.0, 3.0) = 0.35;
// Luminancia del ambiente por encima de la cual no hay sombra; 1 = siempre, porque la cripta es oscura por sus tiles y
// no tiene CanvasModulate; bajarla (~0,5) en escenas de día / ambient luminance above which there is no shadow; 1 =
// always, since the crypt is dark by its tiles and has no CanvasModulate; lower it (~0.5) in daytime scenes
uniform float shadow_max_ambient : hint_range(0.0, 1.0) = 1.0;
// La segunda banda usa la fila cálida (4) en vez de la 2 / the second band uses the warm row (4) instead of row 2
uniform bool warm_edge = false;

// Modulate del sprite por el piso de ambiente, para la salida de light() / sprite modulate times the ambient floor
// for light()'s output
varying vec3 lit_scale;

vec3 toned(vec3 colour, int row) {
	int count = textureSize(tone_lut, 0).x;
	for (int i = 0; i < count; i++) {
		if (distance(texelFetch(tone_lut, ivec2(i, 0), 0).rgb, colour) < 0.01) {
			return texelFetch(tone_lut, ivec2(i, row), 0).rgb;
		}
	}
	return colour;
}

void fragment() {
	vec3 ambient_floor = mix(vec3(1.0), ambient_color, ambient_strength);
	// COLOR ya trae modulate × hoja; se separa el modulate (hit flash) / COLOR is modulate × sheet; split the modulate
	lit_scale = COLOR.rgb / max(texture(TEXTURE, UV).rgb, vec3(0.001)) * ambient_floor;
	// Godot multiplica por el CanvasModulate después: se compensa acá / Godot multiplies by CanvasModulate afterwards
	COLOR.rgb *= ambient_floor / max(ambient_color, vec3(0.01));
}

void light() {
	// Solo el plano: la altura de la luz no achata los lados (en el juego las antorchas tienen altura 0)
	// Floor plane only: the light height does not flatten the sides (in game torches have height 0)
	float side = dot(NORMAL.xy, LIGHT_DIRECTION.xy) / max(length(LIGHT_DIRECTION.xy), 0.001);
	float peak = max(LIGHT_COLOR.r, max(LIGHT_COLOR.g, LIGHT_COLOR.b));
	float reach = peak * LIGHT_ENERGY;
	float intensity = side * reach;
	int row = intensity >= second_band ? (warm_edge ? 4 : 2) : (intensity >= first_band ? 1 : 0);
	bool dark = dot(ambient_color, vec3(0.299, 0.587, 0.114)) <= shadow_max_ambient;
	if (row == 0 && dark && reach >= shadow_reach && side <= -shadow_side) {
		row = 3;
	}
	// Mix con alfa 0 deja el piso; con alfa 1 lo reemplaza: varias antorchas no se suman
	// Mix with alpha 0 keeps the floor; alpha 1 replaces it: several torches never add up
	// shortcut: con dos antorchas cerca, la sombra de la última tapa la luz de la otra; resolverlo cuando haya salas
	// con más de una antorcha al alcance del personaje
	// shortcut: with two torches near, the later one's shadow covers the other's light; fix when rooms put more than
	// one torch in reach of a character
	LIGHT = vec4(toned(texture(TEXTURE, UV).rgb, row) * lit_scale, row > 0 ? 1.0 : 0.0);
}
