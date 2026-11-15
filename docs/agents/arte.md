# Escenas, dirección visual y pixel art (AGENTS.md §38)

Parte del contrato de [`AGENTS.md`](../../AGENTS.md); los números de sección son los de ese documento.

---

# 38. Diseño de escenas

Preferir escenas pequeñas y reutilizables.

Ejemplos:

```text
player.tscn
enemy_base.tscn
slime.tscn
sword.tscn
arrow.tscn
room.tscn
exit.tscn
```

Una escena puede componerse de otras escenas cuando tenga sentido.

No duplicar estructuras enteras si pueden reutilizarse como componentes.

## 38.1. Dirección visual y estándar de pixel art

Base de esta sección: D4, D5, D7 y D15 en [`DECISIONES.md`](../../DECISIONES.md). Si algo de acá las contradice, gana `DECISIONES.md`.

### Dirección visual

- **Dos climas (D15)**: la mazmorra es lo más oscuro, con assets de estilo *Blasphemous* (solo el estilo, no la vista de costado) y gore y horror corporal permitidos; el pueblo y el gremio van más cálidos, como *Sea of Stars* pero más oscuros. La iluminación y los filtros llevan buena parte del clima.
- **Cámara aérea como la de *Sea of Stars***: el suelo se ve desde arriba, las paredes muestran su cara frontal y los personajes se ven de frente, de espaldas o de perfil. No es una vista cenital pura ni un side-scroller.
- **Paleta apagada (importante)**: colores desaturados y terrosos, sombras frías, pocos tonos por material. El saturado se reserva para lo que hay que leer de un vistazo: hit flash, VFX, telegrafía de ataque, peligros, botín e interactuables (D5). Todo asset nuevo se revisa contra esta paleta.
- **Lectura de beat 'em up**: los ataques se leen de perfil, con anticipación e impacto claros. Las entidades tienen que ordenarse por profundidad para que los grupos de enemigos se lean bien: en el escenario 3D lo resuelve la profundidad de la escena; mientras el juego siga en 2D, el orden es solo por `z_index`.
- La paleta exacta, la perspectiva y las reglas de iluminación están en [`BIBLIA_ARTE.md`](../../BIBLIA_ARTE.md) (D7). Todo el arte actual del entorno (cripta oscura, pueblo, enemigos del kit) es provisorio y se rehace al estilo de la protagonista.
- **Escenario 3D en tiempo real con aspecto de pixel art** (D5, cambio del 2026-11-15; cierra HD-2D): cámara ortográfica a 22°, 1 unidad = 1 px, que se mueve en píxeles enteros; luz en bandas, sombras de borde duro y contorno por profundidad. El TileMap queda como capa lógica y una capa 3D lo dibuja; ese cambio de arquitectura se acuerda antes de tocar `DungeonManager` y `Hondoval` (§44.10). Prototipo y medidas en `art/pruebas/escenario_3d/NOTA.md` (no versionado). En el escenario 3D queda suspendida la regla de 3 tonos por material.
- **Personajes en 3D renderizados a pixel art** (técnica de *Dead Cells*, D5, desde 2026-11-01): modelo low-poly por módulos en `art/source/`, render con `tools/art/rig3d.py` (Blender 5.2) con la cámara del juego, contorno de color y hoja de normales. En el escenario 3D son láminas que reciben luz con esas normales. Proceso en `art/guias/modelado.md` y `art/guias/animacion.md`.

### Tamaños

Decisión (D5): **la grilla del mundo es de 32×32 píxeles**, el mismo tamaño que los tiles de piso y pared (`DungeonGeometry.TILE_SIZE`). La protagonista (la maid) se renderiza en un lienzo de **80×80** con la figura de **~62 px** (prueba de escala del 2026-11-14, D5); la vegetación y los objetos se miden contra ella (árbol normal ~2,3 maids, ~140 px). El jugador del código todavía usa las hojas de 48×48 del aventurero (`player.tscn`); las de la maid ya están en `assets/art/characters/maid_op15/` (reposo, caminata y carrera, 8 cuadros, pies en x 40 y suelas en y 78).

| Tipo | Tamaño del sprite | Ocupa |
|---|---|---|
| Tiles de piso y pared | 32×32 | 1 tile |
| Protagonista y personajes humanoides | 80×80 (figura de ~62 px; pies en x 40, suelas en y 78) | ~1 tile de base |
| Enemigos comunes del kit actual (provisorios) | 64×64 o 48×48 | ~1 tile de base |
| Objetos (cofre, salida, items) | sobre la grilla de 32 | 1 tile |
| Enemigos grandes (troll, gigante, ogro) | 96×96 | 2×2 tiles de base |
| Jefes (dragón, etc.) | 128×128 o más | 3×3 a 4×4 tiles |

Los tamaños grandes no tienen que ser cuadrados (un dragón puede ser 128×80).

### Reglas

- **Misma densidad de píxel en todo el juego.** Una criatura grande se dibuja directamente más grande; nunca se escala un sprite a ×2.
- **Nunca escalar a factores no enteros** (×1.5, etc.): deforma los píxeles.
- **Silueta primero.** En la figura chibi entran cara (ojos de 1–2 px, expresión simple), manos, ropa y equipo; no entran texto, joyas chicas ni dedos individuales. Cada enemigo tiene que reconocerse por su forma y colores.
- **Contorno de color de 1 px (sel-out) en su propia capa** en los personajes, para poder ocultarlo o cambiarle el color; sin línea en el hueco entre las piernas, de frente y de espaldas (detalle en `BIBLIA_ARTE.md` §4).
- **Capas:** ropa, pelo e ítems van en capas que se ponen y se sacan, y cada personaje se exporta a `.aseprite` con capas y etiquetas por animación y dirección.
- **Formato:** PNG con transparencia, sin suavizado. Varias poses o frames del mismo personaje van juntos en una hoja (spritesheet) con celdas del mismo tamaño.

### Animaciones (por personaje)

| Animación | Frames |
|---|---|
| Idle | 8 (la maid; 4 en los personajes viejos) |
| Caminar y correr | 8 |
| Ataque | 3–5 |

Las animaciones salen de mocap retargeteado al rig, nunca animadas a mano (D7).

Cada animación se dibuja en **4 direcciones** (abajo, arriba, izquierda y derecha), sin espejar con `flip_h`: los personajes de lado con cámara cenital lo exigen (D4). Las criaturas grandes pueden usar menos frames o armarse por partes (cabeza, cuerpo, alas) animadas en Godot, que es más barato que dibujar cada frame.

### Criaturas grandes en el juego

- Cada criatura es una escena que hereda de `enemy_base.tscn` (los jefes van como escenas aparte, §26) con su propio `EnemyData` y su propio arte.
- **Las colisiones no siguen al dibujo**: `Hurtbox` y `Hitbox` se dimensionan aparte. Un dragón puede tener la zona vulnerable en el cuerpo y cajas de ataque en la cabeza o la cola.
- **Las puertas miden 1 tile (32 px)**: un enemigo de 64 px no pasa entre zonas. Los enemigos grandes aparecen y pelean en su propia zona.
- Una celda mide 15×9 tiles (480×288 px, una pantalla): un jefe de 128 px entra, pero los jefes necesitan una zona BOSS de varias celdas.

### Pantalla

El juego dibuja a 480×270 (unos 15×8 tiles de 32) y se escala a la ventana con **escala entera** (`stretch/mode = viewport`, `scale_mode = integer`, ventana de 1920×1080 = ×4). Si la pantalla no da para ×4, usa el mayor entero que entra, con bordes.
