# PLAN — De hoy al MVP y al juego completo

Este documento **ordena el trabajo**; no decide diseño. El diseño está en [`DECISIONES.md`](DECISIONES.md), la
arquitectura en [`AGENTS.md`](AGENTS.md) y el detalle de cada feature en [`FEATURES.md`](FEATURES.md). Si este plan
los contradice, ganan ellos y se corrige el plan.

Cada sesión de trabajo empieza leyendo el **Estado** y termina actualizándolo (§7).

## 0. Estado

| | |
|---|---|
| Actualizado | 2026-11-15 |
| Hito activo | **H0 — Ordenar la casa** |
| Último avance | 2026-11-15: el escenario pasa a 3D en tiempo real. Tres rondas de prueba fuera del juego (`art/pruebas/escenario_3d/`, ver `NOTA.md`): una sala de la cripta y una parcela exterior, sin temblor con la cámara en píxeles enteros, la maid tapada por el escenario y con luz por normales, vegetación medida contra ella. El usuario aprobó luz, tamaño y técnica: D5 y D15 escritos en `DECISIONES.md` (sin commit: el clasificador bloqueó el commit). La cabeza nueva pasó a `art/source/modulos/` (`op15_cara_10`, `op15_pelo_10`) y la receta real de la maid suma la colisión de brazos; hojas nuevas en `art/pruebas/maid_op15/receta_real/`, todavía no en el juego. 2026-11-14: prueba de escala en el juego real (`art/pruebas/escala/`). |
| Siguiente paso | (1) Que el usuario mire las hojas nuevas de la maid (`art/pruebas/maid_op15/receta_real/`) y, con su sí, copiarlas a `assets/art/characters/maid_op15/`. (2) Commits con su visto bueno: `PLAN.md`, `DECISIONES.md`, cabeza en `art/source` y hojas. (3) Cerrar H0: `AGENTS.md` §38.1 (escala y escenario 3D) y `FEATURES.md` §1, push y PR a `dev`. (4) Integrar el escenario 3D al juego: el TileMap queda como capa lógica y una capa 3D dibuja; es un cambio de arquitectura y se explica antes de tocar `DungeonManager` y `Hondoval` (AGENTS §44.10). |
| Bloqueos | Ninguno técnico. Los commits desde la sesión los bloquea el clasificador de permisos: los corre el usuario o da permiso. Pasada final anotada en `art/pruebas/escenario_3d/NOTA.md` (flores, punta del pino, troncos, contornos sobre fondo oscuro, pared sur que tapa los pies, VFX 2D sin profundidad). |

## 1. Dónde estamos (2026-11-10)

- **El loop del MVP ya funciona con arte provisorio** en `dev`: Hondoval con tiendas y día/noche, San Ulmo de 3
  pisos, bestiario, élite, la Madre de la Fosa, muerte con piedra azul, mejoras permanentes, diálogo y cierre.
- **Desde el 2026-10-29 casi todo el esfuerzo fue al flujo de arte** (personajes 3D renderizados a pixel art). Hay
  una protagonista con reposo, caminata y carrera, módulos con slot, tela animada y panel de ajuste. Todavía **no está
  en el juego real**: `player.tscn` sigue con el aventurero de 48×48 y no hay hoja de ataque.
- **Todo el arte actual es provisorio** (cripta oscura, pueblo de PixelLab, enemigos del kit V3): se rehace al estilo
  de la protagonista. El estilo del entorno no está definido; las dos pruebas de la zona de pruebas no convencieron.
- **Escala sin resolver:** la maid mide ~59 px en un lienzo de 80×80; el mundo está pensado para figuras de ~40 px
  sobre tiles de 32, con puertas de 1 tile y sin orden por Y.
- **Ramas:** `main` ← `dev` (90 commits adelante) ← `feat/estilo-3d-pixel` (59 adelante, 20 sin push), más cambios
  sin commit. D27 (equipo por slots) está en código y en `DECISIONES.md` como propuesta. `AGENTS.md` §38.1 todavía habla de 40 px.

El riesgo principal no es técnico: es que el flujo de arte siga absorbiendo las sesiones mientras el juego no avanza.

## 2. Reglas de avance

1. **Dos carriles, uno en primer plano.** Arte y juego avanzan en paralelo. Cuando hay un proceso largo de Blender o
   agentes, en primer plano va una tarea de juego que no toque esos archivos.
2. **El juego no espera al arte.** Toda mecánica entra con arte provisorio.
3. **Primero una rebanada, después producción.** No se producen assets en cantidad hasta que el equipo apruebe una
   pantalla completa en el estilo nuevo (H2).
4. **Cada tanda de arte termina dentro del juego real**, no en `art/pruebas/`. Recién ahí empieza la siguiente.
5. **Exploraciones con tope:** 3 rondas por tema. A la tercera se elige entre lo que hay o se anota como decisión
   abierta (§6) y se sigue con otra cosa.
6. **Las decisiones se cierran en la puerta del hito que las necesita**, no antes. Las abiertas están en §6.
7. **Tests:** baja prioridad mientras se define. Al cerrar cada hito se corre la suite completa y se actualiza la base.
8. **Git:** una rama por hito desde `dev`, PR a `dev`, y `dev` pasa a `main` al cerrar cada hito. Nada se commitea ni
   se publica sin el visto bueno puntual (`AGENTS.md` §44.3).
9. **No rehacer lo que funciona:** generador, protocolo de daño, perfil y expedición se extienden, no se reescriben.

## 3. Hitos hasta el MVP

El MVP es el de D17: `pueblo → 1 dungeon de 3 pisos → jefe → volver con loot → comprar 1 mejora → repetir`, interno,
**con todo lo visible en el estilo nuevo**. Sin fechas: el costo de arte se mide en H2 y recién ahí se estima.

### H0 — Ordenar la casa (tamaño: chico)

- [ ] Commits por punto de lo pendiente (ya están las hojas de la maid, `89fc495`, y el equipo por slots, `3c9f5a5`): escenas de prueba, `rush_ghost`,
      `sombra.py`. Push de la rama.
- [ ] `DECISIONES.md`: D27 (equipo por slots) ya está como propuesta (`464b7f3`); falta registrar el tamaño de figura variable (D5), "sin animación a mano,
      solo mocap" (D7) y el reemplazo del estilo oscuro como propuesta (D15).
- [ ] Alinear `AGENTS.md` §38.1 y §31 (que apunte a este plan) y `FEATURES.md` §1.
- [ ] Una corrida completa de tests para saber desde dónde se parte.
- [ ] PR `feat/estilo-3d-pixel` → `dev`.

**Salida:** árbol limpio, rama publicada, documentos sin contradicciones.

### H1 — La protagonista en el juego real (mediano)

Carril de juego, con arte provisorio en todo lo demás.

- [x] **Prueba de escala** (primera tarea, decide el resto): la maid como jugador en una sala de la cripta y en
      Hondoval. Colisión por los pies, puertas, cámara y orden por Y (hoy solo hay `z_index`).
- [ ] Combo de espada de 3 golpes por mocap (Quaternius UAL2), sincronizado con las fases de `SwingData`.
- [ ] Correr y dash (D26); el dash reemplaza a `RollComponent`. Números de partida: los de la rodada de D24.
- [ ] Animaciones mínimas que faltan: recibir golpe, morir, tomar el vial, disparar (arco) y lanzar (bastón).
- [ ] Equipo por slots (D27): terminar el corte mínimo que ya está empezado; sin loot nuevo.

**Salida:** una expedición completa de San Ulmo jugada con la maid, grabada en video para el equipo.
**Cierra:** escala del mundo, números de correr y dash.

### H2 — Rebanada de estilo (mediano, con tope de rondas)

Una sola pantalla de cada clima (D15) con calidad final, dentro del juego:

- [ ] Una sala de la cripta: tiles, pared, puerta, antorcha, 3 o 4 objetos y la luz sobre los personajes.
- [ ] Un tramo de Hondoval: suelo, una fachada, vegetación.
- [ ] Un enemigo humanoide sobre el maniquí (errante) y una criatura (rata), para medir los dos caminos.
- [ ] Un NPC armado con módulos, para probar que una variante sale barata.

**Salida:** el equipo dice que sí a una captura y un video; `BIBLIA_ARTE.md` reescrita; tabla de costo por tipo de
asset (horas y generaciones de PixelLab) y, con ella, la estimación de H3.
**Cierra:** estilo del entorno, técnica de luz (HD-2D o no), camino para criaturas no humanoides.

### H3 — MVP en el estilo nuevo (grande)

**Carril de arte**, por tandas y en este orden; cada una se integra antes de seguir:

1. Cripta: atlas, objetos, ambiente, cofre, altar, bloque, escaleras (el `.tres` sigue saliendo del generador).
2. Bestiario: errante, reptante, rata, escupebilis, guardia, cultista y el Cosido.
3. La Madre de la Fosa (fija, 3 poses).
4. Hondoval: exterior, gremio y los interiores.
5. Los 7 NPCs, por módulos.
6. UI, íconos y efectos que desentonen.

**Carril de juego**, en paralelo:

- [ ] Bloqueo, parry y ataque fuerte (D26).
- [ ] Flujo y presentación de `FEATURES.md` P1: menú principal, pantalla de muerte con resumen, prompts de
      interacción (teclado y gamepad), aviso de puertas trabadas, fundido entre pisos, opciones y su guardado.
- [ ] Pasada de balance con notas de prueba de juego.

**Salida:** no queda arte provisorio en el loop.

### H4 — MVP cerrado (mediano)

- [ ] Audio: 3 temas (pueblo, cripta, jefe) y SFX definitivos (D18).
- [ ] Textos finales ES/EN de San Ulmo y del pueblo.
- [ ] Build de Windows exportada; prueba en Steam Deck si hay una a mano.
- [ ] Prueba con 3 a 5 personas de fuera del equipo y una ronda de arreglos.
- [ ] Tests al día, documentos alineados, `dev` → `main`, etiqueta `v0.1`.

**Salida:** alguien que no conoce el juego completa el loop sin ayuda.

## 4. Puerta después del MVP

Con el MVP en la mano y los costos medidos, el equipo decide el alcance del juego completo (§6, filas marcadas
"puerta"). Hasta entonces esas preguntas no frenan nada.

## 5. Del MVP al juego completo

| Hito | Qué es | Salida |
|---|---|---|
| **H5 — Profundidad** | Kits de habilidad completos y maestría (D12), efectos de estado, mejoras de expedición (D11), variantes y rareza de armas, loot de equipo si se confirma, pathfinding, trampas, minimapa, atajo (D3), oleadas. | Dos builds distintas son viables en San Ulmo. |
| **H6 — Segundo dungeon** | Las Cloacas de Hondoval: bioma, enemigos, jefe, 4 pisos y su tramo de historia. Es la prueba del flujo de contenido. | Costo real de un dungeon medido; con eso se fecha el resto. |
| **H7 — Demo pública** (si se aprueba) | San Ulmo pulido como demo, página de tienda, tráiler corto. | Interés medido antes de invertir en el tercer dungeon. |
| **H8 — Contenido final** | La Mina del Rey, cierre de la historia, pueblo completo (conversaciones largas; granja o relaciones solo si se aprueban). | El juego se termina de principio a fin. |
| **H9 — Beta y salida** | Balance, inglés completo, opciones y accesibilidad, rendimiento, versionado del guardado, QA y lanzamiento. | Publicado. |

## 6. Decisiones abiertas

| Decisión | Se necesita en | Recomendación |
|---|---|---|
| Escala: maid de ~62 px (59 antes de la frente alta del 2026-11-12) sobre tiles de 32 y 480×270 | H1 | Cerrada el 2026-11-15 en D5: la maid queda en ~62 px y la vegetación se mide contra ella (árbol normal ~2,3 maids). Si el combate queda apretado, 640×360 antes que achicarla. |
| ¿La maid es la protagonista? (D13) | H1 | Sí; este plan lo asume. |
| Correr y dash: botón, coste, i-frames (D26) | H1 | Correr manteniendo el botón, sin coste, se corta al atacar o recibir un golpe. Dash con los números de la rodada. |
| Alcance de D27 (equipo por slots) en el MVP | H1 | Solo ponerse y sacarse piezas con stats simples en el gremio. |
| Bloqueo y parry: ventanas y stamina (D26) | H3 | Reusar el camino del `Guard` de los enemigos. |
| "Tú" o "vos" en los textos (D16) | H4 | Elegir uno y pasarlo por el glosario. |
| Quién hace el audio (D18) | H4 | Packs libres para SFX; música encargada o generada, a decidir. |
| Cantidad de dungeons | puerta | Tres, los del lore: San Ulmo, Cloacas, Mina del Rey. |
| Loot tipo Diablo | puerta | Decidir después de jugar el MVP con el equipo mínimo de D27. |
| Segunda jugable (D13) | puerta | No antes de H8. |
| Granja, crafting, relaciones (D2) | puerta | Fuera, salvo que el MVP muestre que el pueblo queda vacío. |
| Demo pública y plataformas (D8, D17) | puerta | Demo en PC antes del tercer dungeon. |

## 7. Protocolo de sesión

**Al empezar**
1. Leer §0. Si el pedido del día es del hito activo, seguir por la primera tarea sin marcar.
2. Si el pedido es de otro hito o no está en el plan, hacerlo igual y decir en una línea a qué hito sirve o que queda
   fuera del plan.
3. Si la tarea necesita una decisión abierta de §6, usar la recomendación como valor provisorio y avisarlo.

**Al terminar**
1. Marcar lo hecho en §3 y actualizar §0 (fecha, último avance, siguiente paso, bloqueos).
2. Si se cerró una feature, actualizar `FEATURES.md`; si se tomó una decisión, `DECISIONES.md` y sacarla de §6.
3. Si se cumplió la salida del hito: correr la suite, proponer el PR y pasar el hito activo al siguiente.

**Señales para parar y replantear**
- Tres sesiones seguidas de arte sin que nada nuevo llegue al juego real.
- Una exploración que pasó las 3 rondas.
- Un hito cuyo alcance creció: se parte en dos en vez de estirarlo.
