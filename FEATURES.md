# FEATURES — Estado del juego y backlog

Inventario de lo que el juego hace **hoy** (verificado contra el código, 2026-10-22) y backlog de
features para un roguelite de mazmorras. La arquitectura y las reglas están en [`AGENTS.md`](AGENTS.md).

Leyenda del backlog: `[ ]` pendiente · `[~]` parcial · `[x]` hecho. Prioridad: **P0** bloquea el
loop básico o la sensación de juego · **P1** completa el vertical slice · **P2** profundidad
roguelite · **P3** pulido y contenido.

---

## 1. Features implementadas

### 1.1. Loop de partida

| Feature | Detalle | Dónde |
|---|---|---|
| Inicio de run | Seed aleatoria (`randi()`), piso 1, inventario reseteado a la espada. | `RunManager.start_new_run()` |
| Transición de piso | Interactuar (F) en la salida de la zona EXIT genera el piso siguiente con la misma `run_seed`. | `exit_area.gd`, `DungeonManager._start_floor()` |
| Muerte y reinicio | Al llegar a 0 HP: espera 0.5 s, restaura vida y stamina, **nueva run** (nueva seed, piso 1). | `DungeonManager._on_player_died()` |
| Estado persistente entre pisos | Seed, piso actual, armas obtenidas y arma equipada. | `run_manager.gd` |

### 1.2. Generación procedural

| Feature | Detalle |
|---|---|
| Grid-merging | Grilla de 3–6 × 3–5 celdas (8×8 tiles de 32 px cada una). Las celdas se agrupan en zonas rectangulares, sin espacios muertos. |
| Cantidad de zonas por profundidad | `zone_count_by_floor_depth`: piso 1 → 3–5 zonas, piso 10 → 6–12. |
| Tipos de zona | 1 START, 1 EXIT y el resto COMBAT o REWARD (`reward_ratio` 0.3). |
| Validación | BFS START→EXIT. Si falla, reintenta hasta 5 veces y después usa un layout de fallback. |
| Tope de START | La zona START se recorta a `FloorData.start_zone_max_cells` (2×1 celdas = 16×8 tiles por defecto); lo que sobra pasa a ser zonas nuevas. |
| Determinismo | La misma `(run_seed, floor_number)` produce el mismo piso; cubierto por un test. |
| Puertas | Posición irregular en las aristas compartidas; varias por arista si es larga (`multi_door_threshold`). |
| Render | Un TileMap único con un tileset pre-autorado (`dungeons_v2.tres`). Paredes con colisión y piso con tinte según el tipo de zona. |

### 1.3. Exploración

| Feature | Detalle |
|---|---|
| Movimiento | 8 direcciones, `speed` 60, Input Map (WASD/flechas). |
| Cámara por zona | `Camera2D` limitada al rectángulo de la zona actual (estilo Isaac); cambia al cruzar una puerta. |
| Cruce de puertas | Detección en dos fases (entrar/salir del área): volver atrás no cuenta como cruce. |
| Bloqueo de combate | Entrar a una zona COMBAT sin limpiar cierra sus puertas hasta matar a todos los enemigos. |
| Interacción | Acción `interact` (F) para cofres y salida. |

### 1.4. Combate

| Feature | Detalle |
|---|---|
| Protocolo de daño único | Hitbox/proyectil → Hurtbox → HealthComponent → `died`. Funciona en las dos direcciones (jugador ↔ enemigo). |
| Capas de colisión | 5 capas centralizadas en `CollisionLayers`. |
| Stamina | Pool de 100 que se regenera 20/s. Cada ataque cuesta stamina; no hay cooldowns. Se rellena al cambiar de piso o al morir. |
| Apuntado | Mouse/Space apuntan al cursor; el gamepad apunta hacia donde mira el jugador. |
| Espada | Melee: ventana de hitbox de 0.15 s, daño 10, coste 20, knockback 220. |
| Arco | Flecha de 400 px/s, daño 8, coste 12, knockback 120. |
| Bastón | Proyectil mágico de 280 px/s, daño 14, coste 18, knockback 140 (reutiliza `arrow.gd`). |
| Proyectiles | Mueren al impactar al primer enemigo, al chocar con una pared o a los 2 s. |
| Knockback | `KnockbackComponent`: el golpe empuja al objetivo con velocidad inicial = `knockback` (px/s), que decae a 0 en 0.2 s. Mientras dura, el empuje reemplaza el movimiento propio (stagger). |
| I-frames | `HealthComponent.invulnerability_seconds`: el jugador ignora golpes durante 0.5 s después de recibir uno; los enemigos no tienen. |
| Hit flash | `HitFlash`: destello brillante al recibir daño y parpadeo del sprite mientras duran los i-frames. |

### 1.5. Armas e inventario

| Feature | Detalle |
|---|---|
| Inventario de armas | Lista de armas obtenidas en `RunManager`; Tab rota entre ellas. |
| Montaje | `EquipmentController` monta **una** arma a la vez bajo `Player/Weapons`. |
| Datos por recurso | `WeaponData` (.tres): tipo, escena, daño, knockback, coste de stamina, datos del proyectil. |
| Cofres | En las zonas REWARD: un cofre que da un arma del pool (arco/bastón), elegida con la seed. Se equipa automáticamente. |

### 1.6. Enemigos

| Feature | Detalle |
|---|---|
| Slime | 30 HP, velocidad 60, daño 8, knockback 160. Detecta a 120 px, ataca a 20 px con una ventana de 0.2 s y cooldown de 1.2 s. |
| IA | Persecución en línea recta dentro del radio de detección (sin pathfinding). |
| Spawn | 2 slimes por zona COMBAT, en tiles interiores (lejos de las paredes). |
| Datos | `EnemyData` (.tres). |

### 1.7. UI

| Feature | Detalle |
|---|---|
| Barra de vida | `ProgressBar` ligada a `health_changed`. |
| Barra de stamina | `ProgressBar` ligada a `stamina_changed`. |
| Nombre del arma | Label con el arma equipada. |
| Toast de recogida | "Picked up: X" durante 1.5 s con fade. |

### 1.8. Herramientas de desarrollo

- 26 tests headless (`scripts/test/`), todos pasan.
- `build_dungeon_tileset.gd` regenera el tileset de forma reproducible.
- Atajo de debug **N** (acción `debug_next_floor`): salta al siguiente piso. Solo corre en builds de debug.

---

## 2. Limitaciones conocidas y deuda

| Problema | Impacto |
|---|---|
| `enemy_health/damage_multiplier` no se leen | La dificultad no sube con el piso. |
| Solo hay animaciones `Idle_Down` / `Walk_Down` | El sprite no mira arriba ni a los lados (solo usa `flip_h`). |
| La acción `pause` existe pero no hace nada | No hay pausa. |
| Sin números de daño ni sonido al golpear | El combate se lee solo por el destello y el empuje. |
| El cofre es un `ColorRect` | Placeholder visual. |
| `guild_tavern.tscn` no está conectada | Escena de hub sin flujo de entrada ni salida. |
| Sin audio | No hay música ni SFX. |
| La muerte reinicia al instante | No hay pantalla de muerte ni resumen de la run. |
| Una zona más chica que la pantalla (480×270 px) deja ver a sus vecinas | La cámara no puede limitar por debajo del viewport; pasa con zonas de 1 celda, START incluida. |
| `AGENTS.md` describe `secondary_attack` / `staff_attack` | Los docs no coinciden con el esquema real (`attack` + Tab). |
| Doble `RunManager` (autoload + nodo en escena) | Riesgo de usar la instancia equivocada. |
| Los `.uid` están en el gitignore | Los UIDs cambian entre máquinas. |
| `_merge_cells` puede dar zonas cuyos rectángulos se solapan (~5% de los layouts) | Celdas que pertenecen a dos zonas: tiles pintados dos veces. Lo detectó `assert_start_zone_cap`. |

---

## 3. Backlog (TODOs)

### P0 — Sensación de combate y estabilidad

- [x] Atajo de debug N para saltar de piso sin recorrer la sala.
- [x] Limitar el tamaño de la zona START (`FloorData.start_zone_max_cells`, 2×1 celdas).
- [ ] Arreglar el solape de zonas en `_merge_cells` (las zonas son bounding boxes del crecimiento, no rectángulos exactos).
- [ ] Cámara en zonas más chicas que la pantalla: ocultar o atenuar las zonas vecinas (o zoom), para mantener las salas aisladas.
- [x] Restaurar los tintes del piso (START verde, REWARD dorado, EXIT rojo); vuelven a pasar `assert_plank_floor` y `assert_prebuilt_tileset`.
- [x] Aplicar knockback en `enemy.gd` y `player.gd` usando `DamageInfo.knockback` (`KnockbackComponent`, decae en 0.2 s).
- [x] I-frames para el jugador (0.5 s) tras recibir daño, con parpadeo del sprite (`HealthComponent.invulnerability_seconds`).
- [x] Hit flash al recibir daño, para jugador y enemigos (`HitFlash`, modulate).
- [ ] Animaciones de 4 direcciones (Idle/Walk Up, Side, Down) en el jugador.
- [ ] Animación o efecto visual del swing de la espada (hoy solo existe la hitbox).
- [ ] Pausa: `get_tree().paused` con la acción `pause` y un menú mínimo (Continuar / Salir).
- [ ] Actualizar `AGENTS.md` §13 y §30 al esquema real `attack` + `swap_weapon`.
- [ ] Quitar `run_manager` de los autoloads (o el nodo de la escena) y dejar una sola instancia.
- [ ] Commitear los `.uid` (sacarlos de `.gitignore`).

### P1 — Completar el vertical slice

- [ ] HUD: label de piso actual (`FloorLabel`, previsto en `AGENTS.md` §5).
- [ ] Pantalla de muerte: piso alcanzado, enemigos derrotados y botón de reintentar.
- [ ] Menú principal (Jugar / Salir) como escena de entrada.
- [ ] Dash (acción `dash`) con coste de stamina e i-frames cortos.
- [ ] Usar los multiplicadores de `FloorData` en `Spawner` al instanciar enemigos.
- [ ] Escalar `enemies_per_zone` según el piso o el tamaño de la zona.
- [ ] Sprite real para el cofre, con animación de abrir.
- [ ] Indicador de "puertas cerradas" y feedback al limpiar la zona (sonido o efecto).
- [ ] Prompt "F" visible al estar cerca de un cofre o de la salida.
- [ ] Audio base: música de piso, SFX de golpe, muerte, ataque, recogida y puerta.

### P2 — Profundidad roguelite (Fases 8–9 de `AGENTS.md`)

**Habilidades (Fase 8)**
- [ ] `AbilityData` (Resource) + un `AbilityController` en el jugador (sin jerarquía de clases todavía).
- [ ] Ice Nova: AoE con ralentización (primer crowd control).
- [ ] Fireball: proyectil que reutiliza `arrow.gd` y aplica daño en área al impactar.
- [ ] Speed Buff: buff temporal de velocidad.
- [ ] Acciones `ability_1..3` en el Input Map y en el HUD, con cooldown visible.

**Estados y buffs**
- [ ] Sistema mínimo de status effects (slow, burn, freeze) con duración, aplicado vía `DamageInfo`.
- [ ] Buffs de stats temporales y permanentes (daño, velocidad, regeneración de stamina).

**Enemigos**
- [ ] Segundo enemigo a distancia (dispara proyectiles con el mismo protocolo).
- [ ] Tercer enemigo con carga o embestida (telegrafía su ataque).
- [ ] Pathfinding básico (NavigationRegion2D o A* sobre la grilla) para no quedarse trabado en paredes.
- [ ] Tabla de spawn por piso en `FloorData` (qué enemigos aparecen y con qué peso).
- [ ] Elites: variante con más HP, tinte distinto y un modificador.

**Loot y progresión**
- [ ] Drops de enemigos: oro y curación.
- [ ] Oro en `RunManager` + contador en el HUD.
- [ ] `UpgradeData`: mejoras pasivas elegibles (elige 1 de 3) en las zonas REWARD.
- [ ] Rareza de armas (común/rara/épica) con modificadores de stats.
- [ ] Variantes de arma (`sword_heavy`, multishot del arco, etc.) como nuevos `.tres`.
- [ ] XP y niveles (si encaja con el diseño; en muchos roguelites alcanza con el loot).

**Mazmorra**
- [ ] Nuevos tipos de zona: EVENT, SHOP y BOSS.
- [ ] Piso de jefe cada N pisos (decidido en `DungeonGenerator`, lógica en la escena del boss).
- [ ] Primer boss con 2–3 fases (`PhaseController`, ver `AGENTS.md` §26).
- [ ] Minimapa con las zonas visitadas.
- [ ] Obstáculos y decoración dentro de las zonas (pilares, trampas) para variar el combate.
- [ ] Trampas que usen el protocolo Hitbox (pinchos, explosiones).
- [ ] Mostrar la seed en pausa o en la pantalla de muerte, y poder introducir una seed.

### P3 — Pulido, meta y contenido

- [ ] Screen shake y hit-stop al golpear.
- [ ] Números de daño flotantes.
- [ ] Partículas de muerte de enemigos.
- [ ] Transición (fade) entre pisos.
- [ ] Hub (`guild_tavern.tscn`): punto de partida entre runs.
- [ ] Meta-progresión: moneda persistente para desbloqueos entre runs.
- [ ] Guardado: ajustes y meta-progresión (`user://`).
- [ ] Opciones: volumen, remapeo de controles y pantalla completa.
- [ ] Soporte completo de gamepad (apuntado con el stick derecho).
- [ ] Balance: tabla de DPS por arma/coste y curvas de dificultad por piso.
- [ ] Builds híbridas: sinergias entre arma, habilidad y upgrade (ver `AGENTS.md` §28).
- [ ] Localización ES/EN de los textos de UI.

---

## 4. Cómo usar este archivo

- Al terminar una feature: pásala de §3 a §1 (o márcala `[x]`) y ajusta §2 si cambió una limitación.
- Antes de empezar un item P2+, revisa que los P0/P1 de los que depende estén cerrados
  (`AGENTS.md` §31: no saltar a sistemas posteriores con la base inestable).
- Si un item cambia la arquitectura, actualiza también `AGENTS.md`.
