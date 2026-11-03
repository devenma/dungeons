# tools/art — herramientas de arte

Scripts de Python que arman el arte fuera del motor. Usan Python 3.13 con Pillow y numpy, y Aseprite 1.3.18 en
modo batch (ruta en la variable `ASEPRITE`; por defecto, la de Steam).

## Entorno (cripta)

- `build_crypt_atlas.py`: arma el atlas de la cripta oscura.
- `export_room.py`: exporta salas de la vista previa.

## Flora (suelo y matas)

`flora.py`: generador procedural genérico, configurado por un preset JSON (el de este juego,
`art/source/flora/pradera.json`). `suelo` arma el piso plano en 2D (tiles de pasto sin costura y tileset Wang
pasto/tierra con el formato de `ground_cozy.json`, hoja de flores, tréboles y piedritas, muestra `.aseprite` con
capas); `matas` modela las matas en 3D y las renderiza con `rig3d.py` (necesita `BLENDER`) como sprites con pivote,
sombra de contacto, viento de 4 cuadros y normales, y un atlas común (`flora_atlas.png`, una fila por especie y
variante) para dibujarlas todas con un MultiMesh; `lamina` las reparte con disco de Poisson (`blue_noise`) y arma la
revisión ×4 y el GIF del viento. Opcional: las especies con `"hornear": true` van dentro de los tiles de pasto
(`suelo --matas DIR`, 4 cuadros por tile animados por el TileSet).

## Personajes 2D y gremio

Flujo: fuentes del artista en `art/source/` → herramientas de acá → hojas en `assets/art/characters/` y `.aseprite`
con capas en `art/source/`.

| Script | Para qué |
|---|---|
| `aseprite_io.py` | Exporta las capas de un `.aseprite` a PNG y escribe `.aseprite` con capas y etiquetas. |
| `outline.py` | Contorno de 1 px en capa propia, con la regla del artista (sin línea entre las piernas). |
| `guild_mockup.py` | Maquetas del gremio: sala sin luz con piezas sueltas, tablones dibujados, sombras y luz simulada. |
| `guild_preview_export.py` | Despiece de la maqueta A+ para `scenes/preview/guild_preview.tscn`: fondo sin luz, llamas aparte y piezas en `assets/art/guild_preview/`. |

## Personajes en 3D (rig3d)

Cada personaje tiene un modelo 3D de piezas simples que se anima y se renderiza a 40 px con la cámara del juego.
Guías: `art/guias/modelado.md` y `art/guias/animacion.md`. Los datos van en `art/source/<personaje>/3d/`
(`modelo.json`, `ref/`, `anim/`). Usa Blender 5.2 en segundo plano: ruta en la variable `BLENDER`.

| Script | Para qué |
|---|---|
| `rig3d.py` | `cuadros` renderiza animaciones y exporta hoja + JSON para `kit_sprite.gd` (sin efectos; la estela del corte va aparte en `_efectos.png`, con las mismas celdas), `.aseprite` con capas (efectos, personaje, contorno), GIF, hoja de revisión y marcadores; `vistas` saca vistas grandes del modelo; `ajuste` lo compara con las referencias; `sondeo` mide hacia dónde mueve cada canal. El `anchor` del JSON es una esquina de píxel, como lo lee `kit_sprite.gd` (`offset = -Vector2(feet_x, sole_y)`): `sole_y` es el borde de abajo de la fila de las suelas (62 con `margen_suela` 2) y `feet_x` la mitad del lienzo (32); con `desfase_x` -0,5 el eje de la figura queda medio píxel a la izquierda (columna 31), que no se arregla con offsets enteros. |
| `rig3d_blender.py` | Corre dentro de Blender: arma el modelo, la proyección de los píxeles del artista, la cámara y las poses. |
| `motion.py` | Expande claves a cuadros (lineal, entrada-salida o escalón) y ayuda con el movimiento secundario. |
| `paquete_modelado.py` | Paquete de apoyo para modelar: `hoja` arma la hoja de giro medida (vistas a la misma escala con líneas de altura) desde `3d/paquete.json`; `guia` renderiza a 0° una malla de referencia (frente, perfil, espalda, arriba). |

Tests: `python -I tools/art/test_tools.py` (salida 0 = pasa). Con `BLENDER` definida corre además el sondeo de signos.
