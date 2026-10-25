# FEATURES — Estado del juego y backlog

La dirección vigente del juego está en [`DECISIONES.md`](DECISIONES.md); si este documento la
contradice, gana `DECISIONES.md`. La arquitectura y las reglas están en [`AGENTS.md`](AGENTS.md).

- **§1** describe lo que el código hace **hoy** (verificado contra el código, 2026-10-24).
- **§3** es el backlog ya re-sliced para el juego nuevo (dungeon crawler con historia).

Leyenda del backlog: `[ ]` pendiente · `[~]` parcial · `[x]` hecho. Prioridad: **P0** base
confiable y feel · **P1** vertical slice v2 · **P2** profundidad · **P3** contenido y pulido.

---

## 1. Features implementadas

### 1.1. Loop de partida

| Feature | Detalle | Dónde |
|---|---|---|
| Arranque | El juego arranca en el guild; la puerta de expedición (F) arma el piso 1. | `guild.gd`, `DungeonManager.start_expedition()` |
| Inicio de expedición | Seed aleatoria (`randi()`), piso 1, armas = las aseguradas en el perfil. La mochila no se toca. | `RunManager.start_new_run()` |
| Transición de piso | Interactuar (F) en la salida de la zona EXIT genera el piso siguiente con la misma `run_seed`. | `exit_area.gd`, `DungeonManager._start_floor()` |
| Muerte | Al llegar a 0 HP: espera 0.5 s, restaura vida y stamina y vuelve al guild con seed nueva. Sin piedra azul se pierden mochila, oro encima y armas recogidas; con piedra azul se gasta una y se conserva todo (las armas quedan aseguradas en el perfil). | `DungeonManager._return_to_guild()` |
| Estado entre pisos | Seed, piso actual, armas, arma equipada, mochila y oro encima. | `run_manager.gd` |
| Perfil persistente | Oro bancado, almacén del guild (60 slots), armas aseguradas y desbloqueos en `user://profile.json`. Guardado atómico (.tmp + rename); un archivo corrupto se aparta como `.corrupt`. | `profile_state.gd` |

### 1.2. Generación procedural

| Feature | Detalle |
|---|---|
| Grid-merging | Grilla de 3–6 × 3–5 celdas (8×8 tiles de 32 px cada una), que crece si hace falta para que entren las zonas. Cortes guillotina: zonas rectangulares exactas, sin solapes ni espacios muertos, de al menos `min_zone_cells` (2×2 celdas = 512×512 px, más que el viewport). |
| Cantidad de zonas por profundidad | `zone_count_by_floor_depth`: piso 1 → 3–5 zonas, piso 10 → 6–12. |
| Tipos de zona | 1 START, 1 EXIT y el resto COMBAT o REWARD (`reward_ratio` 0.3). |
| Validación | `validate_layout()`: rectángulos exactos, cobertura completa, tamaño mínimo, tope de START, puertas en aristas compartidas y todas las zonas alcanzables desde START. Si falla, reintenta con otra seed derivada hasta 5 veces y después falla con `push_error` (sin fallback). Cubierto por `assert_zone_partition` (500 seeds × 3 profundidades). |
| Tope de START | La zona START se recorta primero en el origen a `FloorData.start_zone_max_cells` (2×2 celdas = 16×16 tiles por defecto); si es menor que `min_zone_cells`, gana el mínimo. |
| Determinismo | La misma `(run_seed, floor_number)` produce el mismo piso; cubierto por un test. |
| Puertas | Posición irregular en las aristas compartidas; varias por arista si es larga (`multi_door_threshold`). |
| Render | Un TileMap único con el tileset de la cripta oscura (`crypt_dark.tres`): tope + cara de 2 filas en la pared norte, topes en las laterales y la sur, piso periódico por `(tx % 3, ty % 3)` con AO al pie de las paredes, puertas en hueco o en arco y escalera de bajada en la salida. Las paredes bloquean su tile completo. |
| Ambiente | `floor_dressing.gd`, sembrado por la seed: una antorcha encendida por zona en la cara norte (dos si es ancha) con luz que solo toca personajes, soportes apagados, objetos colgados, telarañas y calcos de piso. |

### 1.3. Exploración

| Feature | Detalle |
|---|---|
| Movimiento | 8 direcciones, `speed` 60, Input Map (WASD/flechas). |
| Cámara por zona | `Camera2D` limitada al rectángulo de la zona actual (cámara fija por sala); cambia al cruzar una puerta. |
| Cruce de puertas | Detección en dos fases (entrar/salir del área): volver atrás no cuenta como cruce. |
| Bloqueo de combate | Entrar a una zona COMBAT sin limpiar cierra sus puertas hasta matar a todos los enemigos. |
| Interacción | Acción `interact` (F) para cofres y salida. |

### 1.4. Combate

| Feature | Detalle |
|---|---|
| Protocolo de daño único | Hitbox/proyectil → Hurtbox → HealthComponent → `died`. Funciona en las dos direcciones (jugador ↔ enemigo). |
| Capas de colisión | 5 capas centralizadas en `CollisionLayers`. |
| Recursos | Stamina 100 (regen 20/s), se rellena al cambiar de piso o al morir. Cada ataque cuesta stamina; no hay cooldowns. Todavía no hay maná (D19). |
| Apuntado | Mouse/Space apuntan al cursor; el gamepad apunta hacia donde mira el jugador. |
| Espada | Melee, combo de 3 golpes (`WeaponData.combo`, un `SwingData` por golpe): preparación → hitbox activa → recuperación. Atacar durante el golpe activo o la recuperación encadena el siguiente; también hay 0.25 s de margen al terminar. Perder el margen o no tener stamina vuelve al golpe 1. Daño 10 / 12 / 22, coste 20 / 20 / 30, knockback 220 / 260 / 420; el 3.º es más lento. Cada golpe juega la animación de ataque del jugador sincronizada con sus fases y un smear por dirección (corte, revés y golpe de arriba). |
| Arco | Flecha de 400 px/s, daño 8, coste 12, knockback 120. |
| Bastón | Proyectil mágico de 280 px/s, daño 14, coste 18, knockback 140 (reutiliza `arrow.gd`). |
| Proyectiles | Mueren al impactar al primer enemigo, al chocar con una pared o a los 2 s. Vuelan con la hoja de su dirección (flecha o bolo de bilis) y dejan un efecto de impacto. |
| Knockback | `KnockbackComponent`: el golpe empuja al objetivo con velocidad inicial = `knockback` (px/s), que decae a 0 en 0.2 s. Mientras dura, el empuje reemplaza el movimiento propio (stagger). |
| I-frames | `HealthComponent.invulnerability_seconds`: el jugador ignora golpes durante 0.5 s después de recibir uno; los enemigos no tienen. |
| Hit flash | `HitFlash`: destello brillante al recibir daño y parpadeo del sprite mientras duran los i-frames. |
| Sangre | `HitVfx`: cada golpe aceptado a un enemigo saca una chispa, un chorro de sangre hacia el empuje y una mancha en el piso que dura todo el piso. |
| Hit-stop | `HitStop`: cada golpe aceptado de una `Hitbox` congela el juego (`Engine.time_scale` 0.05) durante `hit_stop_seconds`: espada 60 / 70 / 110 ms por golpe del combo, slime 60 ms (`EnemyData`). Varios golpes no se suman: gana el fin más tardío. Las flechas y proyectiles todavía no lo usan. |

### 1.5. Armas e inventario

| Feature | Detalle |
|---|---|
| Inventario de armas | Lista de armas obtenidas en `RunManager`; Tab rota entre ellas. |
| Montaje | `EquipmentController` monta **una** arma a la vez bajo `Player/Weapons`. |
| Datos por recurso | `WeaponData` (.tres): tipo, escena, daño, knockback, coste de stamina, datos del proyectil y, en melee, el combo (`SwingData`). |
| Cofres | En las zonas REWARD: un cofre que da un arma del pool (arco/bastón), elegida con la seed, más una tirada de botín (`chest_drops.tres`). El arma se equipa automáticamente. |
| Loot | `ItemData` (.tres) y `DropTable` (probabilidad por objeto + rango de oro). El slime suelta gel, hueso, piedra azul y 1–3 de oro. |
| Mochila y almacén | `Inventory`: slots con apilado. Mochila de 20 slots (`RunManager`), almacén de 60 (`ProfileState`). El cofre del guild pasa la mochila al almacén y banca el oro. |

### 1.6. Enemigos

| Feature | Detalle |
|---|---|
| Slime | 30 HP, velocidad 60, daño 8, knockback 160. Detecta a 120 px, ataca a 20 px con una ventana de 0.2 s y cooldown de 1.2 s. Sprite fijo con aplaste/estiramiento por tween. |
| Cadáver errante | 55 HP, velocidad 28, daño 14, knockback 260. Detecta a 140 px, ataca a 22 px: se queda quieto 0.6 s alzando el brazo (telegrafía) antes de abrir la hitbox; cooldown de 1.8 s. Animaciones del kit en 4 direcciones; al morir queda su cuerpo en el piso. |
| IA | Persecución en línea recta dentro del radio de detección (sin pathfinding). |
| Spawn | 2 enemigos por zona COMBAT, sorteados con la seed de la lista `Spawner.enemy_scenes` (slime y errante), en tiles interiores (lejos de las paredes). |
| Muerte | Corta la IA y las colisiones, juega la muerte (animación o aplaste + estallido de sangre) y recién después libera al enemigo. |
| Datos | `EnemyData` (.tres). |

### 1.7. UI

| Feature | Detalle |
|---|---|
| Barra de vida | `ProgressBar` ligada a `health_changed`. |
| Barra de stamina | `ProgressBar` ligada a `stamina_changed`. |
| Nombre del arma | Label con el arma equipada. |
| Toast de recogida | "Picked up: X" durante 1.5 s con fade; el botín del mismo frame se suma al toast. |
| Oro | Label con oro bancado y oro encima. |
| Mochila | `inventory` (I) muestra la mochila y el almacén. |
| Pausa | Esc (`pause`) pausa el juego y muestra un menú (Resume / Quit); otro Esc o Resume lo cierra. |

### 1.8. Herramientas de desarrollo

- 37 tests headless (`scripts/test/`), todos verdes.
- Vista previa del estilo de arte: `scenes/preview/art_preview.tscn` (no está en `main.tscn`); su tileset sale de `scripts/tools/build_art_preview_tileset.gd`.
- Tileset del juego: `tools/art/build_crypt_atlas.py` arma el atlas y `scripts/tools/build_crypt_tileset.gd` genera `tilesets/crypt_dark.tres`.
- **Advertencia:** `tilesets/crypt_dark.tres` se genera con `scripts/tools/build_crypt_tileset.gd` (colisiones desde `DungeonGeometry.is_solid_atlas`): no editarlo a mano, se pisa al regenerar.
- Atajo de debug **N** (acción `debug_next_floor`): salta al siguiente piso. Solo corre en builds de debug.

---

## 2. Limitaciones conocidas y deuda

| Problema | Impacto |
|---|---|
| `enemy_health/damage_multiplier` no se leen | La dificultad no sube con el piso. |
| Sin números de daño ni sonido al golpear | El combate se lee solo por el destello y el empuje. |
| El cofre es un `ColorRect` | Placeholder visual. |
| Sin audio | No hay música ni SFX. |
| La muerte vuelve al guild al instante | No hay pantalla de muerte ni resumen de la run. |
| No existe `DungeonData` | No hay techo de pisos: la muerte es la única forma de volver al guild. |
| No existe maná ni coste dual | Todas las habilidades gastan solo stamina; el maná llega con la Fase 8 parte B (D19). |
| Los `.uid` están en el gitignore | Los UIDs cambian entre máquinas. |

---

## 3. Backlog (TODOs)

Ya está en `main` y documentado en §1: knockback, i-frames, hit flash, pausa y tope de START (PR #6).

### P0 — base confiable y feel

**Generador y cámara**
- [x] Arreglar el solape de `_merge_cells` (rectángulos exactos) y agregar un tamaño mínimo de zona.
- [x] Cámara en zonas más chicas que el viewport: ya no hay zonas más chicas que el viewport (`min_zone_cells` 2×2).

**Feel de combate**
- [x] Hit-stop al impactar.
- [x] Visual del swing de la espada (smear por golpe y dirección).
- [x] Combo de 3 golpes en `sword.gd`.
- [x] Animaciones de 4 direcciones del jugador (idle, caminar y ataque).

**Estabilidad y docs**
- [x] Actualizar `README.md`, `AGENTS.md` y `FEATURES.md` a la dirección v2.
- [x] Dejar una sola instancia de `RunManager` (se quitó el autoload; queda el nodo de `main.tscn`).
- [ ] Commitear los `.uid` (sacarlos de `.gitignore`).

### P1 — vertical slice v2

**Perfil, economía y pueblo**
- [x] `ProfileState` persistente en `user://` (oro bancado, almacén del guild, armas aseguradas, desbloqueos).
- [x] Oro e ítems: drops de enemigos y cofres (tablas de botín) y contador de oro en el HUD. Falta la curación.
- [x] Inventario de mochila (slots con apilado) y almacén del guild; panel con `inventory` (I).
- [x] Vuelta al guild en vez de wipe (`_return_to_guild()`), perdiendo lo de la expedición.
- [x] Piedra azul: consumible que, al morir, te lleva al guild conservando el loot (D1).
- [ ] Guild con tienda (vender loot, comprar equipo y piedras azules) en `scenes/guild/`. Hoy es un guild provisorio con almacén y puerta.
- [ ] `WorldClock` con fases día/noche.
- [ ] Guardado del perfil y de los ajustes (`user://`).

**Expedición y jefe**
- [ ] `DungeonData` (id, cantidad de pisos, jefe) y techo de 3–4 pisos.
- [ ] Tipo de zona BOSS.
- [ ] Primer boss con 1–2 fases (`PhaseController`, ver `AGENTS.md` §26).
- [ ] Usar los multiplicadores de `FloorData` en `Spawner` al instanciar enemigos.
- [ ] Escalar `enemies_per_zone` según el piso o el tamaño de la zona.

**Flujo y presentación**
- [ ] HUD: label de piso actual (`FloorLabel`, previsto en `AGENTS.md` §5).
- [ ] Pantalla de muerte: piso alcanzado, enemigos derrotados y botón de reintentar.
- [ ] Menú principal (Jugar / Salir) como escena de entrada.
- [ ] Prompt "F" visible al estar cerca de un cofre o de la salida.
- [ ] Indicador de "puertas cerradas" y feedback al limpiar la zona (sonido o efecto).
- [ ] Sprite real para el cofre, con animación de abrir.
- [ ] Transición (fade) entre pisos.
- [ ] Base de localización ES/EN (`tr()` + CSV) de los textos de UI.

**Audio (último del slice)**
- [ ] Música de pueblo y de dungeon.
- [ ] SFX de golpe, muerte, ataque, recogida y puerta.

### P2 — profundidad

**Mazmorra**
- [ ] Pool de plantillas de sala en `scenes/rooms/`.
- [ ] Obstáculos movibles que consumen stamina (D20); su colocación viene de las plantillas de sala.
- [ ] Llaves y puertas cerradas + validación de solvabilidad en el generador.
- [ ] Nuevos tipos de zona: EVENT y SHOP.
- [ ] Minimapa con las zonas visitadas.
- [ ] Obstáculos y decoración estática dentro de las zonas (pilares, escombros) para variar el combate.
- [ ] Trampas que usen el protocolo Hitbox (pinchos, explosiones).
- [ ] Mostrar la seed en pausa o en la pantalla de muerte, y poder introducir una seed.

**Habilidades (Fase 8 parte B, D12)**
- [ ] `AbilityData` por kit de arma + abstracción de slot (activas 1-4, buffs/debuff Q/E/R).
- [ ] `ManaComponent` + barra de maná + coste dual (`stamina_cost` / `mana_cost`) en `AbilityData` (D19).
- [ ] Primer corte: 1-2 activas + 1 pasiva por arma.
- [ ] Ice Nova: AoE con ralentización (primer crowd control).
- [ ] Fireball: proyectil que reutiliza `arrow.gd` y aplica daño en área al impactar.
- [ ] Speed Buff: buff temporal de velocidad.
- [ ] Acciones de habilidad en el Input Map y en el HUD.

**Estados y buffs**
- [ ] Sistema mínimo de status effects (slow, burn, freeze) con duración, aplicado vía `DamageInfo`.
- [ ] Buffs de stats temporales y permanentes (daño, velocidad, regeneración de stamina/maná).

**Enemigos**
- [ ] Segundo enemigo a distancia (dispara proyectiles con el mismo protocolo).
- [x] Enemigo que telegrafía su ataque (cadáver errante).
- [ ] Tercer enemigo con carga o embestida.
- [ ] Pathfinding básico (NavigationRegion2D o A* sobre la grilla) para no quedarse trabado en paredes.
- [ ] Tabla de spawn por piso en `FloorData` (qué enemigos aparecen y con qué peso).
- [ ] Elites: variante con más HP, tinte distinto y un modificador.

**Loot y progresión**
- [ ] `UpgradeData`: mejoras pasivas elegibles (elige 1 de 3) en las zonas REWARD.
- [ ] Rareza de armas (común/rara/épica) con modificadores de stats.
- [ ] Variantes de arma (`sword_heavy`, multishot del arco, etc.) como nuevos `.tres`.
- [ ] Meta-progresión: desbloqueos persistentes entre expediciones (D1).
- [ ] Builds híbridas: sinergias entre arma, habilidad y upgrade (ver `AGENTS.md` §28).
- [ ] Balance: tabla de DPS por arma/coste y curvas de dificultad por piso.

**Historia y pueblo**
- [ ] Sistema de diálogo data-driven (`DialogueData`).
- [ ] NPCs del pueblo con diálogo fijo.
- [ ] Escena de cierre al terminar cada dungeon.

### P3 — contenido y pulido

- [ ] Granja y crafting (solo si se aprueba; hoy fuera del alcance).
- [ ] Relaciones con NPCs.
- [ ] HD-2D (luces y normal maps) si se decide.
- [ ] Screen shake.
- [ ] Números de daño flotantes.
- [ ] Partículas de muerte de enemigos.
- [ ] Dash (acción `dash`) con coste de stamina e i-frames cortos.
- [ ] Opciones: volumen, remapeo de controles y pantalla completa.
- [ ] Soporte completo de gamepad (apuntado con el stick derecho).
- [ ] Efectos de estado adicionales y pulido de combate.

### Descartado explícitamente

- **XP y niveles** (D11): el poder viene del equipo y de las mejoras.
- **Cooperativo** (D6): un jugador.
- **Agarres y lanzamientos** (D4): fuera del feel buscado.

---

## 4. Cómo usar este archivo

- Al terminar una feature: pásala de §3 a §1 (o márcala `[x]`) y ajusta §2 si cambió una limitación.
- Antes de empezar un item P2+, revisa que los P0/P1 de los que depende estén cerrados
  (`AGENTS.md` §31: no saltar a sistemas posteriores con la base inestable).
- Si un item cambia la arquitectura, actualiza también `AGENTS.md`.
