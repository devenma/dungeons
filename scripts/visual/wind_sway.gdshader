shader_type canvas_item;

// Viento para plantas en pixel art. Lo principal es el susurro del borde: solo los racimos del contorno de la copa
// asoman o se esconden 1 px, cada uno a su ritmo, y el interior queda quieto (correr la copa entera a 1 px se leía
// como una línea que se mueve, no como hojas). Opcional, `sway_px` corre además la copa en franjas enteras. La parte
// de abajo (tronco) no se mueve. La fase sale de la posición en el mundo: el viento cruza la escena como una ola.
// Un solo material compartido es el viento de toda la escena.
// Wind for pixel-art plants. The main effect is an edge rustle: only the canopy's outline clusters pop in or out by
// 1 px, each at its own pace, and the inside stays still (shifting the whole canopy by 1 px read as a moving line, not
// leaves). Optionally `sway_px` also shifts the canopy in whole bands. The bottom (trunk) never moves. The phase comes
// from the world position, so the wind crosses the scene as a wave. One shared material is the whole scene's wind.

// Fracción de abajo que no se mueve (tronco y base) / bottom fraction that never moves (trunk and base)
uniform float still_fraction : hint_range(0.0, 0.9) = 0.3;
// Susurro del borde: corrimiento (px), velocidad (rad/s), tamaño de cada racimo (px) y qué parte del tiempo asoma
// cada racimo (0 = siempre quieto, 1 = siempre movido) / edge rustle: shift (px), speed (rad/s), cluster size (px) and
// how much of the time each cluster is out
uniform float rustle_px : hint_range(0.0, 2.0) = 1.0;
uniform float rustle_speed : hint_range(0.0, 8.0) = 2.2;
uniform float cluster_px : hint_range(1.0, 8.0) = 3.0;
uniform float rustle_share : hint_range(0.0, 1.0) = 0.35;
// Cuántos px hacia adentro del borde cuentan como borde / how many px inside the edge count as edge
uniform int edge_px : hint_range(1, 3) = 2;
// Balanceo opcional de la copa en franjas (0 = apagado), velocidad, franjas y atraso de cada una (rad)
// Optional canopy sway in bands (0 = off), speed, bands and each band's lag (rad)
uniform float sway_px : hint_range(0.0, 4.0) = 0.0;
uniform float sway_speed : hint_range(0.0, 6.0) = 1.4;
uniform int band_count : hint_range(1, 4) = 2;
uniform float lag : hint_range(0.0, 2.0) = 0.5;
// Ráfagas: velocidad (rad/s) y cuánto bajan la fuerza (0 = sin ráfagas) / gusts: speed and how much they dip it
uniform float gust_speed : hint_range(0.0, 2.0) = 0.37;
uniform float gust_depth : hint_range(0.0, 1.0) = 0.35;

varying float phase;
varying vec4 tint;

void vertex() {
	phase = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).x * 0.07;
	tint = COLOR;
}

float alpha_at(sampler2D tex, vec2 texel, vec2 px_size) {
	return texture(tex, (texel + 0.5) * px_size).a;
}

void fragment() {
	vec2 size = 1.0 / TEXTURE_PIXEL_SIZE;
	vec2 texel = floor(UV * size);
	// 0 en la fila de abajo, 1 arriba / 0 at the bottom row, 1 on top
	float height = 1.0 - (texel.y + 0.5) / size.y;
	vec2 shift = vec2(0.0);
	if (height > still_fraction) {
		float gust = 1.0 - gust_depth + gust_depth * sin(TIME * gust_speed + phase * 1.7);
		if (sway_px > 0.0) {
			float bands = float(band_count);
			float band = min(floor((height - still_fraction) / (1.0 - still_fraction) * bands), bands - 1.0);
			float band_amplitude = floor(sway_px * (band + 1.0) / bands + 0.5);
			shift.x = floor(band_amplitude * gust * sin(TIME * sway_speed + phase - (bands - 1.0 - band) * lag) + 0.5);
		}
		// Borde: algún vecino a edge_px o menos con distinta opacidad / edge: a neighbour within edge_px of different opacity
		float here = alpha_at(TEXTURE, texel, TEXTURE_PIXEL_SIZE);
		bool edge = false;
		for (int d = 1; d <= edge_px; d++) {
			float fd = float(d);
			edge = edge || abs(alpha_at(TEXTURE, texel + vec2(fd, 0.0), TEXTURE_PIXEL_SIZE) - here) > 0.5
					|| abs(alpha_at(TEXTURE, texel - vec2(fd, 0.0), TEXTURE_PIXEL_SIZE) - here) > 0.5
					|| abs(alpha_at(TEXTURE, texel - vec2(0.0, fd), TEXTURE_PIXEL_SIZE) - here) > 0.5;
		}
		if (edge) {
			vec2 cell = floor(texel / cluster_px);
			float seed = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
			// La ola cruza la escena: depende de la x del racimo en el mundo / the wave crosses the scene with world x
			float wave = sin(TIME * rustle_speed + seed * 6.2831 + phase * 4.0 + cell.x * 0.5);
			float threshold = 1.0 - rustle_share * gust;
			float out_dir = wave > threshold ? 1.0 : (wave < -threshold ? -1.0 : 0.0);
			shift += vec2(out_dir, seed > 0.5 ? 0.0 : -abs(out_dir)) * rustle_px;
		}
	}
	COLOR = texture(TEXTURE, (texel - shift + 0.5) * TEXTURE_PIXEL_SIZE) * tint;
}
