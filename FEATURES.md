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
| Inicio de run | Seed aleatoria (`randi()`), piso 1, inventario reseteado a la espada. | `RunManager.start_new_run()` |
| Transición de piso | Interactuar (F) en la salida de la zona EXIT genera el piso siguiente con la misma `run_seed`. | `exit_area.gd`, `DungeonManager._start_floor()` |
| Muerte y reinicio | Al llegar a 0 HP: espera 0.5 s, restaura vida y stamina, **nueva run** (nueva seed, piso 1). | `DungeonManager._on_player_died()` |
| Estado persistente entre pisos | Seed, piso actual, armas obtenidas y arma equipada. | `run_manager.gd` |

### 1.2. Generación procedural

| Feature | Detalle |
|---|---|
| Grid-merging | Grilla de 4–8 × 4–6 celdas (8×8 tiles de 32 px cada una). Partición guillotina con seed: zonas rectangulares exactas, sin solapes ni espacios muertos. |
| Cantidad de zonas por profundidad | `zone_count_by_floor_depth`: piso 1 → 3–5 zonas, piso 10 → 6–12. |
| Tipos de zona | 1 START, 1 EXIT y el resto COMBAT o REWARD (`reward_ratio` 0.3). |
| Validación | BFS START→EXIT. Si falla, reintenta hasta 5 veces y después usa un layout de fallback. |
| Tope de START | `FloorData.start_zone_max_cells` (2×2 celdas = 16×16 tiles por defecto): el generador aísla la esquina START a ese tamaño. |
| Tamaño mínimo de zona | `FloorData.zone_min_cells` (2×2 celdas = 512×512 px, contiene el viewport de 480×270). La partición nunca genera zonas menores. |
| Determinismo | La misma `(run_seed, floor_number)` produce el mismo piso; cubierto por un test. |
| Puertas | Posición irregular en las aristas compartidas; varias por arista si es larga (`multi_door_threshold`). |
| Render | Un TileMap único con un tileset pre-autorado (`dungeons_v2.tres`). Paredes con colisión y piso con tinte según el tipo de zona. |

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
| Pausa | Esc (`pause`) pausa el juego y muestra un menú (Resume / Quit); otro Esc o Resume lo cierra. |

### 1.8. Herramientas de desarrollo

- 33 tests headless (`scripts/test/`), todos verdes.
- **Advertencia:** no re-ejecutar `scripts/tools/build_dungeon_tileset.gd`. Sobrescribe las colisiones y los ajustes autorados a mano en `tilesets/dungeons_v2.tres`.
- Atajo de debug **N** (acción `debug_next_floor`): salta al siguiente piso. Solo corre en builds de debug.

---

## 2. Limitaciones conocidas y deuda

| Problema | Impacto |
|---|---|
| `enemy_health/damage_multiplier` no se leen | La dificultad no sube con el piso. |
| Solo hay animaciones `Idle_Down` / `Walk_Down` | El sprite no mira arriba ni a los lados (solo usa `flip_h`). |
| Sin números de daño ni sonido al golpear | El combate se lee solo por el destello y el empuje. |
| El cofre es un `ColorRect` | Placeholder visual. |
| `guild_tavern.tscn` no está conectada | Escena de hub sin flujo de entrada ni salida. |
| Sin audio | No hay música ni SFX. |
| La muerte reinicia al instante | No hay pantalla de muerte ni resumen de la run. |
| No existen `DungeonData` ni la tienda | No hay techo de pisos ni economía de compra/venta; el pueblo es un placeholder. |
| No existe maná ni coste dual | Todas las habilidades gastan solo stamina; el maná llega con la Fase 8 parte B (D19). |
| Doble `RunManager` (autoload + nodo en escena) | Riesgo de usar la instancia equivocada. |
| Los `.uid` están en el gitignore | Los UIDs cambian entre máquinas. |

---

## 3. Backlog (TODOs)

Ya está en `main` y documentado en §1: knockback, i-frames, hit flash, pausa y tope de START (PR #6), más el generador de partición exacta con mínimo 2×2.

### P0 — base confiable y feel

**Generador y cámara**
- [x] Arreglar el solape de `_merge_cells` (rectángulos exactos) y agregar un tamaño mínimo de zona.
- [x] Cámara en zonas más chicas que el viewport: resuelto por el mínimo de 2×2 celdas (512×512 px > 480×270).

**Feel de combate**
- [x] Hit-stop al impactar.
- [x] Visual del swing de la espada (arco procedural, sin arte).
- [x] Combo de 3 golpes en `sword.gd`.
- [ ] Animaciones de 4 direcciones (Idle/Walk Up, Side, Down).

**Estabilidad y docs**
- [x] Actualizar `README.md`, `AGENTS.md` y `FEATURES.md` a la dirección v2.
- [ ] Dejar una sola instancia de `RunManager` (quitar el autoload o el nodo de escena).
- [ ] Commitear los `.uid` (sacarlos de `.gitignore`).

### P1 — vertical slice v2

**Perfil, economía y pueblo**
- [x] `ProfileState` persistente en `user://` (oro, equipo; desbloqueos y pueblo llegan con D2).
- [~] Oro: drops de enemigos y contador en el HUD (hecho el oro; falta la curación).
- [x] Retorno al pueblo en vez de wipe (`_return_to_town()`), perdiendo el loot de la run.
- [ ] Objeto de retorno que conserva el loot.
- [ ] Pueblo mínimo con tienda (vender loot, comprar equipo). El placeholder vive en `scenes/town/town.tscn`; `scenes/hub/guild_tavern.tscn` no carga (le faltan PNGs).
- [ ] `WorldClock` con fases día/noche.
- [~] Guardado en `user://`: perfil hecho (`profile.json`); ajustes pendientes.

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
- [ ] Tercer enemigo con carga o embestida (telegrafía su ataque).
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
