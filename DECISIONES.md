# DECISIONES — Dirección de diseño v2

**Estado:** dirección aprobada el 2026-10-24. D1–D4 (bloqueantes), D5, D12 y D19 están cerradas; el resto son
propuestas vigentes hasta que el equipo las revise.
**Fecha:** 2026-10-24.
**Revisión 2:** 2026-10-24, tras el merge del PR #6 (`feat/p0-combate-y-start`). Ver *Estado del repo*.
**Revisión 3:** 2026-10-24. Se suma el maná como segundo recurso (D19) y los obstáculos movibles (D20).
**Revisión 4:** 2026-10-24. D5 pasa a decidida (32 px de tile, personajes de 48×48, entorno "cripta
suave") y se crea la biblia de arte (D7).
**Alcance:** define el juego que queremos hacer. Las decisiones cerradas acá mandan sobre `AGENTS.md`,
`README.md` y `FEATURES.md` en todo lo que contradigan; esos documentos se actualizan **después** de la
validación, no antes.

## Cómo leer este documento

Cada decisión tiene un ID (`D1`…`D18`) para poder citarla en la discusión.

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

**[IMPACTO]** Hecho. `DungeonManager._on_player_died()` llama a `_return_to_guild()`: si hay piedra azul
en la mochila la gasta, conserva mochila y oro encima y asegura en `ProfileState` las armas recogidas; si
no, vacía la mochila. En los dos casos `RunManager.start_new_run()` re-rollea la seed y arranca con las
armas del perfil, y el perfil se guarda en `user://profile.json`. En el guild, el cofre del almacén pasa
la mochila al almacén y banca el oro. El generador no se tocó.

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
`FloorData.min_zone_cells` (2×2 celdas = 512×512 px) fija el tamaño mínimo; `validate_layout()` lo verifica:

1. **`_merge_cells` producía rectángulos que se solapaban.** La zona era el *bounding box* de las celdas que
   ganó, y el paso de asignación greedy expandía ese bbox sin verificar celdas ajenas: ~5% de los
   layouts tenían celdas pintadas dos veces. Con plantillas de sala esto deja de ser cosmético: una
   plantilla necesita un rectángulo exacto. Lo cubre `assert_zone_partition`.
2. **Una zona de 1 celda (8×8 tiles = 256×256 px) era más chica que el viewport (480×270 px).** La cámara
   no puede limitar por debajo del viewport y se veían las zonas vecinas.

Con esos dos arreglos la topología quedó confiable y el pool de plantillas es una capa encima, no una
reescritura.

**Alternativas descartadas:**
- *Puzzles*: requieren scripting bespoke por sala; caros. Dejarlos para cuando el loop esté cerrado.
- *Todo a mano*: tira a la basura la Fase 3, el sistema más grande implementado.

---

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

---

## PRONTO — combate, progresión y jefes

### D5 — Arte: ¿16 o 32 px? ¿HD-2D? [DECIDIDO]

**Decidido el 2026-10-24:**
- Tiles de 32×32, que ya es lo que usa el proyecto (`tilesets/dungeons_v2.tres`).
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

### D15 — ¿Qué mundo y qué tono? [PROPUESTA]

"Superficie acogedora, profundidad opresiva": el pueblo es cálido y apagado; el dungeon es más oscuro y
contrastado. Resuelve el tono y la legibilidad del combate al mismo tiempo.

**Dirección del equipo (2026-10-24), reemplaza lo anterior:** *Moonlighter* y *Stardew* son referencias
de juego; la atmósfera y el ambiente son *Fear & Hunger*: tono **lo más oscuro posible**. Se permiten gore y horror corporal. Trasfondo: el mundo se vino abajo por
algo relacionado con las mazmorras y hay una crisis. El pueblo deja de ser acogedor: es un refugio frágil y
desesperado. Falta confirmarlo formalmente para pasar a [DECIDIDO].

### D16 — ¿Idiomas? [PROPUESTA]

Español e inglés, preparados desde ahora.

**[IMPACTO]** Los textos de UI están hardcodeados en escenas y scripts ("Picked up: X"). Retrofittear es
barato hoy e innecesariamente caro más adelante: pasada de `tr()` + CSV cuando se toque el HUD.

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
| Tipos de zona | START, COMBAT, REWARD, EXIT | Suma BOSS (D10) y, más adelante, EVENT/SHOP |
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
3. **`tilesets/dungeons_v2.tres` se edita solo en el editor**: sus polígonos de colisión están ajustados a
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
contradicción nueva, gana este documento y se corrige el otro.
