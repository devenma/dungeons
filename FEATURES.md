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
| Arranque | El juego arranca en el guild; el portón del dungeon (F) arma el piso 1. | `guild.gd`, `DungeonManager.start_expedition()` |
| Guild | Sala de una pantalla (480×270) con tablones, chimenea (la única luz cálida, solo toca personajes), almacén en los cofres, tablón de encargos y 7 NPCs quietos con idle; hablarles (F) muestra uno de sus saludos. | `guild.tscn`, `guild_room.gd`, `guild_npc.gd` |
| Tienda | La reducidora compra lo de la mochila a su `ItemData.value` y vende piedras azules a 150 de oro (`fence_shop.tres`); todo en oro bancado. Pausa el juego mientras está abierta y guarda el perfil tras cada trato. | `shop_panel.gd`, `ProfileState.sell()` / `buy()` |
| Inicio de expedición | Seed aleatoria (`randi()`), piso 1, armas = las aseguradas en el perfil. La mochila no se toca. | `RunManager.start_new_run()` |
| Transición de piso | Interactuar (F) en la salida de la zona EXIT genera el piso siguiente con la misma `run_seed`. | `exit_area.gd`, `DungeonManager._start_floor()` |
| Muerte | Al llegar a 0 HP: espera 0.5 s, restaura vida y stamina y vuelve al guild con seed nueva. Sin piedra azul se pierden mochila, oro encima y armas recogidas; con piedra azul se gasta una y se conserva todo (las armas quedan aseguradas en el perfil). | `DungeonManager._return_to_guild()` |
| Estado entre pisos | Seed, piso actual, armas, arma equipada, mochila y oro encima. | `run_manager.gd` |
| Perfil persistente | Oro bancado, almacén del guild (60 slots), armas aseguradas y desbloqueos en `user://profile.json`. Guardado atómico (.tmp + rename); un archivo corrupto se aparta como `.corrupt`. | `profile_state.gd` |

### 1.2. Generación procedural

| Feature | Detalle |
|---|---|
| Grid-merging | Grilla de 2–4 × 2–3 celdas; cada celda es una pantalla de sala (15×9 tiles de 32 px = 480×288 px, `DungeonGeometry.CELL_TILES`). La grilla crece si hace falta para que entren las zonas. Cortes guillotina: zonas rectangulares exactas, sin solapes ni espacios muertos, de al menos `min_zone_cells` (1×1 celda). Sobre 500 seeds del piso 1: 71% de zonas de 1×1, 16% de 1×2 o 2×1, el resto más grandes. |
| Cantidad de zonas por profundidad | `zone_count_by_floor_depth`: piso 1 → 4–6 zonas, piso 10 → 7–12. |
| Tipos de zona | 1 START, 1 EXIT y el resto COMBAT o REWARD (`reward_ratio` 0.3). |
| Validación | `validate_layout()`: rectángulos exactos, cobertura completa, tamaño mínimo, tope de START, puertas en aristas compartidas y todas las zonas alcanzables desde START. Si falla, reintenta con otra seed derivada hasta 5 veces y después falla con `push_error` (sin fallback). Cubierto por `assert_zone_partition` (500 seeds × 3 profundidades). |
| Tope de START | La zona START se recorta primero en el origen a `FloorData.start_zone_max_cells` (1×1 celda = una pantalla por defecto); si es menor que `min_zone_cells`, gana el mínimo. |
| Determinismo | La misma `(run_seed, floor_number)` produce el mismo piso; cubierto por un test. |
| Puertas | Posición irregular en las aristas compartidas; varias por arista si es larga (`multi_door_threshold`). |
| Render | Un TileMap único con el tileset de la cripta oscura (`crypt_dark.tres`): tope + cara de 2 filas en la pared norte, topes en las laterales y la sur, piso periódico por `(tx % 3, ty % 3)` con AO al pie de las paredes, puertas en hueco o en arco y escalera de bajada de 2×2 en la salida, que se entra solo desde el sur (nunca bajo un arco norte ni pegada a una puerta). Las paredes bloquean su tile completo. |
| Ambiente | `floor_dressing.gd`, sembrado por la seed: una antorcha encendida por zona en la cara norte (dos si es ancha) con luz que solo toca personajes, soportes apagados, objetos colgados, telarañas y calcos de piso. |

### 1.3. Exploración

| Feature | Detalle |
|---|---|
| Movimiento | 8 direcciones, `speed` 60, Input Map (WASD/flechas, stick izquierdo o cruceta). |
| Voltereta | `roll` (Shift / B): 64 px en 0,4 s hacia donde se mueve (o hacia donde mira), cuesta 25 de stamina, 0,3 s de invulnerabilidad desde el inicio. No se cancela; el ataque pedido durante la voltereta sale al terminar. |
| Gamepad (D8) | Stick izquierdo mueve, stick derecho apunta, X ataca, B rueda, A interactúa, Y cambia de arma, Back abre la mochila, Start pausa. |
| Cámara por zona | `Camera2D` limitada al rectángulo de la zona actual y en píxeles enteros. Al cruzar una puerta se desliza a la zona nueva en 0.4 s (`slide_seconds`) con el juego en pausa, estilo Zelda; mientras tanto el jugador entra caminando solo hasta el piso de la zona, frente a la puerta (un tile más adentro si entra por un arco norte, `north_landing_tiles`). Dentro de una zona de varias pantallas sigue al jugador. |
| Cruce de puertas | Detección en dos fases (entrar/salir del área): volver atrás no cuenta como cruce. |
| Bloqueo de combate | Entrar a una zona COMBAT sin limpiar cierra sus puertas hasta matar a todos los enemigos; se cierran recién cuando los pies del jugador pisan el piso interior (nunca sobre el hueco, el arco ni la cara), así la puerta no queda encima del cuerpo. |
| Interacción | Acción `interact` (F / A) para cofres y salida. Muerto no se usa la salida. |

### 1.4. Combate

| Feature | Detalle |
|---|---|
| Protocolo de daño único | Hitbox/proyectil → Hurtbox → HealthComponent → `died`. Funciona en las dos direcciones (jugador ↔ enemigo). |
| Capas de colisión | 5 capas centralizadas en `CollisionLayers`. |
| Recursos | Stamina 100 (regen 20/s), se rellena al cambiar de piso o al morir. Cada ataque cuesta stamina; no hay cooldowns. Todavía no hay maná (D19). |
| Apuntado | Mouse/Space apuntan al cursor; el gamepad apunta con el stick derecho o, si está suelto, hacia donde mira el jugador. |
| Espada | Melee, combo de 3 golpes (`WeaponData.combo`, un `SwingData` por golpe): preparación → hitbox activa → recuperación. Atacar durante el golpe activo o la recuperación encadena el siguiente; también hay 0.25 s de margen al terminar. Perder el margen o no tener stamina vuelve al golpe 1. Daño 10 / 12 / 22, coste 20 / 20 / 30, knockback 220 / 260 / 420; el 3.º es más lento. Cada golpe juega la animación de ataque del jugador sincronizada con sus fases, un smear por dirección (corte, revés y golpe de arriba) y su sonido. El jugador queda plantado desde la preparación hasta el fin de la recuperación, salvo un paso hacia adelante en el golpe activo (`SwingData.step_distance`: 4 / 4 / 8 px); la orientación se fija al empezar el golpe. El 3.º golpe hace temblar la cámara 3 px al impactar. |
| Arco | Flecha de 400 px/s, daño 8, coste 12, knockback 120. Moverse no impide disparar, pero abre un desvío de hasta 12° por lado (`WeaponData.aim_spread_*`: llega al máximo en 0,25 s caminando y se cierra en 0,5 s quieto). Dos marcas tenues junto al jugador muestran el desvío. |
| Bastón | Proyectil mágico de 280 px/s, daño 14, coste 18, knockback 140 (reutiliza `arrow.gd` y el script del arco). Desvío de hasta 16° por lado al moverse. |
| Proyectiles | Mueren al impactar al primer enemigo, al chocar con una pared o a los 2 s. Vuelan con la hoja de su dirección (flecha o bolo de bilis) y dejan un efecto de impacto. |
| Knockback | `KnockbackComponent`: el golpe empuja al objetivo con velocidad inicial = `knockback` (px/s), que decae a 0 en 0.2 s. Mientras dura, el empuje reemplaza el movimiento propio y el enemigo no actúa. |
| Aturdimiento | Un golpe aceptado corta el ataque del enemigo y lo deja sin actuar `EnemyData.stagger_seconds` (slime 0,35 s, errante 0,3 s). Con `poise_while_attacking` (errante) el golpe no corta la telegrafía ni el ataque ya comprometido. El errante juega su animación de golpe; el slime, un aplaste. |
| Temblor de cámara | `CameraShake` mueve el `offset` de la cámara en px enteros: 2 px al recibir un golpe, 3 px en el impacto del 3.º golpe del combo, 0,14 s. No toca los límites ni la transición de zona. |
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
| Mochila y almacén | `Inventory`: slots con apilado. Mochila de 20 slots (`RunManager`), almacén de 60 (`ProfileState`). En el guild, el cofre del almacén (o `inventory`) abre el panel y pausa el juego: activar un slot (clic, Enter o A) pasa la pila al otro lado, con Shift sostenido o X pasa una unidad, y "Guardar todo" deposita la mochila y banca el oro. Lo que no entra queda donde estaba y el perfil se guarda tras cada cambio. En la mazmorra el almacén se ve pero no se toca. |

### 1.6. Enemigos

| Feature | Detalle |
|---|---|
| Slime | 30 HP, velocidad 60, daño 8, knockback 160. Detecta a 120 px, ataca a 20 px con una ventana de 0.2 s y cooldown de 1.2 s. Sprite fijo con aplaste/estiramiento por tween. |
| Cadáver errante | 55 HP, velocidad 28, daño 14, knockback 260. Detecta a 140 px, ataca a 22 px: se queda quieto 0.6 s alzando el brazo (telegrafía) antes de abrir la hitbox; cooldown de 1.8 s. Animaciones del kit en 4 direcciones; al morir queda su cuerpo en el piso. |
| IA | Persecución en línea recta dentro del radio de detección (sin pathfinding). |
| Spawn | Pool por piso en `FloorData.enemy_pool` (`EnemySpawnData`: escena, coste de amenaza, peso, tamaño de grupo, a distancia, tope por zona) sorteado con la seed hasta gastar `threat_budget_per_cell` (San Ulmo: 4/5/6, D22). Siempre cabe un grupo a distancia; los siguientes no pasan de un tercio del presupuesto. Una zona por piso puede quedar para el élite solo (`elite_chance`: 0 / 1 / 0,25). Sin pool (rigs de test) se usa la lista fija `Spawner.enemy_scenes`. Persiguen en toda su zona y la rodean. |
| Bestiario de la cripta | Rata (8 HP, grupos de 5-8, sale volando), reptante (salta 60 px tras 0,35 s), escupebilis (bilis en arco que deja un charco que daña; retrocede si te acercás), guardia osario (escudo frontal de 120° que gira lento; el 3.er golpe del combo rompe la guardia 0,8 s), cultista (virote de sangre y levanta errantes de 35 HP; un golpe corta la invocación) y el Cosido (élite de 96 px, 220 HP, sin aturdimiento). Arte del kit V3 en 4 direcciones. |
| Muerte | Corta la IA y las colisiones, juega la muerte (animación o aplaste + estallido de sangre) y recién después libera al enemigo. |
| Datos | `EnemyData` (.tres). |

### 1.7. Audio

| Feature | Detalle |
|---|---|
| Buses | `default_bus_layout.tres`: Master, SFX, Ambience y UI. |
| SFX | Placeholders procedurales en `assets/audio/sfx/` con `AudioStreamRandomizer` (variaciones, tono ±8 %). Suenan: 3 tajos de espada (uno por golpe del combo), golpe en carne (slime) y hueso (errante), muerte de enemigo, golpe y muerte del jugador, pasos en los frames de apoyo, voltereta, disparo e impacto de flecha y de proyectil mágico, cofre, recogida de objeto, oro, piedra azul al morir, puertas que se traban y se abren. |
| Ambiente | Loop de mazmorra en los pisos, crepitar en cada antorcha encendida (se oye de cerca) y loop del guild. |

### 1.8. UI

| Feature | Detalle |
|---|---|
| Kit de UI | Texturas, 9-slice y fuentes pixel del kit de la cripta (`assets/ui/`, `assets/fonts/`); tema por defecto del proyecto en `resources/ui/ui_theme.tres`. |
| Barras de vida y stamina | Marco del kit con relleno, rastro de daño (alcanza al relleno a los 0.3 s) y parpadeo del marco al bajar (`resource_bar.gd`). |
| Arma equipada | Ícono del arma en un slot (`weapon_icon.gd`). |
| Toast de recogida | "Recogido: X" con los íconos de lo recogido, 1.5 s con fade y sonido; el botín del mismo frame se suma al toast y los repetidos se agrupan (x3). |
| Oro y piedra azul | Placas con oro bancado + oro encima y cantidad de piedras azules en la mochila. |
| Mochila y almacén | `inventory` (I) abre las dos grillas de slots de 20×20 con ícono, cantidad, borde de rareza y tooltip (nombre + descripción); mouse, teclado o cruceta. |
| Pausa | Esc (`pause`) pausa el juego y muestra un menú (Continuar / Salir); otro Esc o Continuar lo cierra. |
| Idiomas | ES/EN con `tr()` desde `locale/strings.csv`; español por defecto. Para cambiar: `internationalization/locale/test` en `project.godot` (`"en"`). |

### 1.9. Herramientas de desarrollo

- 50 tests headless (`scripts/test/`), todos verdes.
- Vista previa del estilo de arte: `scenes/preview/art_preview.tscn` (no está en `main.tscn`); su tileset sale de `scripts/tools/build_art_preview_tileset.gd`.
- Tileset del juego: `tools/art/build_crypt_atlas.py` arma el atlas y `scripts/tools/build_crypt_tileset.gd` genera `tilesets/crypt_dark.tres`.
- **Advertencia:** `tilesets/crypt_dark.tres` se genera con `scripts/tools/build_crypt_tileset.gd` (colisiones desde `DungeonGeometry.is_solid_atlas`): no editarlo a mano, se pisa al regenerar.
- Atajo de debug **N** (acción `debug_next_floor`): salta al siguiente piso. Solo corre en builds de debug.

---

## 2. Limitaciones conocidas y deuda

| Problema | Impacto |
|---|---|
| Sin números de daño | El combate se lee por el destello, el empuje y el sonido. |
| El cofre es un `ColorRect` | Placeholder visual. |
| SFX placeholder y sin música | Los sonidos son sintéticos (sirven para timing, no para el juego final) y no hay música. |
| La mochila no se guarda entre sesiones | Una piedra azul comprada (va a la mochila) se pierde si se cierra el juego sin depositarla; el oro ya se cobró. |
| Diálogo y tienda provisorios | Caja de texto sin nombre ni retrato, fuente por defecto y textos de respaldo en inglés hasta que entren las traducciones. |
| Pantalla de muerte breve | Negro con lo que pasó con el botín (piedra azul gastada o expedición perdida) y fundido al guild. Todavía sin resumen de la run (piso, enemigos). |
| Cierre de la Madre | Falta la escena de cierre (D14); la Escalera del Farol usa el arte de la escalera de bajada y la *Nana* no tiene sonido propio. |
| Habilidades: solo el slot 1 | Una activa por arma; faltan los slots 2-4, Q/E/R y las opciones por slot. |
| Los `.uid` están en el gitignore | Los UIDs cambian entre máquinas. |

---

## 3. Backlog (TODOs)

Ya está en `main` y documentado en §1: knockback, i-frames, hit flash, pausa y tope de START (PR #6).

### P0 — base confiable y feel

**Generador y cámara**
- [x] Arreglar el solape de `_merge_cells` (rectángulos exactos) y agregar un tamaño mínimo de zona.
- [x] Cámara en zonas más chicas que el viewport: ya no hay zonas más chicas que el viewport (cada celda es una pantalla).
- [x] Salas del tamaño de la pantalla y cámara que se desliza entre zonas (feedback del equipo: menos caminata, sin parpadeo).

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
- [x] Inventario de mochila (slots con apilado) y almacén del guild; panel con `inventory` (I) y pase de objetos entre los dos en el guild.
- [x] Vuelta al guild en vez de wipe (`_return_to_guild()`), perdiendo lo de la expedición.
- [x] Piedra azul: consumible que, al morir, te lleva al guild conservando el loot (D1).
- [x] Guild con tienda en `scenes/guild/`: vender loot y comprar piedras azules.
- [x] Comprar mejoras permanentes en la tienda: vendas, peto y cinturón (vida y aguante máximos, D11).
- [~] Días: `ProfileState.day` avanza en cada vuelta al gremio y el HUD lo muestra ahí; faltan las fases día/noche con efecto (`WorldClock`).
- [ ] Guardado del perfil y de los ajustes (`user://`).

**Expedición y jefe**
- [x] `DungeonData` (id, cantidad de pisos, jefe) y techo de pisos: San Ulmo tiene 3.
- [x] Zonas BOSS y EVENT (antesala del jefe).
- [x] Primer boss con 2 fases: la Madre de la Fosa (D21), con barra de vida y Escalera del Farol.
- [x] La *Nana* y los charcos de bilis de la Madre.
- [x] Usar los multiplicadores de `FloorData` en `Spawner` al instanciar enemigos.
- [x] Escalar la cantidad de enemigos según el piso y el tamaño de la zona (`Spawner.enemies_per_screen`).

**Flujo y presentación**
- [x] HUD: label de piso actual (`FloorLabel`, "Piso 2 de 3").
- [ ] Pantalla de muerte: piso alcanzado, enemigos derrotados y botón de reintentar.
- [ ] Menú principal (Jugar / Salir) como escena de entrada.
- [ ] Prompt "F" visible al estar cerca de un cofre o de la salida.
- [ ] Indicador visual de "puertas cerradas" y efecto al limpiar la zona (el sonido ya existe).
- [ ] Sprite real para el cofre, con animación de abrir.
- [ ] Transición (fade) entre pisos.
- [x] Base de localización ES/EN (`tr()` + CSV) de los textos de UI.

**Audio (último del slice)**
- [ ] Música de pueblo y de dungeon.
- [x] SFX placeholder de golpe, muerte, ataque, recogida y puerta.
- [ ] SFX definitivos (grabados o de packs libres).

### P2 — profundidad

**Mazmorra**
- [x] Pool de plantillas de sala (`RoomTemplate` en `resources/rooms/`, 6 plantillas).
- [x] Obstáculos movibles que consumen stamina (D20), puestos por las plantillas.
- [x] Llave y bóveda tras puertas trabadas + validación de solvabilidad en el generador.
- [x] Zona EVENT con el Altar del Voto: cura a cambio de carne, diezmo o piedra azul (D23). SHOP sigue pendiente.
- [ ] Minimapa con las zonas visitadas.
- [x] Pilares dentro de las salas COMBAT (plantillas); faltan los escombros decorativos.
- [ ] Trampas que usen el protocolo Hitbox (pinchos, explosiones).
- [ ] Mostrar la seed en pausa o en la pantalla de muerte, y poder introducir una seed.

**Habilidades (Fase 8 parte B, D12)**
- [~] `AbilityData` por kit de arma (`WeaponData.abilities`, índice = slot); hoy solo el slot 1.
- [x] Maná (segundo `StaminaComponent`) + barra en el HUD + coste dual atómico en `AbilityData` (D19).
- [~] Primer corte: 1 activa por arma (tajo giratorio, disparo triple, bola de fuego); faltan las pasivas.
- [ ] Ice Nova: AoE con ralentización (primer crowd control).
- [x] Fireball: proyectil que reutiliza `arrow.gd` y explota en área al impactar.
- [ ] Speed Buff: buff temporal de velocidad.
- [x] `ability_1` en el Input Map (1 / RB) y en el HUD, junto al arma; parpadea en rojo si no alcanza el coste.

**Estados y buffs**
- [ ] Sistema mínimo de status effects (slow, burn, freeze) con duración, aplicado vía `DamageInfo`.
- [ ] Buffs de stats temporales y permanentes (daño, velocidad, regeneración de stamina/maná).

**Enemigos**
- [x] Enemigos a distancia: escupebilis (bilis en arco + charco) y cultista (virote de sangre + invocación).
- [x] Enemigo que telegrafía su ataque (cadáver errante).
- [x] Enemigos con embestida o salto: reptante, rata y guardia osario (con escudo).
- [ ] Pathfinding básico (NavigationRegion2D o A* sobre la grilla) para no quedarse trabado en paredes.
- [x] Pool de spawn por piso en `FloorData` con presupuesto de amenaza (D22). Faltan las oleadas para zonas de varias pantallas.
- [x] Élite: el Cosido, solo en su zona, con gancho que tira del jugador (la voltereta lo esquiva).

**Loot y progresión**
- [ ] `UpgradeData`: mejoras pasivas elegibles (elige 1 de 3) en las zonas REWARD.
- [ ] Rareza de armas (común/rara/épica) con modificadores de stats.
- [ ] Variantes de arma (`sword_heavy`, multishot del arco, etc.) como nuevos `.tres`.
- [ ] Meta-progresión: desbloqueos persistentes entre expediciones (D1).
- [ ] Builds híbridas: sinergias entre arma, habilidad y upgrade (ver `AGENTS.md` §28).
- [ ] Balance: tabla de DPS por arma/coste y curvas de dificultad por piso.

**Historia y pueblo**
- [x] Sistema de diálogo data-driven (`DialogueData` + `DialoguePanel`).
- [~] NPCs del pueblo: saludo fijo y una línea según cómo volviste (muerte, piedra azul, victoria); faltan las conversaciones largas.
- [x] Escena de cierre al limpiar San Ulmo por primera vez.

### P3 — contenido y pulido

- [ ] Granja y crafting (solo si se aprueba; hoy fuera del alcance).
- [ ] Relaciones con NPCs.
- [ ] HD-2D (luces y normal maps) si se decide.
- [x] Screen shake.
- [ ] Números de daño flotantes.
- [ ] Partículas de muerte de enemigos.
- [x] Voltereta (acción `roll`, reemplaza al dash) con coste de stamina e i-frames.
- [ ] Opciones: volumen, remapeo de controles y pantalla completa.
- [x] Gamepad en todas las acciones (apuntado con el stick derecho).
- [ ] Prompts de UI para gamepad.
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
