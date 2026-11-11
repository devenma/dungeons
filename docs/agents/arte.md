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
- **Lectura de beat 'em up**: los ataques se leen de perfil, con anticipación e impacto claros. Las entidades deberían ordenarse por profundidad (Y) para que los grupos de enemigos se lean bien. Pendiente: hoy el orden es solo por `z_index`.
- La paleta exacta, la perspectiva y las reglas de iluminación están en [`BIBLIA_ARTE.md`](../../BIBLIA_ARTE.md) (D7). El entorno de la mazmorra sigue siendo la cripta oscura hasta que se rehaga; los personajes siguen el estilo del NPC base del artista (2026-10-29). HD-2D se decide después (D5).
- **Personajes en 3D renderizados a pixel art** (técnica de *Dead Cells*, D5, desde 2026-11-01): modelo low-poly por módulos en `art/source/`, render con `tools/art/rig3d.py` (Blender 5.2) a 40 px con la cámara del juego, contorno de color y normal map. Proceso en `art/guias/modelado.md` y `art/guias/animacion.md`.

### Tamaños

Decisión (D5): **la grilla del mundo es de 32×32 píxeles**, el mismo tamaño que los tiles de piso y pared (`DungeonGeometry.TILE_SIZE`). Los personajes se dibujan en un lienzo de 64×64, chibi, sobre el maniquí en capas del artista. El código todavía usa hojas de 48×48 para el jugador y los NPCs; pasan a 64×64 cuando entren los personajes nuevos.

| Tipo | Tamaño del sprite | Ocupa |
|---|---|---|
| Tiles de piso y pared | 32×32 | 1 tile |
| Jugador, NPCs, enemigos comunes (slime, goblin) | 64×64 (figura de ~40 px, máximo 42 sin contar adornos de la cabeza; pies en x 32, suelas en y 47) | ~1 tile de base |
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

### Animaciones (por personaje de 64×64)

| Animación | Frames |
|---|---|
| Idle | 4 |
| Caminar | 8 |
| Ataque | 3–5 |

Cada animación se dibuja en **4 direcciones** (abajo, arriba, izquierda y derecha), sin espejar con `flip_h`: los personajes de lado con cámara cenital lo exigen (D4). Las criaturas grandes pueden usar menos frames o armarse por partes (cabeza, cuerpo, alas) animadas en Godot, que es más barato que dibujar cada frame.

### Criaturas grandes en el juego

- Cada criatura es una escena que hereda de `enemy_base.tscn` (los jefes van como escenas aparte, §26) con su propio `EnemyData` y su propio arte.
- **Las colisiones no siguen al dibujo**: `Hurtbox` y `Hitbox` se dimensionan aparte. Un dragón puede tener la zona vulnerable en el cuerpo y cajas de ataque en la cabeza o la cola.
- **Las puertas miden 1 tile (32 px)**: un enemigo de 64 px no pasa entre zonas. Los enemigos grandes aparecen y pelean en su propia zona.
- Una celda mide 15×9 tiles (480×288 px, una pantalla): un jefe de 128 px entra, pero los jefes necesitan una zona BOSS de varias celdas.

### Pantalla

El juego dibuja a 480×270 (unos 15×8 tiles de 32) y se escala a la ventana con **escala entera** (`stretch/mode = viewport`, `scale_mode = integer`, ventana de 1920×1080 = ×4). Si la pantalla no da para ×4, usa el mayor entero que entra, con bordes.
