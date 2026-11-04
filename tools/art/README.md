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
| `rig3d.py` | `cuadros` renderiza animaciones y exporta hoja + JSON para `kit_sprite.gd` (sin efectos; la estela del corte va aparte en `_efectos.png`, con las mismas celdas), `.aseprite` con capas (efectos, personaje, contorno), GIF, hoja de revisión y marcadores. Limpieza 2D antes del espejado y de exportar: `"limpieza"` en la receta (pasadas `hilos`, `sueltos`, `colgados`, `islas` sobre el cuadro compuesto, con los tonos de contorno y sombra de la piel) y `"cabeza_fija": [direcciones]` en la animación (la cabeza del cuadro 0 pegada en todos, corrida por el rebote; con IDs de parte solo se pegan las partes que cuelgan del cuello, con su contorno, y una cola detrás de la cabeza sigue su cuadro); `"espejar_sin": [prefijos]` en la receta deja esas partes (una cola de un lado) fuera del espejo del ciclo: el cuerpo sale espejado y ellas (±1 px) del render propio de c + n/2; `"resortes": {canal: {"impulsado_por", "rigidez", "amortiguacion", "retraso"}}` en la receta suma un resorte de `motion.resortes` a cualquier animación (la cola no necesita tocar la caminata); los ojos 2D no se estampan con la cara cabeza abajo en pantalla (`EYES_TILT_MAX`, 90°). `"limites_pose": [{"nombre", "vistas", "huesos": {hueso: {canal: [mín, máx]}}}]` en la receta acota canales solo al renderizar esas direcciones (de perfil, abrir el brazo lo lleva hacia la cámara sin cambiar la silueta: pasa por delante de la pollera); `"deformar"` y `"quitar_partes"` (los escribe el panel de ajuste en `deformar.json`) corren vértices a mano y sacan partes. `vistas` saca vistas grandes del modelo; `ajuste` lo compara con las referencias; `sondeo` mide hacia dónde mueve cada canal. El `anchor` del JSON es una esquina de píxel, como lo lee `kit_sprite.gd` (`offset = -Vector2(feet_x, sole_y)`): `sole_y` es el borde de abajo de la fila de las suelas (62 con `margen_suela` 2) y `feet_x` la mitad del lienzo (32); con `desfase_x` -0,5 el eje de la figura queda medio píxel a la izquierda (columna 31), que no se arregla con offsets enteros. |
| `rig3d_blender.py` | Corre dentro de Blender: arma el modelo, la proyección de los píxeles del artista, la cámara y las poses. |
| `panel_ajuste/` | Panel para ajustar un personaje con deslizadores y ver el pixel art en vivo, en una página local (`abrir_panel.bat`). `servidor.py` sirve la página y deja un Blender sin interfaz abierto (`worker_blender.py`, `rig3d.RUN_BLENDER`); `vista.py` corre `rig3d.cuadros` con los módulos editados en memoria (`rig3d.PARCHES`); `receta.py` resuelve los controles de `controles.json` y guarda solo los números tocados sin cambiar el formato. Guía: `art/guias/panel_ajuste.md`. |
| `motion.py` | Expande claves a cuadros (lineal, entrada-salida o escalón) y ayuda con el movimiento secundario. |
| `paquete_modelado.py` | Paquete de apoyo para modelar: `hoja` arma la hoja de giro medida (vistas a la misma escala con líneas de altura) desde `3d/paquete.json`; `guia` renderiza a 0° una malla de referencia (frente, perfil, espalda, arriba). |

### Tela caída en el reposo (`"tela"`, apagada por defecto)

Una parte de ropa de la receta (`pollera`, `delantal`...) puede caer como tela sobre el maniquí en vez de quedar rígida:
`{"nombre": "pollera", "tela": {"fijar": "cintura", "cuadros": 100, "rigidez": 100, "cizalla": 1, "compresion": 0.2,
"flexion": 0.1, "amortiguacion": 15, "distancia": 0.05, "sobre": [partes ya caídas]}}`. `rig3d_blender.tela` agrega el modificador
Cloth de Blender con la fila de arriba fija (`fijar`: vértices a `banda` = 0,3 px del tope), colisión con el cuerpo y las
piernas (partes `cuerpo`, `pierna`, `muslo`, `media`) y con las partes de `sobre`, simula `cuadros` en la pose de reposo y
reemplaza los vértices (pesos y sombra quedan; salen redondeados a 4 decimales). Las demás claves son la física de Blender
a escala de píxel (valores por defecto: rigidez 15, compresion = rigidez, flexion 0.5, amortiguacion 2, distancia 0.05); una
rigidez baja estira la tela por la gravedad y una distancia grande la expulsa del cuerpo al arrancar. Además `masa` (0,3), `gravedad`
(factor sobre 9,81; 1) y `calidad_colision` (2). Los valores del panel de ajuste salen de tres preajustes (`controles.json` > `tela`: algodón,
seda, lona) que sí hacen caer la pollera de la maid sobre las piernas; con los viejos (rigidez 100, amortiguación 15) casi no se movía. `{"sigue": "pollera"}`
no simula: copia el corrimiento de esa parte (el ruedo y el delantal siguen a su pollera, así no flotan ni se hunden).
Es determinista (misma receta, mismos píxeles) y `OUT/tela.json` guarda cuánto se movió cada parte y si se asentó
(`ultimo_cuadro_px`). Sin la clave todo sale idéntico a antes. Una parte `"tipo": "malla_fija"` con `"archivo"` (ruta relativa
al módulo) trae vértices, caras y pesos de un JSON: es lo que escribe el botón Hornear del panel (`art/source/modulos/ropa/horneado/`);
la receta con `"hornear": <carpeta>` hace que Blender escriba ahí la forma caída de cada parte con `tela`. La malla horneada
es fija: la animación la mueve con los huesos de la pollera, pero no se vuelve a plegar al caminar.

### Colisión de la ropa con la piel (`"colision"`, apagada por defecto)

`{"nombre": "pollera", "colision": true, "colision_margen": 0.4}` en una parte de ropa: en cada cuadro, después de posar (`pose`),
`rig3d_blender.aplicar_colision` sube hasta superficie + margen (px; 0,4 por defecto) todo vértice de la parte que esté a menos del margen
de los cuerpos (partes `cuerpo`, `pierna`, `muslo`, `media`); hasta `COLISION_PASADAS` vueltas, también con el centro de cada cara y el
punto medio de cada arista (las caras grandes cortaban el muslo aunque sus vértices estuvieran afuera). La parte empujada se dibuja como
malla estática de ese cuadro (el esqueleto ya está aplicado) y el cuadro siguiente la restaura. Sin la clave, o con `false`, no se toca
nada. `OUT/colision.json` cuenta los vértices empujados y el empuje máximo por parte. No usa Cloth, así que sirve en la caminata.

### Panel de ajuste: escena reusada

Si el que corre `rig3d_blender.py` le pasa `PERSIST_PANEL` (un dict; lo hace `panel_ajuste/worker_blender.py`), el script reusa el
esqueleto, las rampas, la luz, las piezas sueltas y las partes que no cambiaron; sin él arma todo de cero. Cada trabajo escribe
`OUT/tiempos.json` con los segundos por etapa. Ver `panel_ajuste/README.md` > Rendimiento.

Tests: `python -I tools/art/test_tools.py` (salida 0 = pasa). Con `BLENDER` definida corre además el sondeo de signos.
