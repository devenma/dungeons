# DECISIONES — Dirección de diseño v2

**Estado:** dirección aprobada el 2026-10-24. D1–D4 (bloqueantes), D5, D12 y D19 están cerradas; el resto son
propuestas vigentes hasta que el equipo las revise.
**Fecha:** 2026-10-24.
**Revisión 2:** 2026-10-24, tras el merge del PR #6 (`feat/p0-combate-y-start`). Ver *Estado del repo*.
**Revisión 3:** 2026-10-24. Se suma el maná como segundo recurso (D19) y los obstáculos movibles (D20).
**Revisión 4:** 2026-10-24. D5 pasa a decidida (32 px de tile, personajes de 48×48, entorno "cripta
suave") y se crea la biblia de arte (D7).
**Revisión 5:** 2026-10-25. Se suman las propuestas del slice de San Ulmo: jefe (D21), techo de pisos y
`DungeonData` (D22), sala de cura con precio (D23) y números de sensación de combate (D24).
**Alcance:** define el juego que queremos hacer. Las decisiones cerradas acá mandan sobre `AGENTS.md`,
`README.md` y `FEATURES.md` en todo lo que contradigan; esos documentos se actualizan **después** de la
validación, no antes.

## Cómo leer este documento

Cada decisión tiene un ID (`D1`…`D24`) para poder citarla en la discusión.

| Marca | Significado |
|---|---|
| **[PROPUESTA]** | Recomendación técnica. No vinculante hasta que el equipo la apruebe. |
| **[DECIDIDO]** | Decisión tomada por el equipo. Se propaga a los documentos y al código. |
| **[CONFLICTO]** | Choca con una decisión previa registrada en Engram o con el código actual. Hay que resolverlo, no ignorarlo. |
| **[BLOQUEANTE]** | Sin esto no se puede empezar el siguiente hito. |
| **[IMPACTO]** | Consecuencia concreta en el código que ya existe. |

Las decisiones **D1 a D4** son las que definen qué juego hacemos y bloquean el resto. Las demás se pueden
dejar abiertas sin frenar el trabajo.

---

## Estado del repo al alinear (2026-10-24)

El PR #6 (`feat/p0-combate-y-start`) ya está en `main` e implementó casi todo el P0 que este documento
asumía pendiente:

| Landed | Efecto |
|---|---|
| Knockback (`KnockbackComponent`, decae en 0.2 s) | **D4** ya no arranca de cero |
| I-frames del jugador (0.5 s) + parpadeo | **D4** |
| Hit flash (`HitFlash`) en jugador y enemigos | **D4** |
| Menú de pausa (Esc: Resume / Quit) | Cierra un P0 y habilita una build jugable |
| Tope de la zona START (`start_zone_max_cells`, 2×1 celdas) | Hace el testeo menos tedioso |
| Tintes de piso restaurados | 27 tests headless, todos verdes |

Lo que **no** cambió: todas las decisiones de este documento siguen abiertas. Nada del P0 tocó la capa de
estado, el pueblo ni la economía. Sí tocó el generador (tope de START) y dejó a la vista el bug de solape.

Sí apareció deuda nueva del P0 que **condiciona D3** (ver *Deuda nueva del P0* más abajo).

---

## Contexto: la tensión de fondo

Tres documentos describen hoy un juego distinto del que queremos:

- `README.md` — *Binding of Isaac*, *Enter the Gungeon*, *Dead Cells*. Roguelite puro.
- `AGENTS.md` — roguelite sin historia, sin pueblo, con meta-progresión especulativa.
- `FEATURES.md` — backlog ordenado como roguelite (meta-progresión y hub en P3).

La dirección nueva es **Moonlighter + Stardew Valley** en lo jugable, con exploración tipo Zelda, cámara
cenital y paleta apagada; la atmósfera es *Fear & Hunger* (D15). Eso empuja hacia un mundo persistente y salas hechas a mano, mientras el código actual es
procedural y borra todo al morir. **D1 a D3 resuelven cuánto de cada lado tomamos.**

Auditoría de Engram (68 sesiones): no hay ninguna traza de esta dirección creativa. Todo lo registrado
asume el roguelite anterior.

---

## AHORA — definen qué juego hacemos

### D1 — ¿Sigue siendo roguelite? ¿Qué pasa al morir? [DECIDIDO] [BLOQUEANTE]

**Propuesta:** estilo Moonlighter. Se pierde la expedición, no el progreso.

Dos capas de estado, explícitas y separadas:

| Capa | Vive en | Contenido | Persiste |
|---|---|---|---|
| Perfil | `ProfileState` (`user://`) | Oro bancado, almacén del guild, armas aseguradas, desbloqueos | Sí, entre sesiones |
| Expedición | `RunManager` | Seed del dungeon, piso actual, loot de la mochila, oro encima y armas recogidas en esta expedición | No, muere con la expedición |

Al morir: volvés al guild, perdés lo no asegurado, se re-rollea la seed del dungeon. El oro bancado, el
almacén, las armas aseguradas y los desbloqueos quedan.

**Regla del equipo (2026-10-24), manda sobre lo anterior:**
- Hay **inventario y mucho loot**.
- **Morir sin piedra azul:** se pierde todo lo de la expedición, es decir, el loot de la mochila y lo que
  se agarró o equipó durante la expedición. Se conserva lo guardado en el guild: oro bancado, almacén y
  desbloqueos.
- **Piedra azul:** es un consumible. Si morís con una en la mochila, se gasta y te teletransporta al guild
  **con** el loot. Sale como loot y más adelante se puede comprar. Es el "objeto de retorno" de D10.
  También se puede ofrecer en el altar de cura (D23), y el jefe suelta una (D21).

**[IMPACTO]** Hecho. `DungeonManager._on_player_died()` llama a `_return_to_guild()`: si hay piedra azul
en la mochila la gasta, conserva mochila y oro encima y asegura en `ProfileState` las armas recogidas; si
no, vacía la mochila. En los dos casos `RunManager.start_new_run()` re-rollea la seed y arranca con las
armas del perfil, y el perfil se guarda en `user://profile.json`. En el guild, el cofre del almacén abre
la mochila y el almacén: se pasan objetos en las dos direcciones (pila o de a uno) y "Guardar todo" deposita
la mochila y banca el oro. El generador no se tocó.

**Alternativas descartadas:**
- *Perder todo menos los desbloqueos* (roguelite clásico): pelea con el pueblo persistente y con Stardew.
- *Sin muerte permanente*: deja el juego sin tensión y tira a la basura la arquitectura de runs con seed,
  que es el sistema más sólido que tenemos.

---

### D2 — ¿Qué tomamos de Stardew Valley? [DECIDIDO] [BLOQUEANTE]

**Propuesta:** pueblo con NPCs y ciclo día/noche. Granja y crafting, más adelante.

Pero con una corrección: **el pueblo necesita una tienda desde el día uno.** El loop de Moonlighter es
tienda de día, dungeon de noche. Si cambiamos la tienda por un pueblo de Stardew, el oro no tiene sink y el
loop se rompe. La tienda además *es* la respuesta a D11.

Alcance mínimo del pueblo:
- 3–4 NPCs con diálogo fijo (sin medidores de relación).
- Un vendedor: vender loot, comprar equipo.
- Ciclo día/noche como **fases discretas**, no iluminación dinámica.

**Regla del equipo (2026-10-24):** el juego **arranca en un guild**, que es el hub: de ahí salen las
expediciones y ahí se vuelve. Tiene el almacén y la tienda.

**[IMPACTO]** El guild mínimo existe: `scenes/guild/guild.tscn` (`World/Guild` en `main.tscn`), con el
cofre del almacén y la puerta de expedición. El juego arranca ahí y se vuelve ahí al morir. La taberna
huérfana (`scenes/hub/guild_tavern.tscn`) se eliminó el 2026-10-24. Faltan la tienda, los NPCs y un
`WorldClock` con `DAY/NIGHT` que avance al volver del dungeon. Sin luces dinámicas ni ciclo continuo.

**Costo que hay que asumir:** los NPCs son lo más caro por hora de gameplay que existe. Granja y crafting
multiplican sistemas (inventario, recetas, cultivos, calendario) y no los necesitamos para validar el loop.
El calendario, al principio, es un contador de días.

---

### D3 — ¿Cómo combinamos exploración tipo Zelda con dungeon procedural? [DECIDIDO] [BLOQUEANTE]

**Propuesta:** mundo exterior fijo + dungeons procedurales armados con salas diseñadas a mano.

Concreto y reutilizando lo que hay:
- El **grid-merging** sigue definiendo la topología del piso y los tipos de zona.
- El **interior de cada zona** deja de generarse desde cero: sale de un pool de plantillas
  (`scenes/rooms/`) por tipo y tamaño de zona. La seed elige la plantilla.
- El gating es por **llaves y puertas cerradas**, más un objeto que abre un atajo.

Eso da la sensación Zelda de "sala diseñada" sin perder el orden procedural.

**[CONFLICTO]** La validación actual del generador solo verifica que START→EXIT sea alcanzable (BFS). Con
llaves, el problema pasa a ser de **solvabilidad**: la llave tiene que estar antes que su puerta en la
ruta. Esa validación va en el generador, no en runtime. Es la parte no trivial de esta decisión.

**[PRERREQUISITO, resuelto]** Antes de meter plantillas de sala había que arreglar dos cosas del generador.
Ya están arregladas: `_merge_cells` corta la grilla en rectángulos exactos (cortes guillotina) y
`FloorData.min_zone_cells` fija el tamaño mínimo; `validate_layout()` lo verifica:

1. **`_merge_cells` producía rectángulos que se solapaban.** La zona era el *bounding box* de las celdas que
   ganó, y el paso de asignación greedy expandía ese bbox sin verificar celdas ajenas: ~5% de los
   layouts tenían celdas pintadas dos veces. Con plantillas de sala esto deja de ser cosmético: una
   plantilla necesita un rectángulo exacto. Lo cubre `assert_zone_partition`.
2. **Una zona de 1 celda (8×8 tiles = 256×256 px) era más chica que el viewport (480×270 px).** La cámara
   no puede limitar por debajo del viewport y se veían las zonas vecinas. Primero se subió el mínimo a
   2×2 celdas; después, por feedback del equipo ("las salas son muy grandes, mucha caminata"), cada
   celda pasó a ser **una pantalla de sala** (15×9 tiles = 480×288 px) con mínimo 1×1, y la cámara se
   desliza a la zona nueva al cruzar una puerta en vez de saltar. Con la segunda prueba de juego (las de
   2×1 y más "se sienten muy grandes aún") todas las zonas quedan de una pantalla
   (`FloorData.min_size_zones_only`): la grilla se elige con tantas celdas como zonas.

Con esos dos arreglos la topología quedó confiable y el pool de plantillas es una capa encima, no una
reescritura.

**Alternativas descartadas:**
- *Puzzles*: requieren scripting bespoke por sala; caros. Dejarlos para cuando el loop esté cerrado.
- *Todo a mano*: tira a la basura la Fase 3, el sistema más grande implementado.

---

**Estado (2026-10-26, rama `feat/slice-v2`):** primer corte. Las plantillas son recursos (`RoomTemplate`, el bloque
central de 9×3 de cada sala COMBAT) en vez de escenas, porque las salas son de una pantalla y el anillo de piso libre
garantiza que nada tapa una puerta. Hay una llave por piso (40-50 %) para una bóveda; el atajo todavía no existe.

### D4 — ¿Cuánto beat 'em up? [DECIDIDO] [BLOQUEANTE]

**Propuesta:** combos de 3 golpes, hit-stop y knockback fuerte. Sin agarres por ahora.

**Dirección del equipo (2026-10-24):** el juego es un **mazmorreo en tiempo real, estilo ARPG**: oscuro,
duro y pesado. "Pesado" se traduce en anticipaciones largas, impactos con hit-stop y poco perdón al errar.

El punto clave: **la mayor parte de esto ya está hecho.** El PR #6 implementó el feel base:

| Pieza | Estado al 2026-10-24 |
|---|---|
| Knockback | **Hecho**: `KnockbackComponent`, decae en 0.2 s, stagger |
| I-frames del jugador | **Hecho**: 0.5 s en `HealthComponent.invulnerability_seconds` |
| Hit flash | **Hecho**: `HitFlash` con destello + parpadeo |
| Hit-stop | Pendiente |
| Visual del swing de espada | Pendiente (solo existe la hitbox) |
| Animaciones 4 direcciones | Pendiente: solo `Idle_Down` / `Walk_Down` |
| Combo de 3 | Pendiente |

Orden actualizado (lo que quedó después del PR #6):
1. **Hit-stop** al impactar: es lo único del "feel" base que falta.
2. **Visual del swing** de la espada.
3. **Combo de 3**: máquina de estados en `sword.gd` (swing 1 → ventana → swing 2 → swing 3, con distinto
   hitbox, daño y knockback). Reusa el `KnockbackComponent` que ya existe; cada golpe solo cambia el
   `DamageInfo`.
4. **Animaciones de 4 direcciones** (arte, no código).

Oleadas por sala salen casi gratis después: las puertas ya se bloquean al entrar y se abren al limpiar.
Agarrar/lanzar queda afuera; sin co-op (D6) no hay razón para tenerlo.

**[IMPACTO de arte]** Personajes de lado con cámara cenital obligan a **cuatro direcciones de animación**,
no `flip_h`. Ese es el costo real de esta decisión y hay que resolverlo antes de encargar arte.

Los números objetivo (plantado, rodada, dispersión, stagger por enemigo) están en **D24**.

---

## PRONTO — combate, progresión y jefes

### D5 — Arte: ¿16 o 32 px? ¿HD-2D? [DECIDIDO]

**Decidido el 2026-10-24:**
- Tiles de 32×32 (`tilesets/crypt_dark.tres`, la cripta oscura).
- Personajes en un lienzo de **48×48**, con enemigos grandes de 96 y jefes de 128 o más.
- El estilo del entorno es la **cripta oscura**: la cripta "suave" (rampas de 8 tonos, losas irregulares sin
  grilla visible, luz de antorcha en anillos, sin dither) con una pasada *Fear & Hunger* más oscura y sucia.
- El estilo de los personajes es **"esbelto"**: ~4,4 cabezas, harapos y capuchas, sombreado calculado y
  contorno de color por material. Los objetos del entorno usan el mismo render.

Todo el detalle está en [`BIBLIA_ARTE.md`](BIBLIA_ARTE.md). El estilo puede cambiar más adelante, pero
mientras tanto todo asset nuevo sale con él.

HD-2D se decide después: en Godot implica sprites 2D con luces y normal maps, es una decisión de renderer y
es barata de posponer.

Ojo con la paleta apagada: choca con la legibilidad del combate. Reservar saturación para el feedback
(hit flash, VFX, telegrafía de ataque).

### D6 — ¿Un jugador o cooperativo? [PROPUESTA]

Un jugador. Co-op obliga a inventario por jugador en `RunManager`, cámara y límites por zona por jugador,
y HUD múltiple. Agregarlo después es casi reescribir. Confirmarlo temprano.

### D7 — ¿Quién produce el arte y con qué presupuesto? [PROPUESTA]

IA para borradores + una persona que retoque y apruebe.

Antes de generar un solo asset: **biblia de arte** (paleta, escala, perspectiva, reglas de iluminación).
Sin eso los assets no van a pegar entre sí. Lo primero que hay que resolver ahí es la mezcla
"personajes de lado + cámara cenital" que pide D4.

La biblia ya existe: [`BIBLIA_ARTE.md`](BIBLIA_ARTE.md) (2026-10-24). Cubre escala, cámara, luz, el
entorno y su paleta; la sección de personajes sigue en prueba.

### D8 — ¿Plataformas y control? [PROPUESTA]

Gamepad como control principal, teclado como alternativa. El seam de apuntado ya distingue mouse (apunta
al cursor) de gamepad (apunta hacia donde mira el jugador), así que ambos caminos existen. Falta que
gamepad sea el default y los prompts de UI. Steam Deck es PC con gamepad. Consolas, a futuro.

### D9 — ¿Se quedan el arco y el bastón? [YA DECIDIDO POR EL CÓDIGO]

Cuerpo a cuerpo principal; arco y bastón como alternativas. Esto **ya está implementado**: una sola arma
equipada, `swap_weapon` (Tab), se arranca con espada y las otras dos salen de cofres en zonas REWARD.

### D10 — ¿Cómo es una expedición al dungeon? [PROPUESTA]

Varios dungeons de 3–4 pisos, jefe al final, y un objeto para volver al pueblo a mitad de expedición.

**[IMPACTO]** Hoy los pisos son infinitos (`current_floor` incrementa sin techo). Hace falta un
`DungeonData` (id, cantidad de pisos, jefe) y el tipo de zona **BOSS**, que no existe: el generador solo
conoce START, COMBAT, REWARD y EXIT. El objeto de retorno reusa el mismo camino que la muerte, pero
conservando el loot.

Concretado para San Ulmo en **D21** (jefe) y **D22** (techo de pisos y `DungeonData`).

### D11 — ¿Cómo se hace más fuerte el personaje? [PROPUESTA]

Equipo del pueblo como progreso permanente + mejoras temporales en cada expedición. Sin XP ni niveles: el
poder viene del equipo. Es la consecuencia directa de D1 (dos capas de estado) y D2 (tienda).

**[IMPACTO]** El oro ya existe: cae de enemigos y cofres, se lleva encima en la expedición y se banca en el
guild (`ProfileState.banked_gold`). Todavía no hay en qué gastarlo: falta la tienda (D2).

### D12 — ¿Cómo funcionan las habilidades? [DECIDIDO]

**Modelo:** habilidades ligadas al arma equipada (reframe Albion, Engram #277). Cada arma tiene su kit
intercambiable: activas en los slots 1-4, buffs/debuff en Q/E/R. Varias opciones por slot, una sola activa
por slot; la maestría del arma desbloquea opciones nuevas.

**Recursos:** cada habilidad declara su coste. Puede ser **stamina**, **maná**, o **ambos a la vez**
(D19). Hoy el código solo tiene stamina; la infraestructura de maná entra con la Fase 8 parte B.

**Cooldowns:** no hay cooldowns de arma. Solo el slot "ultimate" puede tener uno.

Para el slice alcanza con 1–2 activas + 1 pasiva por arma, conservando la abstracción de slot para no
reescribir después. Ya propagado a `AGENTS.md` §18–§19 y `FEATURES.md` P2.

### D13 — ¿Un protagonista o varios? [PROPUESTA]

Uno solo. Varios protagonistas implican ramas de historia y multiplican el arte.

---

## HISTORIA Y ALCANCE

### D14 — ¿Cómo se cuenta la historia? [PROPUESTA]

Diálogos en el pueblo + una escena al cerrar cada dungeon. Requiere un sistema de diálogo data-driven
(Resource o JSON) y localización desde el principio.

**Estado (2026-10-26, rama `feat/slice-v2`):** primer corte. `DialogueData` + `DialoguePanel`; la escena de cierre de
San Ulmo son 3 líneas de narración (las velas se apagan, el cultista y "era una hija", la subida) más las de victoria de
Odran y la Hermana Ancel que ya estaban en los textos. Los NPCs usan sus líneas de muerte, piedra y victoria al volver.

### D15 — ¿Qué mundo y qué tono? [PROPUESTA]

"Superficie acogedora, profundidad opresiva": el pueblo es cálido y apagado; el dungeon es más oscuro y
contrastado. Resuelve el tono y la legibilidad del combate al mismo tiempo.

**Dirección del equipo (2026-10-24), reemplaza lo anterior:** *Moonlighter* y *Stardew* son referencias
de juego; la atmósfera y el ambiente son *Fear & Hunger*: tono **lo más oscuro posible**. Se permiten gore y horror corporal. Trasfondo: el mundo se vino abajo por
algo relacionado con las mazmorras y hay una crisis. El pueblo deja de ser acogedor: es un refugio frágil y
desesperado. Falta confirmarlo formalmente para pasar a [DECIDIDO].

### D16 — ¿Idiomas? [PROPUESTA]

Español e inglés, preparados desde ahora.

**[IMPACTO]** Hecho el 2026-10-25: HUD, mochila, pausa, guild y tienda usan `tr()` con `locale/strings.csv`
(español por defecto). Pendiente decidir "tú" o "vos": los textos usan "tú" neutro y los documentos "vos".

### D17 — ¿Próximo hito y para cuándo? [PROPUESTA]

Vertical slice interno, no demo pública. Alcance del hito:

```
pueblo → 1 dungeon de 3 pisos → jefe → volver con loot → comprar 1 mejora → repetir
```

Sin fecha estimada todavía: el mayor unknown es arte, no código.

### D18 — ¿Quién se encarga del audio y cuándo? [PROPUESTA]

Al final, pero reservando el alcance: 1 tema de pueblo, 1 de dungeon, 1 de jefe, ~10 SFX. Para el slice
alcanza con SFX de packs libres. La persona es decisión del equipo.

### D19 — Maná como segundo recurso [DECIDIDO]

Además de la stamina (recurso físico), el juego tiene **maná** (recurso mágico). No reemplaza a la
stamina: convive con ella.

- Hechizos y habilidades con propiedades mágicas declaran coste de **maná**.
- Las habilidades mixtas pueden costar **stamina + maná a la vez**.
- El coste es atómico: si falta cualquiera de los recursos declarados, la habilidad no se ejecuta. No hay
  casteo parcial.
- Los ataques físicos de arma (espada, arco) siguen costando solo stamina.

**[IMPACTO]** `ManaComponent` espejo de `StaminaComponent` (pool, regeneración, señales, relleno);
`AbilityData` suma `mana_cost`; barra de maná en el HUD junto a la de stamina; `WeaponData` puede necesitar
un coste de maná para el ataque básico del bastón.

**Estado (2026-10-26, rama `feat/slice-v2`):** implementado con valores provisorios: pozo de 100, 4/s de regeneración,
se rellena al cambiar de piso, al volver al gremio y en el altar (D23); el ataque básico del bastón sigue costando
solo stamina. La bola de fuego (35 de maná) es la primera habilidad mágica.

**Pendiente de definir (no bloquea el diseño):**
- Pool máximo, velocidad de regeneración y comportamiento al cambiar de piso (¿se rellena como la stamina?).
- Si el ataque básico del bastón consume maná o solo stamina.
- Si el maná se recupera con ítems, drops o descanso en el pueblo.

### D20 — Obstáculos movibles [PROPUESTA]

Algunas secciones de la mazmorra tienen **obstáculos movibles** (bloques, pilares caídos, escombros) que el
jugador desplaza consumiendo **stamina**, no maná.

- No son habilidades: usan el mismo protocolo de gasto que los ataques (`try_spend`).
- Su colocación sale de las plantillas de sala (D3), así que llegan con el pool de plantillas, no antes.
- No pueden romper la solvabilidad: la validación del generador tiene que asumir que un obstáculo movible
  puede estar bloqueando una ruta y que el jugador puede correrlo.
- Empujar es la interacción base. Tirar, usarlos como pieza de puzzle o aplastar enemigos queda para
  después.

**[IMPACTO]** Escena de obstáculo + interacción de empuje con drenaje de stamina; el generador y la
validación de solvabilidad necesitan conocerlos cuando existan las plantillas.

---

## SLICE — la Cripta de San Ulmo: jefe, pisos, cura y combate

Propuestas de contenido para cerrar el hito de D17. Salen del bestiario
(`_quizas_usemos/00_base/bestiary_V3/bestiary.md`) y del lore (`_quizas_usemos/07_textos/lore.md`), los dos en
estado PROPUESTA. Todos los números son **valores de tuning**: se fijan en `.tres` y se ajustan jugando.

Unidades: la **celda-pantalla** es la celda de la grilla del cambio en curso, de 15×9 tiles (480×288 px), con
anillo de pared de 1 tile y cara norte de 2 filas. El interior pisable de una celda mide 13×5 tiles. Si el
cambio aterriza con otro tamaño, las medidas en tiles se reescalan y los tiempos no cambian.

### D21 — Jefe de la cripta: la Madre de la Fosa [PROPUESTA]

Es Agna Sorel, fundida con la fosa común. Es el jefe del piso 3 de San Ulmo (D22). Está **fija**: no se mueve,
el jugador elige la distancia y ella castiga cada distancia con un ataque distinto. Tiene 2 fases. El sprite
mide 144×128 y tiene 3 poses (reposo, A, B), según el bestiario.

**Arena (zona BOSS)**

| Elemento | Valor |
|---|---|
| Tamaño | 2×2 celdas-pantalla = 30×18 tiles (960×576 px); interior pisable de 28×14 tiles (896×448 px) |
| Puertas | 1 sola, en la pared sur, desde la antesala (D22, D23). Se cierra al entrar, como en COMBAT. |
| La Madre | Anclada al **centro-norte**, con la pila contra la cara norte. Su huella sólida es de 6×4 tiles (192×128 px). |
| Pilares-vela | 4 pilares sólidos de 1×1 tile. Los 2 interiores están a ±5 tiles del eje, 7 filas bajo la pila; los 2 exteriores a ±10 tiles, 10 filas bajo la pila. Bloquean el vómito y los proyectiles. |
| Peligros | Charcos de bilis (del vómito, fase 2) y, en la fase 2, escombro de los pilares interiores (decorativo, no sólido) |
| Cámara | Sigue al jugador dentro de los límites de la zona con un sesgo del 25% hacia el torso de la Madre. Lejos de ella, la Madre puede quedar fuera de cuadro; por eso a más de 200 px solo usa *Manos de la fosa*, que se telegrafía bajo el jugador. |

Se cambia el "centro de la zona" del bestiario por el centro-norte: una Madre fija que mira siempre al sur
necesita solo las 3 poses frontales. En el centro tendría que girar, y eso pide arte en 4 direcciones de un
sprite de 144 px (D4).

**Stats base:** 600 HP (300 por fase). Nunca se aturde y es inmune al knockback (D24). Su golpe congela
120 ms (`hit_stop_seconds`). Hurtboxes:

| Hurtbox | Cuándo | Multiplicador |
|---|---|---|
| Torso (96×48 px, en el borde frontal de la pila, al alcance de la espada) | Siempre | ×1,0 |
| Manos clavadas (32×32 px cada una) | Recuperación de *Golpe doble* | ×1,5 |
| Núcleo del pecho | Recuperación de *Vómito* | ×2,0 |

**Ataques.** Los tiempos son anticipación / activo / recuperación, en segundos, con el valor de la fase 1 y
después el de la fase 2. La telegrafía usa el saturado reservado (D5): brasa del pecho, velas de la corona y
grietas en el piso.

| Ataque | Fase | Antic. | Activo | Recup. | Daño | Telegrafía | Cómo se evita | Castigo |
|---|---|---|---|---|---|---|---|---|
| **Golpe doble** (pose A) | 1-2 | 1,2 / 0,95 | 0,15 | 1,0 / 0,8 | 30 | Alza los dos brazos con las garras abajo, grita y la grieta del pecho pasa a brasa. Dos rectángulos de 128×96 px se oscurecen a cada costado de la pila. | Quedarse al frente de la pila (una franja segura de 160 px) o lejos. También se puede rodar a través del golpe. | Las manos quedan clavadas: ×1,5 durante la recuperación. Entran los golpes 1+2 del combo (1,04 s). |
| **Barrido** | 1-2 | 0,8 / 0,65 | 0,2 | 0,6 / 0,5 | 22 | Echa un brazo atrás y las velas se inclinan hacia ese lado. Un arco de 120° y 128 px de radio desde el torso. | Salir de los 128 px o rodar a través (ventana de 0,1 s). | Recuperación corta: entra 1 golpe. Castiga al que se planta al frente para evitar el golpe doble. |
| **Manos de la fosa** | 1-2 | 0,9 / 0,75 por mano | 0,2 | 0,45 entre manos | 18 c/u | Grieta roja de 24 px de radio bajo el jugador, que se ilumina hasta que sale la mano. Son 3 manos en la fase 1 y 5 en la fase 2, en secuencia. | Seguir moviéndose; rodar si la grieta te alcanza. | Mientras dura la secuencia ella queda quieta y el torso recibe golpes normales (unos 2 s). |
| **Vómito de la fosa** (pose B) | 2 | 1,5 | 1,2 | 1,6 | 10 por tick (cada 0,5 s) | Abre los brazos en cruz, echa la cabeza atrás y se abre el pecho con el núcleo encendido. El cono se marca en el piso. | Salir del cono (70°, 224 px) o ponerse detrás de un pilar. **No se puede rodar a través.** | El núcleo queda abierto: ×2 durante 1,6 s. Entra el combo completo (el 3.º golpe pega entre 1,38 y 1,50 s). |
| **Nana** | 2 | 1,0 | 3,0 | 1,2 | 30 (abrazo) | Las velas de la corona pasan a blanco amarillento, abre la boca y canta (cue de audio obligatorio). | Durante los 3 s el jugador **no regenera stamina** y es atraído a 25 px/s (caminando a 60 se resiste). Al terminar, si el jugador está a menos de 64 px del torso, lo abraza: 30 de daño y knockback de 300. | Si recibe 60 de daño mientras canta, la nana se corta y queda aturdida 1,5 s, la mayor ventana de la pelea. |

Selección de ataques: por distancia al torso (<128 px: golpe doble o barrido; 128–200 px: cualquiera;
>200 px: solo manos), sin repetir el mismo ataque 3 veces seguidas. La pausa entre ataques es de 0,6–1,0 s en
la fase 1 y de 0,3–0,6 s en la fase 2.

**Fase 2 (≤50% HP, 300 HP)**
- Transición de 2,5 s, invulnerable: grita, empuja al jugador con un knockback radial de 300 desde el torso,
  colapsan los 2 pilares interiores y la corona arde más fuerte, que es la señal de fase para siempre.
- Las anticipaciones bajan ~20% (tabla) y se suman *Vómito* y *Nana*.
- **Adds:** de los bordes de la pila salen 2 errantes "a medio formar" (35 HP en lugar de 55, misma
  telegrafía de 0,6 s) cada 18 s, con un máximo de 3 vivos. No sueltan botín, así no se farmean. Cuando muere
  la Madre se desploman todos.

**Rodada y stamina** (números de D24)
- Todo golpe único de la Madre dura ≤0,2 s activo, menos que los 0,3 s de i-frames de la rodada: siempre
  se puede rodar a través con buen timing. Lo sostenido (vómito, nana, charcos) se esquiva por posición.
- Presupuesto de 100 de stamina: un combo completo (70) + 1 rodada (25) siempre alcanza; combo + 2 rodadas
  no. Después de cada ventana de castigo, el ataque siguiente tiene ≥0,65 s de anticipación, así que el
  jugador que vació el combo llega a rodar.
- La *Nana* castiga la codicia: quien entra con poca stamina no puede rodar el abrazo y tiene que salir
  caminando.
- El combo no se cancela con rodada (D24): las ventanas están medidas para que un combo empezado al inicio de
  la recuperación termine antes del siguiente golpe activo.

**Muerte y botín**
- Secuencia de 3 s: se apagan las velas una por una, el pecho se cierra y se hunde en la pila, que se
  desmorona. Los adds caen con ella y la puerta se abre.
- Botín: **Corona de velas** (trofeo único, solo en la primera vez; `ItemData` de valor 200, "sigue tibia"),
  80–120 de oro y 1 piedra azul garantizada (D1).
- Aparece la **Escalera del Farol** donde estaba la pila: vuelve al guild con todo (D22).
- En las vueltas siguientes se cambia la corona por 40–60 de oro extra.

**[IMPACTO]**
- `Zone.ZoneType` suma `BOSS`. El generador corta una zona de 2×2 celdas en el último piso y la deja con una
  sola puerta (D22).
- `DungeonData` con techo de pisos y `boss_scene` (D22).
- Escena `scenes/bosses/madre_fosa.tscn` (AGENTS §26), con `HealthComponent`, varias `Hurtbox` con
  multiplicador, una `Hitbox` por ataque, un `AttackController` que lee un `Resource` por ataque (antic/
  activo/recup, daño, forma, fases y peso) y un `PhaseController` escuchando `health_changed`.
- `Hurtbox` necesita un multiplicador de daño y poder activarse por ventana.
- Escena de charco reutilizable (`Hitbox` periódica con vida útil), compartida con el escupebilis.
- `StaminaComponent.suppress_regen(seconds)` para la *Nana*.
- La atracción es una velocidad externa que suma `player.gd`, como el knockback pero sostenida.
- Barra de vida del jefe en el HUD.
- `Spawner` instancia el jefe en la zona BOSS. El cierre de puertas reutiliza el de COMBAT.
- La cámara gana el sesgo hacia un objetivo (`CameraLimitManager`) solo en la zona BOSS.

**Estado (2026-10-26, rama `feat/slice-v2`):** implementada entera (la *Nana* sin su cue de audio). Desvíos para
revisar: la puerta de la arena está en la pared oeste (la antesala queda al oeste porque la arena va fija en la
esquina sureste de la grilla); la huella sólida de la pila es de 128×112 px, la del dibujo, no de 6×4 tiles; los
pilares están a 3 y 6 filas bajo la pila, porque a 7 y 10 caen sobre la pared sur del interior de 14 filas; el sesgo
de cámara es del 40 % hacia el torso, porque con el 25 % la Madre queda cortada.

### D22 — Techo de pisos y DungeonData [PROPUESTA]

Concreta D10 para el primer dungeon. **San Ulmo tiene 3 pisos**, y el jefe está al final del 3.º. El techo
vive en `DungeonData` (de 3 a 4 pisos), así los dungeons siguientes del lore (Cloacas, Mina del Rey) pueden
tener 4.

**Qué suma cada piso** (la variedad gana a los multiplicadores, AGENTS §25)

| Piso | Lore | Zonas | Enemigos que entran | Presupuesto por celda | Élite | EVENT (D23) | Final |
|---|---|---|---|---|---|---|---|
| 1 | Galerías de Nichos | 5–7 | Errante, reptante, ratas | 4 | No | 25% | EXIT (escalera) |
| 2 | Osario | 6–8 | + Escupebilis, guardia osario | 5 | El Cosido, garantizado, en una zona propia de 2×2 | 50% | EXIT |
| 3 | Fosa Común | 6–8 + antesala + BOSS | + Cultista de la herida | 6 | El Cosido al 25% | Antesala garantizada | BOSS (D21) |

Coste de amenaza: errante 2, reptante 2, grupo de ratas (5–8) 3, escupebilis 3, guardia osario 3,
cultista 4. Una zona gasta `presupuesto × celdas`, con un tope de 3 celdas. Reglas del sorteo:
- Máximo 1 cultista por zona.
- Los enemigos a distancia (escupebilis, cultista) no superan 1/3 del presupuesto.
- Las zonas de ≥2 celdas reparten el presupuesto en 2 oleadas (60/40). La 2.ª sale al limpiar la 1.ª.

Multiplicadores de vida y daño por piso: 1,0/1,0, 1,1/1,1 y 1,2/1,15. Son chicos a propósito: la escala viene
del pool. El slime sale del pool de la cripta y se queda solo para los tests.

**Cómo se llega al jefe**
- En el último piso (`current_floor == floors.size()`) el generador no pone EXIT. Pone **BOSS** en la zona más
  lejana de START por BFS, forzando un corte de 2×2 celdas.
- BOSS tiene **una sola puerta**, desde la **antesala**: una zona de 1×1 celda con el altar de D23, sin
  enemigos.
- `validate_layout()` suma estas reglas: BOSS existe y mide ≥2×2, tiene 1 puerta, su único vecino con puerta
  es la antesala, no es vecina de START y todas las zonas se alcanzan desde START sin cruzar BOSS.
- Al entrar se cierra la puerta. Hay una intro de 1,5 s (las velas se encienden, aparece la barra de vida) y
  después la pelea. Morir ahí es una muerte normal (D1).

**Vuelta al guild después del jefe**
- La **Escalera del Farol** (D21) usa el mismo camino que la piedra azul, pero sin gastar ninguna: conserva
  la mochila y el oro encima, y asegura en el perfil las armas recogidas.
- Además marca `ProfileState.dungeons_cleared[&"san_ulmo"]` y avanza el día (`WorldClock`, D2). Queda lugar
  para la escena de cierre (D14).
- La expedición siguiente arranca en el piso 1 con seed nueva. Saltar pisos en un dungeon ya limpio (el
  atajo de D3) queda para después.

**[IMPACTO]**
- `scripts/resources/dungeon_data.gd` con `id`, `name_key`, `floors: Array[FloorData]` (el tamaño es el
  techo), `boss_scene` y `boss_zone_cells` (2×2), más `resources/dungeons/san_ulmo.tres`.
- `FloorData` suma `enemy_pool` (un `Resource` por entrada: escena, coste, peso y tamaño de grupo),
  `threat_budget_per_cell`, `elite_scene` + `elite_chance` y `event_chance`.
- `Spawner` pasa de "2 fijos por zona" a presupuesto + oleadas y **lee los multiplicadores**, lo que cierra la
  deuda del P0.
- `RunManager` guarda el `DungeonData` de la expedición. `DungeonManager` elige `floors[current_floor - 1]` y
  deja de incrementar pisos sin techo.
- `debug_next_floor` en el último piso salta a la antesala.
- Tests: techo de pisos, BOSS válido en N seeds y vuelta al guild con loot.

**Estado (2026-10-26, rama `feat/slice-v2`):** implementados `DungeonData`, techo de 3 pisos, multiplicadores, BOSS +
antesala EVENT, Escalera del Farol y `dungeons_cleared` (como desbloqueo `cleared:<id>` en `ProfileState.unlocks`, sin
cambiar el formato de guardado). Falta el pool por presupuesto, las oleadas, el élite y `WorldClock`.

**Bestiario y pool (2026-10-26, rama `feat/slice-v2`):** implementados el pool por presupuesto, los 5 comunes y el
Cosido como élite. Desvíos: con salas de una pantalla el tope de un tercio para los enemigos a distancia no deja entrar
ninguno (presupuesto 5 → tope 1), así que siempre cabe un grupo a distancia y el tercio rige desde el segundo; no hay
oleadas (todas las zonas COMBAT son de una pantalla); el Cosido sale en una zona COMBAT normal, sin el 2×2 propio y
con un gancho que tira del jugador (64-160 px, cada 6 s).

### D23 — Sala de cura con precio (zona EVENT) [PROPUESTA]

En la cripta no hay pociones gratis: curarse **cuesta algo de la expedición**. Es una zona EVENT de 1×1 celda
sin enemigos. Las puertas no se cierran. En el centro hay un **Altar del Voto**, el de las velas que el pueblo
encendía en la fosa. Un solo uso: cura **toda la vida y toda la stamina** (y el maná, cuando exista, D19) a
cambio de 1 de 3 ofrendas.

| Ofrenda | Coste | Regla |
|---|---|---|
| **Carne** | −20% de la vida máxima base para el resto de la expedición | Acumulable hasta 3 veces (el piso es el 40% de la vida base). Cura hasta el nuevo máximo. Se recupera al volver al guild. |
| **Diezmo** | Objetos de la mochila | El altar elige: toma unidades de mayor `ItemData.value` hasta sumar el diezmo del piso (15 / 25 / 40). Si la mochila no llega, se la lleva entera. Excluye la piedra azul y los trofeos. Muestra qué se lleva antes de confirmar. |
| **Piedra azul** | 1 piedra azul | Sin otro coste. Se pierde el seguro de D1: morir después cuesta toda la mochila. |

**Frecuencia:** como máximo 1 EVENT por piso: 25% en el piso 1, 50% en el 2, y en el 3 la antesala garantizada
(D22). Solo se asigna a zonas de 1×1 que no sean START, EXIT ni BOSS.

**Reglas**
- No se puede usar con la vida y la stamina llenas: muestra "No necesitás cura" y no gasta nada.
- Después de una ofrenda se apagan las velas, la zona queda resuelta y el altar no se puede volver a usar.
- Lo ofrecido no vuelve nunca, ni con piedra azul ni al limpiar el dungeon.
- La penalización de Carne es estado de expedición (`RunManager`): sobrevive al cambio de piso y muere con la
  run (D1, D11).

**UI**
- `interact` (F) en el altar abre un panel que pausa el juego, como el menú de pausa.
- Tiene 3 tarjetas en fila: el nombre, el coste concreto (el % de vida, la lista de objetos del diezmo o
  "Piedras: N") y una vista previa de la vida, por ejemplo "62/100 → 80/80".
- `move_left/right` elige, `attack` o `interact` confirma y `pause` cancela.
- Las opciones que no se pueden usar quedan grises con el motivo. Textos con `tr()` (D16).

**Casos borde**

| Caso | Resultado |
|---|---|
| Mochila vacía | Diezmo en gris: "La mochila está vacía". |
| Sin piedra azul | Piedra en gris: "No tenés piedra azul". |
| Carne ya ofrecida 3 veces | Carne en gris: "No te queda nada que dar". |
| Las tres en gris | El panel muestra "El altar no acepta nada más" y no cura. |
| Mochila con solo piedras azules | Diezmo en gris (la piedra no cuenta para el diezmo); queda la opción Piedra. |
| Varias piedras | Se gasta una. |
| Diezmo con valor menor al del piso | Se lleva toda la mochila. El panel lo avisa en rojo antes de confirmar. |

**Alternativas consideradas**
- *Pozo de agua negra* (cura o envenena al azar): el azar puro frustra en un combate pesado y pide efectos de
  estado, que no existen.
- *Cirujano del osario* (NPC que cose por oro): pide NPC y diálogo dentro del dungeon. Su lugar es el guild
  (Hermana Ancel).
- *Capilla de velas con oleadas* (cura al sobrevivir): repite la zona COMBAT y no tiene precio, solo tiempo.
- *Banquete podrido* (cura con náusea que baja la regeneración de stamina): pide modificadores de stamina y
  comida. Es buena candidata a 4.ª ofrenda.
- *Sanguijuelas* (cura en el tiempo a cambio de drenaje): pide daño periódico y efectos de estado (AGENTS §12).
- *La marca de la Madre* (cura ahora y el jefe se hace más fuerte): pide estado entre pisos y modificadores del
  jefe. Tiene mucho peso narrativo; se guarda para cuando D21 exista, como ofrenda exclusiva de la antesala.

**[IMPACTO]**
- `Zone.ZoneType` suma `EVENT`. El generador lo asigna con `FloorData.event_chance` y lo valida en
  `validate_layout()`.
- Escena `scenes/dungeon/altar.tscn`, interactuable como el cofre, y panel `scenes/ui/altar_panel.tscn` con
  `process_mode` ALWAYS.
- `RunManager.flesh_offerings: int`, aplicado al arrancar cada piso. `HealthComponent` necesita poder cambiar
  `max_health` en runtime.
- `Inventory` necesita "quitar por valor hasta N", y `ItemData.value` ya existe. El conteo de piedras azules
  ya existe para la muerte (D1).
- Test `assert_altar_offerings`: las 3 ofrendas y los casos borde de la tabla.

**Estado (2026-10-26, rama `feat/slice-v2`):** implementado tal cual: `RunManager.flesh_offerings`,
`Inventory.units_by_value`, `altar.tscn` y `altar_panel.tscn`. Los trofeos y la piedra azul quedan fuera del diezmo
porque son legendarios. Salir del gremio también cura, para que se note una mejora recién comprada.

### D24 — Sensación de combate: números objetivo [PROPUESTA]

Concreta D4 ("pesado = comprometerse") en números. Son **valores de tuning**: los de "en curso" son los que se
están implementando y los demás son propuestas. Viven en `WeaponData`/`SwingData`/`EnemyData` o en
`RollComponent`, y se tocan desde el Inspector.

**Plantado en melee (en curso)**
- Durante la anticipación, el activo y la recuperación de cada golpe de espada el jugador **no camina**. El
  input solo actualiza la orientación para el golpe siguiente.
- Solo avanza el paso del golpe (`SwingData.step_distance`): 4 px en los golpes 1 y 2 y 8 px en el 3.º,
  durante el activo.
- **No se puede rodar durante un golpe.** Sí en el margen de encadenado (0,25 s), que ya no planta.

| Golpe | Antic. | Activo | Recup. | Daño | Stamina | Knockback | Hit-stop | Temblor |
|---|---|---|---|---|---|---|---|---|
| 1 | 0,18 | 0,10 | 0,22 | 10 | 20 | 220 | 60 ms | 0 |
| 2 | 0,20 | 0,10 | 0,24 | 12 | 20 | 260 | 70 ms | 0 |
| 3 | 0,34 | 0,12 | 0,42 | 22 | 30 | 420 | 110 ms | 3 px |

**Dispersión a distancia (en curso).** Moverse no impide disparar, pero abre la dispersión: crece hasta el
máximo en 0,25 s moviéndose y se cierra a 0 en 0,5 s quieto. Dos marcas en el punto de mira la muestran.

| Arma | Dispersión máx. (a cada lado) | Velocidad | Daño | Stamina | Hit-stop propuesto |
|---|---|---|---|---|---|
| Arco | 12° | 400 px/s | 8 | 12 | 40 ms (en curso) |
| Bastón | 16° | 280 px/s | 14 | 18 | 50 ms (en curso) |

**Rodada (en curso, reemplaza al dash previsto)**

| Parámetro | Valor |
|---|---|
| Duración / distancia | 0,4 s / 64 px (160 px/s, contra 60 caminando) |
| I-frames | 0,3 s desde el inicio; los últimos 0,1 s quedan expuestos. Sin parpadeo. |
| Coste | 25 de stamina, con `try_spend` y sin cooldown |
| Reglas | No se cancela, no se rueda plantado ni durante un empuje, y el ataque pedido rodando sale al terminar. |

**Stagger y aguante por enemigo.** `stagger_seconds` (en curso) es el tiempo que el golpe corta la acción;
`poise_while_attacking` (en curso) hace que los golpes no corten una telegrafía ya comprometida;
`knockback_scale` (en curso) escala el empuje que recibe cada enemigo.

| Enemigo | Telegrafía | `stagger_seconds` | Aguante al atacar | `knockback_scale` | Nota |
|---|---|---|---|---|---|
| Rata de osario | casi nula | 0,4 | No | 1,5 | El golpe la saca volando; vale la pena el área. |
| Reptante | 0,35 | 0,5 | No | 1,2 | Frágil: un golpe corta el salto. |
| Cadáver errante | 0,6 | 0,3 (en curso) | Sí (en curso) | 0,8 | No se lo interrumpe una vez que alza el brazo. |
| Escupebilis | 0,8 | 0,4 | No | 1,0 | Alcanzarlo corta el escupitajo. |
| Guardia osario | 0,7 | 0,3 | Sí | 0,5 | El escudo frontal (120°) bloquea: 0 de daño, rebote de 120 para el jugador y 40 ms de hit-stop. El 3.º golpe del combo rompe la guardia: 0,8 s de stagger con el escudo bajo. |
| Cultista de la herida | 1,0 / 0,5 | 0,5 | No | 1,0 | Golpearlo corta la invocación: es su contra. |
| El Cosido | 1,0 | 0 | Siempre | 0,25 | Ventana: la cuchilla clavada en el piso, 1,0 s de recuperación. |
| La Madre (D21) | 0,65–1,5 | 0 (solo el corte de la *Nana*) | Siempre | 0 | Ver D21. |

**Dificultad v1 (en curso, rama `feat/dificultad-v1`).** Respuesta a "muy fácil, pocos enemigos, casi no
pegan". Es un paso previo al presupuesto + oleadas de D22, que lo reemplaza.

| Parámetro | Antes | Ahora |
|---|---|---|
| Enemigos por zona COMBAT | 2 fijos | 3 por pantalla de sala, +1 por piso después del 1.º, tope 8 |
| Persecución | dentro de `detect_radius` | solo en su zona (`territory`), en toda ella; no siguen al jugador a otra sala |
| Acercamiento | en línea recta, se apilan | rodean: cada uno entra con su ángulo (−0,9 / 0 / 0,9 rad) y cierra derecho a 96 px |
| Daño del slime / cadencia | 8 / 1,2 s | 12 / 1,0 s |
| Daño del errante | 14 | 22, con embestida de 150 px/s durante el activo (~30 px) y rango 40 |
| I-frames del jugador tras un golpe | 0,5 s | 0,35 s |

Sigue sin haber regeneración de vida: la vida solo vuelve al volver al guild o en el Altar del Voto (D23).

**Reglas de diseño para todo enemigo nuevo**
1. Todo golpe que daña tiene ≥0,35 s de anticipación con telegrafía visible en el saturado reservado (D5).
2. Un golpe único tiene ≤0,3 s de activo (los i-frames de la rodada), así siempre se puede rodar. Lo que dura
   más se esquiva por posición y se marca en el piso.
3. Cada ataque deja una recuperación castigable. Los ataques de más de 25 de daño dejan una de ≥0,6 s.
4. Los golpes al jugador congelan entre 60 y 120 ms (el errante 90, la Madre 120). El temblor de cámara va en
   px enteros (pixel art, AGENTS §38.1): el 3.º golpe 3 px y el golpe doble de la Madre 4 px.

**[IMPACTO]**
- Plantado, dispersión, rodada, `stagger_seconds` y `poise_while_attacking` ya están en implementación.
- `EnemyData.knockback_scale` es nuevo: lo aplica `KnockbackComponent`.
- El bloqueo frontal del guardia pide que `Hurtbox` conozca la orientación (un componente de guardia).
- El hit-stop de los proyectiles es sumar `hit_stop_seconds` a `WeaponData` y llamarlo en `arrow.gd`.

---

## Si se aprueban D1–D4: orden técnico sugerido

1. ✅ **Arreglar `_merge_cells`** (rectángulos exactos y tamaño mínimo de zona). Desbloquea D3 y evita que
   cualquier capa nueva herede el bug de solape.
2. ✅ **Hit-stop + visual del swing + combo de 3** (D4). Todo local a `sword.gd` y al combate, sin tocar
   estado. El visual del swing es un placeholder dibujado hasta que haya arte.
3. ✅ **`ProfileState` + oro + `_return_to_guild()`** (D1, D11), con almacén del guild y piedra azul.
4. **Guild mínimo con tienda** (D2), en `scenes/guild/`. El guild ya existe; falta la tienda.
5. **Pool de plantillas de sala** (D3), ya con el generador confiable.
6. **`WorldClock` día/noche + techo de pisos por dungeon + zona BOSS** (D2, D10).

El paso 1 es prerrequisito del 5. Los pasos 2 y 3 son independientes entre sí y pueden ir en paralelo.

Fuera de este orden inmediato: **D19 (maná)** entra junto con los kits de habilidad (Fase 8 parte B), y
**D20 (obstáculos movibles)** entra con el pool de plantillas de sala.

---

## Impacto consolidado en el código actual

| Sistema | Estado | Qué cambia si se aprueban D1–D4 |
|---|---|---|
| `RunManager` / `ProfileState` | Separados: perfil persistente + expedición (mochila, oro encima, armas recogidas) | Hecho (D1) |
| `DungeonManager._on_player_died()` | `_return_to_guild()` con regla de piedra azul | Hecho (D1) |
| Generador (grid-merging) | Topología + zonas rectangulares exactas de tamaño mínimo + `validate_layout()` | Pool de plantillas y solvabilidad con llaves |
| `Spawner` | 2 slimes fijos por zona COMBAT | Oleadas y cantidad por piso (D4, D10) |
| Tipos de zona | START, COMBAT, REWARD, EXIT | Suma BOSS (D10, D21) y EVENT (D23); SHOP más adelante |
| Pisos | Infinitos | Techo por dungeon (`DungeonData`) |
| Oro / perfil | `ProfileState` + oro + almacén del guild | Falta la tienda (D2) |
| Textos de UI | Hardcodeados | `tr()` + traducciones (D16) |
| `scenes/guild/` | Guild mínimo: almacén y puerta de expedición | Tienda, NPCs y `WorldClock` (D2) |
| Combate | Knockback, i-frames, hit flash, hit-stop y combo de 3 hechos | Falta arte del swing y 4 direcciones (D4) |
| `StaminaComponent` | Único recurso de combate | Se suma `ManaComponent`; habilidades con coste dual (D19) |
| Obstáculos de zona | No existen | Obstáculos movibles con coste de stamina, colocados por plantilla (D20) |

---

## Deuda nueva del P0 que condiciona decisiones

Está en `FEATURES.md` P0 (no es un hallazgo oculto), pero impacta directo el diseño:

| Deuda | Condiciona |
|---|---|
| `enemy_health/damage_multiplier` de `FloorData` no se leen | **D10/D11**: la dificultad todavía no escala con el piso |

---

## Hallazgos de Engram que no están en los documentos

Discutido en sesiones previas y, hasta el 2026-10-24, ausente de los documentos. Los puntos de diseño ya
fueron propagados; los de proceso siguen abiertos.

1. **Reframe Albion de la Fase 8** (Engram #277): un arma equipada con kit de habilidades propio. Ya
   propagado a `AGENTS.md` §18–§19 y `FEATURES.md` P2. Ver D12.
2. **La Fase 8 tiene dos partes**: `weapon-equip` (parte A, cerrada y archivada) y `abilities`
   (parte B, próximo candidato técnico; suma el maná de D19).
3. **(histórico)** `tilesets/dungeons_v2.tres` se editaba solo en el editor; el 2026-10-25 lo reemplazó `crypt_dark.tres`, generado por script. Antes: sus polígonos de colisión estaban ajustados a
   mano. El script que lo generaba se eliminó el 2026-10-24.
4. **Split del TileMap en nodos `TileMapLayer`** (floor / walls / door): diferido dos veces. Hoy sigue el
   TileMap único de tres capas.
5. **Escaleras sin autorar**: los planks `(6,4)` son escaleras incompletas, y `scenes/dungeon/exit.tscn`
   sigue con un `ColorRect` de placeholder. Falta autorar el tile y cambiar el placeholder por `Sprite2D`.
6. **Visibilidad por zona de las paredes exteriores**: los tiles de pared inferiores no traen arte
   interior; quedó pendiente ocultar lo de afuera según la zona.
7. **Coordenadas de tiles decorativos ya reservadas** en el atlas: `(0,4)-(2,4)`, `(1,5)`, `(0,5)`,
   `(2,5)`, `(1,6)`, `(1,7)`, para mini-rooms y decoración.
8. **Cinco findings no bloqueantes del review de `weapon-equip`**: latch de un solo uso en empty-pool,
   drops silenciosos al pool default, grant descartado si `add_weapon < 0`, cast frágil sobre const
   GDScript, input sintético en tests.
9. **Review nativo de `exit-area-scene` sin cerrar**: lineage `review-9727bafb09eafb83` en
   `state=reviewing` por fallas de transporte del proveedor. Deuda de proceso, no de código.

---

## Estado de la documentación

`README.md`, `AGENTS.md` y `FEATURES.md` quedaron alineados con D1–D20 el 2026-10-24. Si aparece una
contradicción nueva, gana este documento y se corrige el otro. D21–D24 (2026-10-25) son propuestas y
todavía no se propagaron.
