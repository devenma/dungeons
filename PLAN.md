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
| Último avance | 2026-11-15 (tarde): look-dev del escenario 3D cerrado, todo fuera del juego (`art/pruebas/escenario_3d/`, `NOTA.md`). El usuario eligió el sombreado B suave con capa de ambiente de tarde y noche, cristales con refracción y la falda con viento por shader de máscara (D5); los efectos de pantalla quedan disponibles sin decidir. Hechos: pasto con oclusión, copas irregulares, cristal, estandartes, banco de materiales, vivero y parcela con variantes; temblor medido (SSAO apagada). Cambio en `tools/art`: clave "viento" de la tela animada (md5 de la caminata igual, `test_tools` OK), sin commit. Propuesta para integrar el escenario 3D: `art/pruebas/escenario_3d/propuesta_integracion_3d.md`. Paquete para el equipo en `art/pruebas/escenario_3d/lookdev_r3/para_el_equipo/`. |
| Siguiente paso | (1) Cerrar H0 sin tocar arte: commits de `tools/art` y `art/guias/modelado.md`, `AGENTS.md` §38.1 y `FEATURES.md` §1, suite de tests, push y PR a `dev`. (2) Responder las 3 preguntas de la propuesta de integración y recién ahí tocar `DungeonManager` (AGENTS §44.10). Sin más rondas de look-dev. |
| Bloqueos | Ninguno técnico. Falta aprobar `propuesta_integracion_3d.md`. Pasada final del look-dev anotada en `NOTA.md`. |

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

- [x] Commits por punto de lo pendiente (ya están las hojas de la maid, `89fc495`, y el equipo por slots, `3c9f5a5`): escenas de prueba, `rush_ghost`,
      `sombra.py`. Push de la rama.
- [x] `DECISIONES.md`: D27 (equipo por slots) ya está como propuesta (`464b7f3`); falta registrar el tamaño de figura variable (D5), "sin animación a mano,
      solo mocap" (D7) y el reemplazo del estilo oscuro como propuesta (D15).
- [x] Alinear `AGENTS.md` §38.1 y §31 (que apunte a este plan) y `FEATURES.md` §1.
- [x] Una corrida completa de tests para saber desde dónde se parte (2026-11-15: 71/71).
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
