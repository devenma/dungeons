# Muestra del gremio nuevo: plan de implementación

> **Para agentes:** sub-skill requerida: superpowers:subagent-driven-development (recomendada) o
> superpowers:executing-plans, tarea por tarea. Los pasos usan casillas (`- [ ]`).

**Objetivo:** una escena de muestra, fuera del juego, con el gremio rehecho en clima *Sea of Stars* más oscuro, la
pelirroja caminando y sentándose en un banco en las 4 direcciones, y capturas automáticas para el equipo.

**Arquitectura:** el arte se produce con herramientas Python en `tools/art/` (portadas del scratchpad) sobre las
fuentes del artista en `art/source/`, y sale como hojas del kit (`.png` + `.json`) que ya carga
`scripts/visual/kit_sprite.gd`. La escena `scenes/preview/guild_preview.tscn` reutiliza la vista previa de arte
(escala entera, modo captura), el jugador de la vista previa y el punto de interacción del gremio. La luz es del
motor: `CanvasModulate` más `PointLight2D` con parpadeo y halos aditivos.

**Stack:** Godot 4.7.2 (GDScript, sin addons), Python 3.13 + Pillow + numpy, Aseprite 1.3.18 en modo batch,
PixelLab REST v2.

**Spec:** [`odd/tasks/gremio-muestra-design.md`](gremio-muestra-design.md).

## Restricciones globales

- Pantalla 480×270, escala entera, filtro nearest. Tiles de 32 px. Sala de 13×9 tiles salvo que la maqueta elegida
  pida otra cosa.
- Personajes en lienzo de 64×64, pies en x 32, suelas en y 47. 4 direcciones (filas S, E, N, W) sin `flip_h`.
- Contorno negro de 1 px en capa propia con la regla del artista (sin línea en el hueco entre piernas, de frente y de
  espaldas).
- La luz no se pinta en tiles ni objetos. Sí el sombreado de volumen (luz de arriba a la izquierda).
- No se toca `main.tscn`, `scenes/guild/`, `scenes/player/`, Hondoval ni la mazmorra.
- Tope de unas **150 generaciones** de PixelLab para toda la muestra. Antes de cada lote se consulta
  `GET /balance` y se anota lo gastado; si el total va a pasar 150, se frena y se avisa.
- No se pasan capturas de *Sea of Stars* ni de *Blasphemous* a PixelLab como referencia: el clima se describe con
  texto y las referencias de estilo son las del artista.
- El token sale de `PIXELLAB_API_TOKEN` del entorno y no se imprime nunca.
- Comentarios bilingües (español primero), tipado explícito, sin marcas de IA (AGENTS §44.1–44.2).
- **Sin commit, push ni PR sin un "sí" explícito del usuario para ese commit.** Los pasos "Proponer commit"
  muestran archivos y mensaje (en español, sin atribución) y esperan.
- Rama `feat/gremio-muestra`, creada desde `feat/arte-base-npc` (lleva los docs del 2026-10-29 sin commitear).

## Foco de revisión

1. **Dos bancos a la vez:** si el jugador pisa las áreas de dos bancos, `interact` sienta en uno solo; parado
   sentado, `interact` lo levanta del suyo y no lo sienta en el otro.
2. **Levantarse dentro de un sólido:** al levantarse, el jugador vuelve a un punto libre fuera del banco, nunca
   queda encerrado en la colisión del banco.
3. **Moverse mientras se sienta:** si se mantiene una dirección apretada al interactuar, se sienta igual y se
   levanta recién con una dirección nueva o con `interact` otra vez; no se sienta y se levanta en el mismo frame.
4. **Oscuridad en los extremos:** subir o bajar muchas veces deja el valor dentro de [0, 0.95] y el número en
   pantalla coincide con el `CanvasModulate`.
5. **Capturas en headless:** el modo `--shot` funciona sin ventana y no deja la escala de la ventana cambiada.

---

### Tarea 1: herramientas de arte y fuentes del artista en el repo

**Archivos:**
- Crear: `art/source/artista/Base_4_Player_V4.aseprite`, `art/source/artista/Maid-V1.aseprite` (copias de
  `~/gamedev/dungeons-base-npc/`).
- Crear: `tools/art/pl.py`, `tools/art/outline.py`, `tools/art/polish.py` (con `strip_outline` adentro),
  `tools/art/score_walk.py`, `tools/art/idle_drop.py`, `tools/art/aseprite_io.py`, `tools/art/README.md`.
- Fuente de cada port: `<scratchpad>/npcflow/tools/` (`pl.py`, `outline.py`, `polish.py`, `post.py`,
  `score_walk.py`, `idle_drop.py`, `to_aseprite.py`, `export_layers.lua`).
- Test: `tools/art/test_tools.py`.

**Interfaces:**
- Produce:
  - `aseprite_io.export_layers(src: str, out_dir: str) -> dict[str, str]`: corre Aseprite en batch y deja un PNG
    por capa (`<Tag>__<Grupo>__<Capa>.png`); devuelve nombre → ruta.
  - `aseprite_io.write(path: str, frames: list[dict[str, np.ndarray]], tags: list[tuple[str, range, int]]) -> None`:
    escribe un `.aseprite` con una capa por clave y etiquetas `(nombre, frames, ms)`.
  - `outline.outline(img: np.ndarray, from_y: int | None = None, max_gap: int = 3) -> np.ndarray` (máscara) y
    `outline.paint(mask, color=(0, 0, 0)) -> np.ndarray` (RGBA).
  - `polish.polish(fr, rest, neck_y, hip_y, swap_head=True, color=(0, 0, 0), leg_gap=True) -> (frames, offs)`.
  - `score_walk.score(frames, rest) -> float` (menos es mejor).
  - `idle_drop.idle(rest, hip_y, offs=(0, 1, 1, 0)) -> list[np.ndarray]`.
  - `pl.py jobs.json out_dir [nombres...]` por línea de comandos, igual que el original.

- [ ] **Paso 1: crear la rama** `git switch -c feat/gremio-muestra`. Verificar con `git status` que siguen los
  cambios de docs sin commitear.
- [ ] **Paso 2: escribir el test** `tools/art/test_tools.py` (asserts, sin pytest):
  - `test_outline_matches_maid`: exporta las capas de `Maid-V1.aseprite`, compone la silueta de Idle y
    compara `outline(silueta, from_y=<cadera>)` con la capa `outline` del artista: **84 coinciden, 0 faltan**.
  - `test_ring_is_outside`: en una silueta sintética de 5×5, el anillo no pisa ningún píxel opaco y tiene 20 px.
  - `test_leg_gap`: dos columnas separadas por 2 px debajo de `from_y` no reciben contorno en el hueco.
  - `test_aseprite_roundtrip`: `write` de 2 frames con capas `Cuerpo` y `Contorno` y etiqueta `walk_south`;
    Aseprite con `--list-layers --list-tags --data` devuelve 2 frames, esas 2 capas y esa etiqueta.
- [ ] **Paso 3: correrlo y ver que falla**: `python -I tools/art/test_tools.py` → error de import.
- [ ] **Paso 4: portar los módulos.** Sin rutas del scratchpad: cada script recibe rutas por argumento o las
  calcula desde la raíz del repo. `pl.py` lee `PIXELLAB_API_TOKEN` del entorno. Comentarios bilingües. El README
  explica el flujo: fuentes → herramientas → `assets/art/`.
- [ ] **Paso 5: correr el test**: `python -I tools/art/test_tools.py` → `ok` para los 4 y salida 0.
- [ ] **Paso 6: proponer commit** "feat(arte): herramientas de personajes del estilo nuevo y fuentes del artista".

### Tarea 2: la pelirroja de frente y rotada a 4 direcciones

**Archivos:**
- Crear: `tools/art/pelirroja.py` (cambio de paleta por material, portado de `flow_a.py`: rampas y tablas por
  capa).
- Crear: `art/source/pelirroja/rest_{south,east,north,west}.png` y `art/source/pelirroja/capas_south/*.png`.
- Test: `tools/art/test_tools.py` (agrega un caso).

**Interfaces:**
- Consume: `aseprite_io.export_layers`, `outline.outline`.
- Produce: `pelirroja.doll(hair="pelirrojo") -> np.ndarray` (64×64 RGBA, sin contorno) y
  `pelirroja.layers() -> dict[str, np.ndarray]` (`Cuerpo`, `Pelo`, `Ropa`). Las 4 vistas de reposo en
  `art/source/pelirroja/`.

- [ ] **Paso 1: test** `test_pelirroja_palette`: `doll()` no contiene ninguno de los 3 tonos del pelo negro
  original (`(22,20,26)`, `(43,39,48)`, `(74,69,80)`) y sí los 3 de la rampa `pelirrojo`
  (`(60,22,18)`, `(122,52,32)`, `(172,92,52)`). Correr → falla.
- [ ] **Paso 2: implementar** `doll` y `layers` con las rampas de `flow_a.py` (pelo `pelirrojo`; piel `clara`,
  vestido `negro`, delantal `lino` y lazo `rosa` sin cambios). Correr el test → pasa.
- [ ] **Paso 3: rotar.** Un job de `pl.py` con la vista sur (la misma rotación de 1 generación de la ronda 3) que
  da este, norte y oeste. Limpieza: `strip_outline` y paleta fijada a la de `doll()`. Guardar en
  `art/source/pelirroja/rest_*.png`.
- [ ] **Paso 4: revisión visual.** Hoja de las 4 vistas ampliada ×6 con contorno, publicada en la página de flujos
  (sección nueva "Gremio nuevo"). **Esperar el OK del usuario** antes de seguir; si una vista sale mal, se regenera
  solo esa.
- [ ] **Paso 5: proponer commit** "feat(arte): pelirroja en 4 direcciones sobre la maid del artista".

### Tarea 3: caminata pulida del maniquí femenino

**Archivos:**
- Crear: `tools/art/walk_pipeline.py` (poses clave de skeleton-v3 + PixMiniMax con paleta fija, varias tomas,
  elección por `score_walk`, `polish`, centrado sobre el idle; portado de `male_key.py`, `male_eval.py` y
  `build_male.py` de la ronda 3).
- Crear: `art/source/maniqui_f/walk_{dir}_{0..7}.png`, `art/source/maniqui_f/idle_{dir}_{0..3}.png`,
  `art/source/maniqui_f/picks.json`.

**Interfaces:**
- Consume: `pl.py`, `polish.polish`, `score_walk.score`, `idle_drop.idle`.
- Produce: `walk_pipeline.py <rest_dir> <out_dir> --takes 3` deja 8 frames de caminata y 4 de idle por dirección,
  y `picks.json` con el puntaje de cada toma y la elegida.

- [ ] **Paso 1: correr el flujo** sobre las 4 rotaciones del maniquí femenino pelado de la ronda 2 (copiadas del
  scratchpad a `art/source/maniqui_f/rest_*.png`). Unas 25 generaciones. Anotar el balance antes y después.
- [ ] **Paso 2: verificar** que `picks.json` tiene las 4 direcciones y que en cada una el puntaje elegido es el
  mínimo de sus tomas: `python -I -c` con un assert sobre el JSON.
- [ ] **Paso 3: revisión visual.** GIF de las 4 direcciones (×4) en la página. **Esperar el OK del usuario.**
- [ ] **Paso 4: proponer commit** "feat(arte): caminata e idle pulidos del maniquí femenino".

### Tarea 4: la pelirroja caminando, quieta y sentada, como hojas del kit

**Archivos:**
- Crear: `tools/art/build_character.py` (transferencia de ropa por dirección, limpieza de cabeza, paleta y
  contorno, poses de sentarse, hojas del kit y `.aseprite`).
- Crear: `assets/art/characters/pelirroja/pelirroja_{idle,walk,sit}.png` + `.json`.
- Crear: `art/source/pelirroja/pelirroja.aseprite`.

**Interfaces:**
- Consume: los frames de la Tarea 3, las vistas de la Tarea 2, `polish`, `outline`, `aseprite_io.write`.
- Produce: hojas del kit con este JSON (lo lee `kit_sprite.gd`):
  - `cell` `[64, 64]`, `rows` `["S", "E", "N", "W"]`, `anchor` `{"feet_x": 32, "sole_y": 47}`.
  - `idle`: 4 frames, `durations_ms` `[450, 220, 450, 220]`.
  - `walk`: 8 frames, 110 ms cada uno.
  - `sit`: 2 frames (pose y respiración de 1 px), `[600, 600]`. El ancla de `sit` es el punto del asiento:
    donde apoya la cadera, en x 32 y en la `sole_y` 47 del lienzo.
  - `.aseprite` con capas `Cuerpo`, `Pelo`, `Contorno` y etiquetas `walk_*`, `idle_*` y `sit_*`.

- [ ] **Paso 1: transferir la ropa.** `transfer-outfit-v2` por dirección con los 8 de caminata + 4 de idle, igual
  que en la ronda 2 (10 generaciones por dirección, 40 en total). Las instrucciones piden conservar cuerpo,
  pose y proporciones.
- [ ] **Paso 2: generar las poses de sentarse.** `edit-images-v2` con las 4 vistas de reposo en una llamada
  (10 generaciones): "sentada en un banco, mirando hacia <dir>, manos sobre las rodillas". Limpieza igual que la
  caminata. Como mucho un reintento por vista mala (10 más).
- [ ] **Paso 3: escribir el test de formato** en `tools/art/test_tools.py`: `test_kit_sheets`. Cada `.json` de
  `assets/art/characters/pelirroja/` tiene `cell == [64, 64]`, `rows == ["S","E","N","W"]` y el ancla 32/47.
  Cada `.png` mide `64 × frames` por `64 × 4`. La capa `Contorno` del `.aseprite` no tiene píxeles en el hueco
  entre piernas de `walk_south` frame 0. Correr → pasa.
- [ ] **Paso 4: revisión visual.** GIF de caminar, idle y sentarse en 4 direcciones en la página.
  **Esperar el OK del usuario.**
- [ ] **Paso 5: proponer commit** "feat(arte): pelirroja caminando, quieta y sentada en 4 direcciones".

### Tarea 5: maquetas del gremio para elegir estilo

**Archivos:**
- Crear: `tools/art/guild_pieces.py` (pide a PixelLab piezas sin luz: tiles de piso y pared, chimenea, mesa,
  sillas, 4 bancos (uno por orientación), candelabros, botellas, estantes, barril) y `tools/art/guild_mockup.py`
  (arma la sala de 480×270 y le suma una capa de luz: oscuridad global, charcos cálidos y halos).
- Crear: `art/source/gremio/piezas_{a,b,c}/*.png`, `art/source/gremio/maqueta_{a,b,c}.png` y su versión sin luz.

**Interfaces:**
- Produce: `guild_mockup.compose(pieces_dir: str, layout: dict, lights: list[dict], darkness: float) -> Image`.
  `layout` usa las mismas coordenadas de pantalla que la escena de Godot (Tarea 6), así el despiece es directo.

- [ ] **Paso 1: generar piezas** para 2 o 3 variantes que cambian piso (tablones o ladrillo), cantidad de luz y
  nivel de detalle. El clima se describe con texto: taberna cálida, velas, madera oscura, tapizado rojo, piso con
  detalle, muebles de esquinas redondeadas. Unas 60 generaciones en total.
- [ ] **Paso 2: componer** cada maqueta con y sin luz, con la pelirroja sentada en un banco. Verificar con un
  assert que la versión sin luz no tiene halos: sus colores salen solo de las piezas.
- [ ] **Paso 3: publicar** las maquetas en la página de flujos, en la sección "Gremio nuevo".
  **Esperar a que el equipo elija una.** La mesa queda marcada como provisoria (la diseña Sam).
- [ ] **Paso 4: proponer commit** "feat(arte): maquetas del gremio nuevo".

### Tarea 6: la escena de muestra con luz y control de oscuridad

**Archivos:**
- Modificar: `scripts/preview/art_preview.gd` (las poses de captura pasan a `func _shots() -> Array`, que
  devuelve `SHOTS`, para poder sobrescribirlas; nada más cambia).
- Crear: `scripts/tools/build_guild_preview_tileset.gd` → `tilesets/guild_preview.tres` (como
  `build_art_preview_tileset.gd`).
- Crear: `scenes/preview/guild_preview.tscn`, `scripts/preview/guild_preview.gd`,
  `scripts/preview/guild_preview_room.gd`, `assets/art/guild_preview/` (piezas de la maqueta elegida, sin luz).
- Modificar: `project.godot` (acciones `preview_darker` y `preview_lighter`: teclas `-` y `+`, y las del teclado
  numérico).
- Test: `scripts/test/assert_guild_preview.gd`.

**Interfaces:**
- Consume: `KitSpriteScript` con `sheet_prefix = "res://assets/art/characters/pelirroja/pelirroja_"` y
  `animations = ["idle", "walk", "sit"]`, `looping = ["idle", "walk", "sit"]`.
- Produce:
  - `guild_preview.gd extends "res://scripts/preview/art_preview.gd"`.
  - `@export var darkness: float = 0.6` y `func set_darkness(value: float) -> void`: lo deja en [0, 0.95],
    actualiza `$CanvasModulate.color` y la etiqueta `$UI/DarknessLabel` ("Oscuridad: 0.60").
    Paso de 0.05 por tecla.
  - Nodos: `Room/Tiles`, `Room/Things` (Y-sort, con `Player` y los 4 bancos), `Lights` (grupo
    `preview_lights`), `CanvasModulate`, `UI/DarknessLabel`.
  - Las luces usan `scripts/dungeon/torch_flicker.gd` y tienen `light_mask` que toca tiles, objetos y
    personajes. Cada llama lleva un halo `Sprite2D` con `CanvasItemMaterial` en modo aditivo.

- [ ] **Paso 1: test** `assert_guild_preview.gd` (mismo formato que `assert_art_preview.gd`):
  - escala entera mientras está abierta y restaurada al cerrar;
  - `Room/Things` con Y-sort;
  - existe `CanvasModulate` y hay al menos 3 luces en `preview_lights`, todas `PointLight2D` con
    `torch_flicker.gd`;
  - el sprite del jugador tiene `idle_*`, `walk_*` y `sit_*` en S, E, N y W, y una celda de 64×64;
  - `set_darkness(2.0)` deja 0.95; `set_darkness(-1.0)` deja 0.0; 30 pulsaciones de `preview_darker` desde 0.6
    dejan 0.95 y la etiqueta dice "Oscuridad: 0.95";
  - caminar al norte frena en la pared (mismo criterio que la vista previa de arte).
  
  Correr: `"$GODOT" --headless --path . -s scripts/test/assert_guild_preview.gd` → falla (no existe la escena).
- [ ] **Paso 2: construir el tileset y la escena** con las piezas de la maqueta elegida, en la misma
  distribución. Correr `"$GODOT" --headless --path . --import` y después el test → pasa.
- [ ] **Paso 3: correr** `assert_art_preview.gd` → sigue pasando (el cambio a `_shots()` no lo rompe).
- [ ] **Paso 4: proponer commit** "feat(preview): gremio nuevo con luz del motor y control de oscuridad".

### Tarea 7: sentarse en el banco

**Archivos:**
- Crear: `scenes/preview/bench.tscn`, `scripts/preview/bench.gd`.
- Modificar: `scripts/preview/preview_player.gd` (sentarse y levantarse; la vista previa de arte no los usa).
- Modificar: `scenes/preview/guild_preview.tscn` (4 bancos: mirando al S, E, N y O).
- Test: `scripts/test/assert_guild_preview.gd` (agrega casos).

**Interfaces:**
- Consume: `scripts/guild/guild_interactable.gd` (señal `interacted`, hijo `Hint`).
- Produce:
  - `bench.gd extends StaticBody2D`, con `@export var facing: String = "S"` y estos hijos:
    - `Seat` (`Marker2D`): dónde cae el ancla de `sit`.
    - `StandPoint` (`Marker2D`): punto libre donde queda parado al levantarse.
    - `Interact`: `Area2D` con `guild_interactable.gd` y su `Hint`.
  - `preview_player.gd` suma:
    - `var seated_bench: Node = null`;
    - `func sit(bench: Node, seat: Vector2, facing: String) -> void`;
    - `func stand() -> void`.
  - Sentado: no se mueve, apaga su `CollisionShape2D`, va a `seat` y juega `sit_<facing>`.
  - De pie: vuelve a `bench.StandPoint`, prende la colisión y queda en `idle_<facing>`.
  - Se levanta con una dirección **nueva** (una que no estaba apretada al sentarse) o con `interact`.
  - `bench.gd`, en `interacted`:
    - si `player.seated_bench == self`, llama a `stand()`;
    - si `player.seated_bench == null`, llama a `sit(...)`;
    - si está sentado en otro banco, no hace nada.
  - Un `interact` se consume una sola vez: el banco marca el evento como manejado con
    `get_viewport().set_input_as_handled()`.

- [ ] **Paso 1: tests nuevos** en `assert_guild_preview.gd`:
  - `sit_each_direction`: para cada banco, se pone al jugador en su `Interact` y se manda `interact`. Queda
    `seated_bench == banco`, posición == `Seat`, animación `sit_<facing>` sin `flip_h` y colisión apagada.
  - `stand_by_interact`: otro `interact` → `seated_bench == null`, posición == `StandPoint`, colisión prendida,
    `idle_<facing>`.
  - `stand_by_move`: sentado, `move_left` 3 frames → de pie en `StandPoint` y caminando.
  - `held_direction_does_not_stand` (Foco 3): con `move_up` apretado, `interact` → sigue sentado 10 frames.
    Después, `move_down` → se levanta.
  - `two_benches_one_seat` (Foco 1): dos bancos con `Interact` superpuestos en una escena armada en el test.
    `interact` → solo uno queda como `seated_bench`. Otro `interact` → de pie y no sentado en el otro.
  - `stand_point_is_free` (Foco 2): para cada banco, `PhysicsDirectSpaceState2D.intersect_shape` con la forma de
    los pies en `StandPoint` no toca ningún cuerpo.
  
  Correr → fallan.
- [ ] **Paso 2: implementar** `bench.gd`, `bench.tscn` (sprite del banco de la maqueta, colisión del mueble) y
  `sit`/`stand` en `preview_player.gd`. Ubicar los 4 bancos en la escena.
- [ ] **Paso 3: correr** `assert_guild_preview.gd` y `assert_art_preview.gd` → pasan.
- [ ] **Paso 4: proponer commit** "feat(preview): sentarse en los bancos del gremio en 4 direcciones".

### Tarea 8: capturas, página para el equipo y docs

**Archivos:**
- Modificar: `scripts/preview/guild_preview.gd` (`_shots()` con: vista general, sentada en cada banco, junto a la
  chimenea y en un rincón oscuro; más una captura con oscuridad 0.4 y otra con 0.8).
- Modificar: `scripts/test/README.md` (fila de `assert_guild_preview`), `AGENTS.md` §4 (las rutas nuevas de
  `scenes/preview/`, `scripts/preview/`, `tools/art/` y `art/source/`).

- [ ] **Paso 1: test** en `assert_guild_preview.gd`: `_shots()` devuelve al menos 6 poses y cada una tiene
  `[String, Vector2, Vector2]` (Foco 5: el modo captura se arma sin ventana).
- [ ] **Paso 2: capturar**:
  `"$GODOT" --path . res://scenes/preview/guild_preview.tscn -- --shot=<scratchpad>/gremio_shots`. Verificar que
  salen los PNG (480×270 y ×3).
- [ ] **Paso 3: publicar** las capturas y un GIF de sentarse en la página de flujos (sección "Gremio nuevo").
- [ ] **Paso 4: correr todos los tests headless** (receta de `scripts/test/README.md`) y reportar el resultado
  real; la base es 67/67 más `assert_scripts_parse` sin trackear.
- [ ] **Paso 5: proponer commit** "docs: muestra del gremio nuevo" y, con otro "sí", el PR a `dev`.
