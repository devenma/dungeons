# Hondoval jugable: plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Objetivo:** Hondoval como pueblo caminable con placeholders a escala definitiva:
- el exterior y 4 interiores;
- los NPCs en sus locales y la entrada a la cripta en las afueras;
- día y noche;
- el vial de sangre;
- lo que llevás encima se guarda mientras estás en el pueblo.

**Arquitectura:**
- Un nodo `World/Hondoval` reemplaza a `World/Guild` como el hub con el que habla `DungeonManager`, con la
  misma interfaz: `expedition_requested`, `set_active`, `spawn_position`, `camera_rect` y `set_mood`.
- Cada lugar del pueblo es un `TownArea` y en cada momento hay uno solo activo. Las puertas mueven al jugador
  de un área a otra y reencuadran la cámara con `CameraLimitManager.frame_rect`.
- La fase (día o noche) y lo que llevás encima viven en `ProfileState`. `WorldClock` aplica la fase.
- El vial es un componente nuevo del jugador, `PotionDrinker`.

**Tecnología:** Godot 4.7.2, GDScript, tests headless con `SceneTree` (`./run.sh test [filtro]`).

**Spec:** [`odd/tasks/hondoval-design.md`](hondoval-design.md) (D25 en `DECISIONES.md`).

**Alcance de este plan:** los pasos 1, 2, 3 y 5 del orden sugerido del diseño. El arte (paso 4) tiene su propio
plan, que se escribe cuando exista la Tarea 4, porque depende del trazado final y de la prueba de terreno con
PixelLab. Los aventureros nuevos también van ahí, porque necesitan sus recetas del kit V3. Hasta entonces, el
gremio queda con Odran Vell y Maren Tull.

## Restricciones globales

- **Stack:** Godot 4.7.2, solo GDScript, sin addons.
- **Estilo de código:**
  - Tipos explícitos en todo y sin `:=` cuando el tipo no es obvio (AGENTS §32).
  - Comentarios bilingües ES / EN y `##` al inicio de cada script nuevo diciendo de qué es dueño (§44.1,
    `.claude/rules/gdscript.md`).
- **Headless:** los scripts que corren sin editor cargan por ruta (`preload`) y no dependen de `class_name`.
  Después de crear un `class_name` hay que correr `./run.sh import`.
- **Señales:** se conectan antes de la llamada que las emite (§44.16).
- **Números en datos** (`@export` o `.tres`), nunca sueltos en el código:
  - el vial cura **35**, se toma en **0,8 s** y mientras tanto la velocidad es **0,3** de la normal;
  - cuesta **40** de oro y se llevan **3** como máximo;
  - de la puerta del gremio a la entrada de la cripta hay como mucho **`player.speed × 10` px** (10 s a pie).
- **Medidas:** salen de `DungeonGeometry` (`TILE_SIZE`, `CELL_TILES`). No se escribe 32 a mano.
- **Textos:**
  - todo lo visible pasa por `tr()` o `UiText.tr_or`;
  - las claves nuevas van a `locale/strings.csv` (ES/EN), con "tú" como el resto de los textos;
  - los nombres nuevos se agregan a `locale/GLOSARIO.md`.
- **Input:** solo por nombre de acción. La acción nueva es `use_potion` (tecla H, botón LB). Las teclas 1-4 y
  Q/E/R están reservadas (D12).
- **Git:**
  - rama `feat/hondoval` desde `dev`, PR contra `dev`;
  - un commit por tarea, en español y sin atribución;
  - pedir el visto bueno antes de cada commit, push o PR (§44.3, `.claude/rules/workflow.md`).
- **Cierre de cada tarea:** `./run.sh test` completo en verde.

## Foco de revisión

1. **Guardado viejo** sin las claves nuevas: tiene que cargar de día, sin nada encima y sin marca de
   expedición. Test en la Tarea 1.
2. **Cerrar el juego en la cripta con una piedra azul en la mochila:** se pierde igual, porque cerrar adentro
   cuenta como morir sin piedra. Test en la Tarea 1.
3. **Tomar el vial cuando no corresponde** (vida llena, muerto, rodando o en medio de un golpe): se rechaza y
   no gasta el vial. Test en la Tarea 3.
4. **Dos puntos de interacción encimados** (una puerta pegada a un NPC): un solo `interact` dispararía los dos.
   Test en las Tareas 4 y 5.
5. **De noche, guardar el botín:** el almacén del gremio tiene que funcionar, porque el gremio no cierra. Test
   en la Tarea 6.

---

### Task 1: Perfil con fase, lo que llevás encima y marca de expedición

**Archivos:**
- Modificar: `scripts/profile/profile_state.gd` (campos, `reset_profile`, `load_profile`, `save_profile`).
- Crear: `scripts/test/assert_profile_town_state.gd`.

**Interfaces que produce:**
- Campos nuevos, que se guardan con su mismo nombre como clave del JSON. `SAVE_VERSION` sigue en 1 y las
  claves que falten toman el valor por defecto.
  - `var night: bool = false`
  - `var carried_backpack: Dictionary = {}`, en el formato de `Inventory.to_dict()`
  - `var carried_gold: int = 0`
  - `var expedition_in_progress: bool = false`
- Funciones nuevas:
  - `func set_night(value: bool) -> void`: emite `profile_changed`.
  - `func store_carried(backpack: Inventory, gold: int) -> void`: guarda una foto de la mochila y el oro.
    No emite nada.
  - `func restore_carried(backpack: Inventory) -> int`: hace `backpack.load_dict(carried_backpack)` y
    devuelve `carried_gold`.
  - `func begin_expedition() -> void` y `func end_expedition() -> void`: prenden y apagan la marca.
- `load_profile()`: si la marca guardada está prendida, deja `carried_backpack = {}`, `carried_gold = 0`,
  `night = true` y `expedition_in_progress = false`. Cerrar el juego en la cripta cuenta como morir sin
  piedra azul.
- Ninguna de estas funciones guarda sola: guarda quien la llama (`save_profile()`), como hoy.

- [ ] **Paso 1: escribir el test.** Mismo molde que `assert_dialogue.gd`: `extends SceneTree`, `_check`,
  `SAVE_PATH = "user://test_profile_town.json"`, borrar el archivo al final y `quit(0 o 1)`. Se usa un
  `ProfileState` suelto (`load("res://scripts/profile/profile_state.gd").new()`, con `save_path` asignado
  antes de `root.add_child`).

```gdscript
_check(not profile.night and profile.carried_gold == 0 and not profile.expedition_in_progress,
		"a fresh profile is day and carries nothing")
profile.set_night(true); profile.save_profile(); profile.load_profile()
_check(profile.night, "night survives save and load")
# Archivo escrito a mano: {"version": 1, "banked_gold": 5, "day": 3}
_check(not profile.night and profile.carried_backpack.is_empty() and profile.day == 3,
		"an old save without the new keys loads by day with nothing carried")
var pack: Inventory = Inventory.new(20); pack.add(BLUE_STONE, 2)
profile.store_carried(pack, 37); profile.save_profile(); profile.load_profile()
var restored: Inventory = Inventory.new(20)
_check(profile.restore_carried(restored) == 37 and restored.count_of(BLUE_STONE) == 2,
		"what you carry in town survives save and load")
profile.store_carried(pack, 37); profile.begin_expedition(); profile.save_profile(); profile.load_profile()
var after_quit: Inventory = Inventory.new(20)
_check(profile.restore_carried(after_quit) == 0 and after_quit.is_empty() and profile.night
		and not profile.expedition_in_progress,
		"closing the game in the crypt loses what you carried, blue stone included, and wakes you at night")
profile.begin_expedition(); profile.end_expedition()
_check(not profile.expedition_in_progress, "ending the expedition clears the mark")
```

- [ ] **Paso 2:** `./run.sh test assert_profile_town_state` → FALLA (no existen `night`, `store_carried`...).
- [ ] **Paso 3:** implementar los campos y las funciones de arriba en `profile_state.gd`. `reset_profile()`
  pone los cuatro campos en su valor por defecto.
- [ ] **Paso 4:** `./run.sh test assert_profile_town_state` → OK.
- [ ] **Paso 5:** `./run.sh test` → todo OK. Commit (con visto bueno):
  `feat(perfil): fase del día, lo que llevás encima y marca de expedición (D25)`.

---

### Task 2: Volver de noche y guardar lo que llevás en el pueblo

**Archivos:**
- Modificar: `scripts/dungeon/dungeon_manager.gd`:
  - `_ready`: después de `run_manager.start_new_run(...)`, restaurar lo que llevabas y conectar
    `backpack_changed`;
  - `start_expedition`;
  - `_go_home`;
  - función nueva `_on_backpack_changed`.
- Modificar: `scripts/game/run_manager.gd` (`set_backpack_gold`).
- Modificar: `scripts/test/assert_altar_offerings.gd:103`.
- Crear: `scripts/test/assert_town_carry.gd`.

**Interfaces:**
- Usa de la Tarea 1: `set_night`, `store_carried`, `restore_carried`, `begin_expedition` y `end_expedition`.
- Produce `RunManager.set_backpack_gold(gold: int) -> void`: asigna el oro y emite `backpack_changed`.
- Comportamiento:
  - **Al arrancar:** `set_backpack_gold(profile.restore_carried(run_manager.backpack))`. `start_new_run`
    no toca la mochila, así que el orden es seguro.
  - **`start_expedition`:** `store_carried(...)`, `begin_expedition()` y `save_profile()` antes de
    `_start_floor()`.
  - **`_go_home`:** `advance_day()` pasa a ser `set_night(true)`. También `end_expedition()` y
    `store_carried(...)` con la mochila que quedó (después de conservarla o perderla), antes de
    `save_profile()`.
  - **`_on_backpack_changed`:** si `_in_guild` (es decir, en el pueblo), `store_carried(...)` y
    `save_profile()`.

- [ ] **Paso 1: escribir `assert_town_carry.gd`** sobre `main.tscn`, con `save_path` de prueba:

```gdscript
run_manager.add_loot([BLUE_STONE], 25)                    # en el gremio
_check(_saved()["carried_gold"] == 25, "loot carried in town is saved with the profile")
dm.call("start_expedition")
_check(_saved()["expedition_in_progress"] == true, "starting an expedition marks it in the save")
dm.call("_go_home", true)
_check(profile.night and profile.day == 1, "coming back makes it night and does not advance the day")
_check(not _saved()["expedition_in_progress"], "coming back clears the mark")
# Segunda instancia de main.tscn con el mismo save_path y la marca apagada
_check(rm2.backpack.count_of(BLUE_STONE) == 1 and rm2.backpack_gold == 25,
		"a new session restores what you carried")
```

  `_saved()` lee y parsea el JSON de `SAVE_PATH`.
- [ ] **Paso 2:** `./run.sh test assert_town_carry` → FALLA.
- [ ] **Paso 3:** implementar el comportamiento de arriba.
- [ ] **Paso 4:** en `assert_altar_offerings.gd:103`, cambiar el chequeo por
  `profile.night and profile.day == 1`, con la etiqueta `"coming back makes it night"`.
- [ ] **Paso 5:** `./run.sh test` → todo OK. Commit:
  `feat(pueblo): se vuelve de noche y lo que llevás se guarda en el pueblo (D25)`.

---

### Task 3: Vial de sangre

**Archivos:**
- Modificar: `resources/items/item_data.gd`:
  - `@export var heal_amount: int = 0`, la vida que cura al tomarlo (0 = no se toma);
  - `@export var max_carried: int = 0`, el tope de unidades encima (0 = sin tope).
- Crear: `resources/items/vial_sangre.tres`: `id = &"vial_sangre"`, `name_key = "item.vial_sangre.name"`,
  `desc_key = "item.vial_sangre.desc"`, `category = CONSUMABLE`, `rarity = COMMON`, `max_stack = 3`,
  `value = 15`, `heal_amount = 35`, `max_carried = 3`.
- Crear: `assets/art/items/vial_salud.png`, copiado de `~/gamedev/_quizas_usemos/01_iconos_loot/icons/16/`.
  Es el ícono del `.tres`.
- Modificar: `scripts/profile/profile_state.gd` `buy()`: rechaza sin cobrar si `item.max_carried > 0` y
  `backpack.count_of(item) >= item.max_carried`.
- Modificar: `scripts/combat/health_component.gd`: `func heal(amount: int) -> int` devuelve lo curado. No hace
  nada si está muerto, no pasa el máximo y emite `health_changed`.
- Crear: `scripts/player/potion_drinker.gd` (`class_name PotionDrinker`) y un nodo `Potions` en
  `scenes/player/player.tscn`.
- Modificar: `scripts/player/player.gd`:
  - `@onready var _potions: PotionDrinker = get_node_or_null("Potions") as PotionDrinker`;
  - `hold_attack` devuelve `true` (descarta el ataque) mientras toma;
  - la voltereta no sale mientras toma;
  - la velocidad se multiplica por `_potions.move_scale` mientras toma.
- Modificar: `scripts/player/ability_caster.gd` `_busy()`: también mientras toma.
- Modificar: `project.godot`: acción `use_potion` con el mismo formato que `ability_1`: tecla
  `physical_keycode 72` (H) y joypad `button_index 9` (LB).
- Modificar: `scripts/ui/hud_counters.gd` y `scenes/ui/hud.tscn`: una placa `VialPlate` con `%VialLabel`
  que muestra `"%d/%d" % [count, VIAL.max_carried]`, con `const VIAL: ItemData = preload(...)`.
- Modificar: `locale/strings.csv` (`item.vial_sangre.name`: "Vial de sangre" / "Blood vial", y su `.desc`) y
  `locale/GLOSARIO.md`.
- Crear: `scripts/test/assert_blood_vial.gd`.

**Interfaces que produce (`PotionDrinker`):**
- Exports:
  - `@export var potion: ItemData` (es `vial_sangre.tres`);
  - `@export var drink_seconds: float = 0.8`;
  - `@export var move_scale: float = 0.3`;
  - `@export var run_manager_path: NodePath = NodePath("../../../RunManager")`.
- Señales: `signal drink_started`, `signal drank(healed: int)` y `signal drink_refused`.
- `func try_drink() -> bool`:
  - rechaza (emite `drink_refused`, no gasta) si está muerto, rodando, en un golpe que planta, ya tomando,
    sin vial en la mochila o con la vida llena;
  - si no, saca un vial **al empezar** y cura `potion.heal_amount` **al terminar**, salvo que haya muerto;
  - un golpe no corta la toma.
- `func is_drinking() -> bool`.
- Escucha `use_potion` en `_unhandled_input`.
- Cuenta el tiempo en `_physics_process`, no con un `Timer`, porque en carga los timers fallaron
  (lección de `burst.gd`).

- [ ] **Paso 1: escribir `assert_blood_vial.gd`** sobre `main.tscn`, con `save_path` de prueba y el jugador
  en el gremio:

```gdscript
profile.banked_gold = 500
for i in 3: profile.buy(rm.backpack, VIAL, 40)
_check(not profile.buy(rm.backpack, VIAL, 40) and profile.banked_gold == 380, "buying stops at three vials")
_check(not drinker.try_drink() and rm.backpack.count_of(VIAL) == 3, "full health refuses and keeps the vial")
roll.try_roll(Vector2.RIGHT)
_check(not drinker.try_drink() and rm.backpack.count_of(VIAL) == 3, "rolling refuses and keeps the vial")  # foco 3
await _physics_seconds(0.5)
weapon.call("try_attack", Vector2.RIGHT)                   # la espada planta al jugador
_check(not drinker.try_drink() and rm.backpack.count_of(VIAL) == 3, "mid-swing refuses and keeps the vial")
await _physics_seconds(1.0)
health.take_damage(DamageInfo.new(50))                     # queda en 50
_check(drinker.try_drink() and drinker.is_drinking() and rm.backpack.count_of(VIAL) == 2,
		"drinking starts and spends one vial")
_check(player.call("hold_attack", Vector2.RIGHT), "you cannot attack while drinking")
# roll: InputEventAction "roll" por player._unhandled_input -> roll.is_rolling() == false
_check(not roll.is_rolling(), "you cannot roll while drinking")
# con "move_right" apretado, después de un physics_frame
_check(is_equal_approx(player.velocity.x, player.speed * 0.3), "drinking slows you to 30%")
await _physics_seconds(0.5)
_check(health.current_health == 50, "the heal waits for the end of the drink")
health.take_damage(DamageInfo.new(10))                     # un golpe no la corta (ya pasaron los i-frames)
await _physics_seconds(0.4)
_check(health.current_health == 75, "the vial heals 35 at the end even after a hit")
_check(hud_vial_label.text == "2/3", "the HUD shows vials as x/3")
# muerto: health.take_damage(DamageInfo.new(999)) -> try_drink() == false y no gasta
```

  Helpers:
  - `_physics_seconds(s)` espera `physics_frame` hasta juntar `s` segundos de física.
  - `weapon` es `player.get_node("Weapons").get_child(0)`, es decir, la espada montada.
  - `roll` es `player.get_node("Roll")`.
  - `drinker` es `player.get_node("Potions")`.
  - `hud_vial_label` es `%VialLabel`.
  - `DamageInfo.new(n)` no tiene empuje, así que no pisa la velocidad del chequeo del 30 %.

- [ ] **Paso 2:** `./run.sh import` y después `./run.sh test assert_blood_vial` → FALLA.
- [ ] **Paso 3:** implementar lo de arriba. El tope también aplica si la mochila está llena: `buy` ya
  rechaza cuando `add` no entra.
- [ ] **Paso 4:** `./run.sh test assert_blood_vial` → OK. Después `./run.sh test` → todo OK. Commit:
  `feat(combate): vial de sangre que se toma con riesgo (D25, D23)`.

---

### Task 4: Hondoval: áreas, puertas, exterior de bloqueo y entrada a la cripta

**Archivos:**
- Crear: `scripts/town/town_area.gd`. Es la base de cada lugar del pueblo.
- Crear: `scripts/town/town_door.gd`, que extiende `res://scripts/guild/guild_interactable.gd`, y
  `scenes/town/town_door.tscn` (Area2D + CollisionShape2D de 1×1 tile + `Hint` Label).
- Crear: `scripts/town/town_exterior.gd`, que extiende `town_area.gd`: arma el bloqueo desde un mapa de texto.
- Crear: `scenes/town/interior.tscn`. Es una base de interior provisoria:
  - `TownArea` de 480×270 con un piso `ColorRect`;
  - un `StaticBody2D` con los bordes;
  - `Things`, `Markers/from_street` y una `StreetDoor` (`town_door.tscn`) abajo al centro.
- Crear: `scripts/town/hondoval.gd` y `scenes/town/hondoval.tscn`, con estos hijos:
  - `Exterior`;
  - `Guild` (instancia de `guild.tscn`);
  - `Shop`, `Apothecary` y `Smithy` (tres instancias de `interior.tscn`);
  - `TownUI` (CanvasLayer).
- Modificar: `scripts/guild/guild.gd`:
  - extiende `res://scripts/town/town_area.gd`;
  - se borran su `set_active`, `camera_rect`, `camera_bounds`, `expedition_requested` y el cableado de
    `ExpeditionDoor`;
  - el resto (NPCs, almacén, tablón, tienda) queda para la Tarea 5.
- Modificar: `scenes/guild/guild.tscn`:
  - `ExpeditionDoor` pasa a ser `StreetDoor`, con el script `town_door.gd`;
  - `SpawnPoint` pasa a `Markers/spawn`;
  - se agrega `Markers/from_street` junto a la puerta.
- Modificar: `scenes/main/main.tscn`: `World/Guild` se reemplaza por `World/Hondoval` y
  `DungeonManager.guild_node_path` pasa a `NodePath("../Hondoval")`.
- Modificar los tests que usan `World/Guild`, `expedition_requested` en el gremio o `ExpeditionDoor`:
  - `assert_death_loot`, `assert_death_reset`, `assert_dialogue`, `assert_guild_deposit`;
  - `assert_guild_shop`, `assert_room_transition` y `assert_storage_transfer`.
  - Los cambios: `World/Guild` → `World/Hondoval/Guild`, la señal ahora sale de `World/Hondoval` y
    `ExpeditionDoor` → `StreetDoor`.
- Crear: `scripts/test/assert_town_layout.gd`.

**Interfaces que produce:**
- **`town_area.gd`:**
  - `@export var area_id: StringName` y `@export var camera_bounds: Rect2i = Rect2i(0, 0, 480, 270)`;
  - `func set_active(active: bool) -> void`: `visible`, `process_mode`, `collision_enabled` de todo
    `TileMapLayer` descendiente, `visible` de sus hijos `CanvasLayer` (no heredan la visibilidad) y un hijo
    `Ambience` si existe;
  - `func camera_rect() -> Rect2i`, igual que el del gremio de hoy;
  - `func marker_position(marker: StringName) -> Vector2`: posición global de `Markers/<marker>`;
  - para la Tarea 5: `@export var shop_data: ShopData` y `@export var shopkeeper_path: NodePath`.
- **`town_door.gd`:** `@export var target_area: StringName`, `@export var target_marker: StringName` y
  `@export var closes_at_night: bool = false`. Se agrega al grupo `"town_door"`.
- **`hondoval.gd`:**
  - `signal expedition_requested`;
  - `@export var camera_manager_path: NodePath = NodePath("../CameraLimitManager")`;
  - `@export var fade_seconds: float = 0.25`;
  - `func set_active(active: bool) -> void`: prende o apaga la raíz (`visible` y `process_mode`) y
    `TownUI`. Con `true` deja activa solo `Guild`, porque siempre se vuelve al gremio; con `false` apaga
    todas las áreas;
  - `func spawn_position() -> Vector2`: `Guild.marker_position(&"spawn")`;
  - `func camera_rect() -> Rect2i`: la del área actual;
  - `func set_mood(mood: String) -> void`: en esta tarea le pasa el ánimo a `Guild`;
  - `func go_to(area: StringName, marker: StringName) -> void`, en un solo paso:
    - apaga el área actual y prende la otra;
    - ubica al jugador (grupo `"player"`) en el marcador;
    - llama a `frame_rect(player, camera_rect())`;
    - pone `TownUI/Fade` (un `ColorRect` negro a pantalla completa que ignora el mouse) en `modulate.a = 1` y
      lo lleva a 0 en `fade_seconds`.
  - `func current_area() -> StringName`;
  - conecta cada nodo del grupo `town_door` a `go_to(door.target_area, door.target_marker)`, y
    `Exterior/CryptEntrance.interacted` a `expedition_requested.emit`.
- **Ids:** `area_id` del exterior `&"exterior"` y de los interiores `&"guild"`, `&"shop"`, `&"apothecary"` y
  `&"smithy"`. La `StreetDoor` de cada interior apunta a `&"exterior"` y a su marcador `<área>_door`
  (se ajusta por instancia en `hondoval.tscn`).
- **`town_exterior.gd`:** `const MAP: PackedStringArray` de 60×18 caracteres. Lo pinta con `ColorRect`
  provisorios (un color por carácter) y un `StaticBody2D` con un rectángulo por celda sólida, todo con
  `DungeonGeometry.TILE_SIZE`.
  - Leyenda: `#` empalizada, `H` fachada, `C` catedral, `~` agua negra, `+` tumba y `o` pozo son sólidos;
    `.` es suelo.
  - Las letras `S`, `A`, `T` y `G` son las puertas de herrería, botica, tienda y gremio. Crean un
    `town_door.tscn` llamado `SmithyDoor`, `ApothecaryDoor`, `ShopDoor` y `GuildDoor`, hacia `smithy`,
    `apothecary`, `shop` y `guild` (marcador `from_street`), y un marcador `<área>_door` en la celda de abajo.
  - `E` crea `CryptEntrance` (`guild_interactable.tscn`, con la pista `ui.prompt.descend`) y el marcador
    `crypt` debajo.
  - Mapa sugerido. Se puede retocar mientras los tests sigan en verde:

```text
############################################################
#.HHHHHHHH..HHHHHHH..............HHHHHHHHHH.#...CCCCCCCCC..#
#.HHHHHHHH..HHHHHHH..............HHHHHHHHHH.#...CCCCCCCCC..#
#.HHHHHHHH..HHHHHHH..............HHHHHHHHHH.#...CCCCCCCCC..#
#.HHHHHHHH..HHHHHHH..............HHHHHHHHHH.#...CCCCCCCCC..#
#.HHHSHHHH..HHHAHHH..............HHHHHHHHHH.#...CCCCCCCCC..#
#................................HHHHGHHHHH.#...CCCCECCCC..#
#...........................................#..............#
#..........................................................#
#........................oo................................#
#.HHHHHHHH...............oo.................#..+..+...+....#
#.HHHHHHHH..~~~~~~~.........................#..............#
#.HHHHHHHH..~~~~~~~.........................#.....+...+..+.#
#.HHHHHHHH..~~~~~~~.........................#..+...........#
#.HHHHTHHH..................................#......+..+....#
#...........................................#..............#
#...........................................#..............#
############################################################
```

  (Las filas 8 y 9 abren la empalizada en la columna 44: esa es la puerta del pueblo. Cada fila tiene que
  medir exactamente 60. El test lo verifica.)

- [ ] **Paso 1: escribir `assert_town_layout.gd`** sobre `main.tscn`, esperando `physics_frame` después de
  cada `go_to`:

```gdscript
_check(town.current_area() == &"guild" and player.global_position == guild.marker_position(&"spawn"),
		"the game starts in the guild")
guild.get_node("StreetDoor").interacted.emit()
_check(town.current_area() == &"exterior" and player.global_position == exterior.marker_position(&"guild_door")
		and not guild.visible and _camera_limits() == exterior.camera_rect(), "the street door takes you outside")
_check(fade.modulate.a == 1.0, "a door starts from black")
await _physics_seconds(town.fade_seconds + 0.1)
_check(fade.modulate.a == 0.0, "and fades back in")
for row: String in exterior.MAP: _check(row.length() == 60, "map rows are 60 wide")
_check(exterior.marker_position(&"guild_door").distance_to(exterior.marker_position(&"crypt"))
		<= player.speed * 10.0, "from the guild door to the crypt is at most 10 s on foot")
for m: StringName in [&"guild_door", &"shop_door", &"apothecary_door", &"smithy_door", &"crypt"]:
	_check(_space_free(exterior.marker_position(m)), "%s arrival spot is walkable" % m)
_check(not _interact_spots_overlap(exterior), "no two interaction spots overlap")   # foco 4
for door_area: StringName in [&"shop", &"apothecary", &"smithy"]:
	# entrar por su puerta y salir por su StreetDoor vuelve al marcador <área>_door
	_check(_round_trip(door_area), "%s door leads in and back out" % door_area)
exterior.get_node("CryptEntrance").interacted.emit()
_check(not town.visible and dm.get("_dungeon") != null, "the crypt entrance starts the expedition")
dm.call("_go_home", true)
_check(town.current_area() == &"guild", "coming back always lands in the guild")
```

  Helpers:
  - `_camera_limits()` arma un `Rect2i` con los `limit_left/top/right/bottom` de la `Camera2D` del jugador.
  - `_space_free(p)` da `true` si `intersect_point` en `p`, con la máscara de mundo, no devuelve nada.
  - `_interact_spots_overlap(area)` da `true` si se cruzan los rectángulos globales de dos `Area2D` del área
    que tengan `RectangleShape2D`.
  - `_round_trip(a)` hace `go_to(&"exterior", &"<a>_door")`, emite la puerta del exterior que lleva a `a`,
    comprueba `current_area() == a`, emite su `StreetDoor` y vuelve al marcador `<a>_door`.
  - `_physics_seconds` es el de la Tarea 3.
- [ ] **Paso 2:** `./run.sh test assert_town_layout` → FALLA.
- [ ] **Paso 3:** implementar `town_area.gd`, `town_door.gd`, `town_exterior.gd` y `hondoval.gd`, armar las
  escenas y cambiar `main.tscn`.
- [ ] **Paso 4:** `./run.sh import` y `./run.sh test assert_town_layout` → OK.
- [ ] **Paso 5:** actualizar los 7 tests de la lista. `./run.sh test` → todo OK. Commit:
  `feat(pueblo): Hondoval caminable con locales y la cripta en las afueras (D25)`.

---

### Task 5: Los NPCs en sus locales y una tienda por local

**Archivos:**
- Modificar: `scenes/town/hondoval.tscn`.
  - Se mueven los nodos de NPC de `Guild/Things`:
    - `Fence` → `Shop/Things/Fence`;
    - `Healer` → `Apothecary/Things/Healer`;
    - `Blacksmith` → `Smithy/Things/Blacksmith`;
    - `RefugeeChild` → `Exterior/Things/Nela`, en la plaza;
    - `RefugeeWounded` → `Exterior/Things/Tome`, en las afueras.
  - `Guildmaster` y `Questgiver` se quedan.
  - `GuildUI/DialogueBox` y `GuildUI/ShopPanel` pasan a `TownUI`.
  - Cada interior lleva su `shop_data` y su `shopkeeper_path`.
- Borrar: `scripts/guild/guild.gd`. Su lógica pasa a `hondoval.gd` y la raíz de `guild.tscn` queda con
  `town_area.gd` (`area_id = &"guild"`).
- Modificar: `scripts/town/hondoval.gd`. Se le suma lo que hacía `guild.gd`, cableado por áreas:
  - `open_storage()`;
  - el tablón;
  - el saludo con `_mood` y `_told`, en `set_mood(mood)`;
  - `_set_hint(spot, key, fallback)`;
  - `open_shop(area)`.
- Modificar: `resources/shop/shop_data.gd`:
  - `@export var title_key: String = "ui.shop.merchant_title"`;
  - `@export var lines_prefix: String = "npc.merchant.shop"`;
  - `@export var buys_loot: bool = true`;
  - `item` puede ser `null`.
- Modificar: `scripts/ui/shop_panel.gd`:
  - `open(run_manager, profile, data: ShopData = null)`: con `null` usa el `shop_data` exportado;
  - `_say(line: String)` busca `"%s.%s" % [lines_prefix, line]` y usa como respaldo el texto en inglés de
    hoy;
  - sin `item` esconde `%BuyButton`, y sin `buys_loot` esconde `%SellTitle` y `%SellList`;
  - `buy()` se fija en el tope antes que en el oro: si `item.max_carried > 0` y ya llevás esa cantidad, dice
    la línea `capped` y devuelve `false`.
- Modificar: `resources/shop/fence_shop.tres`: `upgrades = []`, así Ilse queda con la piedra azul y la compra
  de loot.
- Crear: `resources/shop/apothecary_shop.tres`: `item = vial_sangre`, `price = 40`, `upgrades = [vendas]`,
  `title_key = "ui.shop.apothecary_title"`, `lines_prefix = "npc.healer.shop"`, `buys_loot = false`.
- Crear: `resources/shop/smithy_shop.tres`: `item = null`, `upgrades = [peto, cinturon]`,
  `title_key = "ui.shop.smithy_title"`, `lines_prefix = "npc.blacksmith.shop"`, `buys_loot = false`.
- Modificar: `locale/strings.csv`. Las líneas `npc.healer.shop.*` y `npc.blacksmith.shop.*` ya existen; se
  suman:
  - `ui.shop.apothecary_title` y `ui.shop.smithy_title`;
  - `ui.prompt.enter` y `ui.prompt.leave` (`%s Entrar` / `%s Salir`);
  - `npc.healer.shop.upgrade`, `npc.healer.shop.full` y `npc.healer.shop.capped`.
- Modificar los tests:
  - `assert_guild_shop`: la tienda está en `Shop` y las mejoras en la botica y la herrería;
  - `assert_dialogue`: la línea de ánimo se prueba con el `Guildmaster`, porque la `Healer` ahora abre su
    tienda;
  - `assert_storage_transfer` y `assert_guild_deposit`: `open_storage` está en `Hondoval`.
- Crear: `scripts/test/assert_town_venues.gd`.

**Interfaces:**
- Usa: `TownArea.shop_data` y `shopkeeper_path` (Tarea 4), y `vial_sangre.tres` (Tarea 3).
- Produce:
  - `Hondoval.open_shop(area: Node) -> void`;
  - `Hondoval.open_storage() -> void`;
  - `Hondoval.say(text: String) -> void`, que la Tarea 6 usa para "Cerrado".
- Los tenderos abren su tienda en vez de saludar. Hoy Ilse ya lo hace así.

- [ ] **Paso 1: escribir `assert_town_venues.gd`:**

```gdscript
for path: String in ["Shop/Things/Fence", "Apothecary/Things/Healer", "Smithy/Things/Blacksmith",
		"Exterior/Things/Nela", "Exterior/Things/Tome", "Guild/Things/Guildmaster", "Guild/Things/Questgiver"]:
	_check(town.has_node(path), "%s is in its place" % path)
_check(not town.has_node("Guild/Things/Fence") and not town.has_node("Guild/Things/Healer"),
		"the guild keeps only the adventurers' people")
# entrar a cada local y hablar con su tendero
_check(_opens(&"shop", FENCE_SHOP) and sell_list.visible and buy_button.visible, "Ilse buys loot and sells stones")
_check(_opens(&"apothecary", APOTHECARY_SHOP) and not sell_list.visible, "the apothecary sells the vial and bandages")
_check(_opens(&"smithy", SMITHY_SHOP) and not buy_button.visible, "the smithy sells the breastplate and the belt")
_check(_active_areas() == 1, "only one area is active at a time")
_check(not _interact_spots_overlap(town.get_node("Exterior")), "NPCs and doors do not overlap")   # foco 4
```

  Helpers:
  - `_opens(a, data)` hace `go_to(a, &"from_street")` y emite el `interacted` del tendero (el nodo de
    `shopkeeper_path`). Da `true` si `TownUI/ShopPanel` queda visible con `shop_data == data`, y lo cierra.
  - `_active_areas()` cuenta las áreas visibles.
  - `sell_list` y `buy_button` son `%SellList` y `%BuyButton` del panel.
  - `FENCE_SHOP`, `APOTHECARY_SHOP` y `SMITHY_SHOP` precargan sus `.tres`.
- [ ] **Paso 2:** `./run.sh test assert_town_venues` → FALLA.
- [ ] **Paso 3:** mover nodos, borrar `guild.gd`, sumar a `hondoval.gd` y generalizar `ShopPanel` y
  `ShopData`.
- [ ] **Paso 4:** `./run.sh test assert_town_venues` → OK. Actualizar los 4 tests de la lista y correr
  `./run.sh test` → todo OK.
- [ ] **Paso 5:** commit:
  `feat(pueblo): cada NPC en su local, botica y herrería con su tienda (D25)`.

---

### Task 6: Día y noche (`WorldClock`)

**Archivos:**
- Crear: `scripts/world/world_clock.gd` y un nodo `World/Hondoval/WorldClock`.
- Crear: `World/Hondoval/NightTint` (`CanvasModulate`, `color = Color(0.42, 0.45, 0.62)`, que se ajusta en
  el inspector).
- Modificar: `scenes/guild/guild.tscn`: un `Bed` (interactable con `Hint`) en uno de los catres.
- Modificar: `scripts/town/hondoval.gd`:
  - las puertas con `closes_at_night` no pasan de noche: `say(tr("ui.town.closed"))` y la pista cambia a
    `ui.prompt.closed`;
  - `Bed`: `if not clock.sleep(): say(tr("ui.town.not_sleepy"))`;
  - `set_active(true)` llama a `clock.refresh()`.
- Modificar: `scenes/town/hondoval.tscn`: `closes_at_night = true` en las puertas `S`, `A` y `T`. La del
  gremio y las de salida de los interiores no cierran.
- Modificar: `scripts/ui/floor_label.gd`: en el pueblo muestra `ui.hud.day_night` ("Día %d, noche") cuando es
  de noche, y se actualiza con `profile_changed`.
- Modificar: `locale/strings.csv`: `ui.prompt.sleep`, `ui.prompt.closed`, `ui.town.closed`,
  `ui.town.not_sleepy` y `ui.hud.day_night`.
- Crear: `scripts/test/assert_world_clock.gd`.

**Interfaces que produce (`WorldClock`):**
- Exports: `@export var profile_state_path: NodePath = NodePath("../../../ProfileState")` y
  `@export var tint_path: NodePath = NodePath("../NightTint")`.
- `signal phase_changed(night: bool)`: solo cuando cambia.
- `func is_night() -> bool`.
- `func refresh() -> void`: `tint.visible = profile.night` y emite si cambió. Se llama con
  `profile_changed`.
- `func sleep() -> bool`:
  - de noche: `profile.advance_day()`, `profile.set_night(false)`, `profile.save_profile()` y devuelve
    `true`;
  - de día: devuelve `false` sin tocar nada.

- [ ] **Paso 1: escribir `assert_world_clock.gd`:**

```gdscript
_check(not clock.is_night(), "a new game starts by day")
dm.call("start_expedition"); dm.call("_go_home", true)
_check(clock.is_night() and tint.is_visible_in_tree(), "coming back from the crypt it is night")
town.call("open_storage")
_check(backpack_panel.visible, "the storage still works at night")                    # foco 5
backpack_panel.call("set_open", false)
guild.get_node("StreetDoor").interacted.emit()
exterior.get_node("ShopDoor").interacted.emit()        # nombre que town_exterior le da a la puerta "T"
_check(town.current_area() == &"exterior" and dialogue_label.text == TranslationServer.translate("ui.town.closed"),
		"the shops are closed at night")
exterior.get_node("GuildDoor").interacted.emit()
_check(town.current_area() == &"guild", "the guild stays open at night")
_check(floor_label.text == TranslationServer.translate("ui.hud.day_night") % 1, "the HUD says it is night")
guild.get_node("Bed").interacted.emit()
_check(profile.day == 2 and not clock.is_night() and not _saved()["night"], "sleeping at night opens the next day")
guild.get_node("Bed").interacted.emit()
_check(profile.day == 2, "sleeping by day does nothing")
dm.call("start_expedition")
_check(not tint.is_visible_in_tree(), "the night tint never reaches the crypt")
```

  Helpers: `_saved()` como en la Tarea 2. `dialogue_label` es `TownUI/DialogueBox/Label`. `tint` es
  `World/Hondoval/NightTint`.
- [ ] **Paso 2:** `./run.sh test assert_world_clock` → FALLA.
- [ ] **Paso 3:** implementar `WorldClock`, la cama, las puertas cerradas, el tinte y el HUD.
- [ ] **Paso 4:** `./run.sh test assert_world_clock` → OK. Después `./run.sh test` → todo OK. Commit:
  `feat(pueblo): día y noche con WorldClock, dormir y locales cerrados (D25, D2)`.

---

### Task 7: Textos, glosario, documentación y prueba en el juego

**Archivos:**
- Modificar: `locale/GLOSARIO.md`. Entradas: Hondoval, la botica, la herrería, el vial de sangre, la catedral
  de San Ulmo y la noche (fase).
- Modificar: `AGENTS.md`:
  - §3: el hub es Hondoval y `WorldClock` existe;
  - §4: `scenes/town/`, `scripts/town/` y `scripts/world/world_clock.gd`;
  - §5: el árbol de `Main`, con `World/Hondoval`;
  - §9: `use_potion`;
  - §24: se vuelve al gremio de noche;
  - §30 Fase 10: `WorldClock` ✅;
  - §43: la lista.
- Modificar: `FEATURES.md` (días y fases, botica, vial), `README.md` (estado de la Fase 10) y `DECISIONES.md`:
  en el **[IMPACTO]** de D25, qué quedó hecho y qué queda para el plan de arte.

- [ ] **Paso 1:** `./run.sh test assert_text_consistency` → OK con las claves nuevas. Si falla, corregir el
  término según el glosario y repetir.
- [ ] **Paso 2:** actualizar los documentos de la lista. Solo lo que cambió: AGENTS.md ya es largo (§17 del
  catálogo).
- [ ] **Paso 3:** `./run.sh test` → todo OK. Copiar la salida real al PR.
- [ ] **Paso 4:** abrir el juego (`./run.sh`) con un perfil de prueba y sacar capturas al scratchpad: el
  gremio, la calle de día, la calle de noche, cada local y la entrada a la cripta. Las capturas no se
  commitean: van en un comentario del PR.
- [ ] **Paso 5:** commit:
  `docs: Hondoval, WorldClock y vial de sangre en AGENTS, FEATURES, README y D25`.
  Después pedir el visto bueno para push y PR contra `dev`.
