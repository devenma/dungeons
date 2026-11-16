shader_type canvas_item;

// Fantasma "rush" de un frame del personaje: la silueta en un color plano que se derrite en trazos hacia atrás,
// en escalones de píxel (técnica de @denchan_BSpro, ver AI_GAMEDEV_TECHNIQUES §22). Va en un Sprite2D con región.
// "Rush" ghost of a character frame: the silhouette in one flat colour melting into streaks behind it, in pixel
// steps. Goes on a region-enabled Sprite2D.

// 0..2: cada escalón borra más cuerpo y estira más los trazos / each step erases more body and stretches the streaks
uniform int melt_step = 0;
// Paso entero en px hacia atrás del movimiento, en 8 direcciones / Integer px step away from the motion, 8 directions
uniform vec2 trail = vec2(-1.0, 0.0);
// Rect del frame en la hoja, en px: los trazos no leen frames vecinos / Frame rect in the sheet, in px: streaks never read neighbour frames
uniform vec4 region;
uniform vec4 core_color : source_color = vec4(0.165, 0.122, 0.180, 1.0);
uniform vec4 streak_color : source_color = vec4(0.541, 0.561, 0.659, 1.0);
uniform float seed = 0.0;

float hash(vec2 v) {
	return fract(sin(dot(v, vec2(12.9898, 78.233))) * 43758.5453);
}

bool in_region(vec2 px) {
	return px.x >= region.x && px.y >= region.y && px.x < region.x + region.z && px.y < region.y + region.w;
}

// TEXTURE solo existe dentro de fragment() y pasarlo como argumento no es fiable: macro
// TEXTURE only exists inside fragment() and passing it as an argument is unreliable: macro
#define SOLID(p) (in_region(p) && texture(TEXTURE, ((p) + 0.5) * TEXTURE_PIXEL_SIZE).a > 0.5)

void fragment() {
	vec2 px = floor(UV / TEXTURE_PIXEL_SIZE);
	vec2 local = px - region.xy;
	// Fila (perpendicular al rastro) y avance a lo largo del rastro / Row (across the trail) and progress along it
	float row = dot(local, vec2(-trail.y, trail.x));
	float along = dot(local, trail);
	float s = float(melt_step);
	// Guiones de 3 px por fila: los cortes van a lo largo del rastro, no en manchas / 3 px dashes per row: cuts run along the trail
	bool body = SOLID(px) && hash(vec2(row, floor(along / 3.0)) + seed) >= s * 0.35;
	// Trazo: un píxel del cuerpo hasta `len` px hacia adelante arrastra a este / Streak: a body pixel up to `len` px ahead drags this one
	float len = floor(2.0 + hash(vec2(row, seed)) * 4.0) * (s + 1.0);
	bool streak = false;
	for (int k = 1; k <= 18; k++) {
		if (float(k) > len) {
			break;
		}
		if (SOLID(px - trail * float(k))) {
			streak = true;
			break;
		}
	}
	streak = streak && hash(vec2(row * 7.0, floor(along / 2.0)) + seed) > 0.3 + s * 0.2;
	COLOR = body ? core_color : (streak ? streak_color : vec4(0.0));
}
