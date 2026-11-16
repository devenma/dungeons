# Arquitectura, escenas, jugador e input (AGENTS.md §3-9, §33-36, §39)

Parte del contrato de [`AGENTS.md`](../../AGENTS.md); los números de sección son los de ese documento.

El párrafo de dueños del estado (§3) y la tabla perfil vs expedición (§6.3) quedaron en `AGENTS.md`.

---

# 3. Arquitectura conceptual

La arquitectura principal debe mantenerse aproximadamente así:

```text
                         Main
                          │
        ┌─────────────────┼──────────────┬─────────────┐
        │                 │              │             │
        ▼                 ▼              ▼             ▼
  ProfileState          World           UI         RunManager
  (perfil persistente)    │          (expedición)
        │                 │
        │                 ▼
        │           DungeonManager
        │                 │
        │                 ├── DungeonGenerator (grid-merging + TileMap)
        │                 ├── DoorController (zona → zona)
        │                 ├── Spawner (contenido por zona)
        │                 ├── TileMap único (3 capas: floor/wall/door)
        │                 └── ExitArea (transición de piso)
        │
        └── Hondoval (hub: pueblo con locales y la entrada a la cripta)
              ├── Exterior, Guild, Shop, Apothecary, Smithy (áreas)
              └── WorldClock (día/noche)


                         Player
                            │
              ┌─────────────┼─────────────┐
              ▼             ▼             ▼
          Movement        Combat        Health
                            │
                     ┌──────┼──────┐
                     ▼      ▼      ▼
                   Weapon Ability Buff
                     │
                     ▼
                  Hitbox
                     │
                     ▼
                  Hurtbox
                     │
                     ▼
                   Enemy
```


## 3.1. Flujo de juego

```text
Guild / pueblo (día)
  │
  ▼
Entrar al dungeon (noche)
  │
  ▼
Crear / cargar Run (seed, piso, mochila)
  │
  ▼
Explorar zonas y salas
  │
  ▼
Combatir / conseguir loot
  │
  ▼
¿Llegaste al final del dungeon?
  │
  ├── No ──────────────► siguiente piso
  │
  └── Sí ───────────────► pelear con el jefe
                              │
                              ▼
                    Volver al guild con loot
                              │
                              ▼
     Depositar, vender, comprar equipo, avanzar el día
                              │
                              ▼
                         nueva expedición

Muerte durante la expedición
  │
  ▼
Volver al guild
  ├── sin piedra azul: se pierden la mochila, el oro encima y las armas recogidas
  ├── con piedra azul: se gasta una y se conserva todo eso
  ├── se re-rollea la seed del dungeon
  └── se conserva el perfil (oro bancado, almacén, armas aseguradas, desbloqueos)
```

---

# 4. Estructura de directorios

La estructura objetivo del proyecto es:

```text
res://
│
├── scenes/
│   │
│   ├── main/
│   │   └── main.tscn
│   │
│   ├── player/
│   │   └── player.tscn
│   │
│   ├── guild/
│   │   ├── guild.tscn               # Área del gremio: sala, Odran y Maren, almacén, tablón y catre
│   │   └── guild_npc.tscn           # NPC quieto con idle y saludo
│   │
│   ├── town/
│   │   ├── hondoval.tscn            # El pueblo: exterior, interiores, reloj y UI del pueblo (D25)
│   │   ├── interior.tscn            # Interior provisorio de un local
│   │   ├── town_spot.tscn           # Punto de interacción base
│   │   └── town_door.tscn           # Puerta entre áreas
│   │
│   ├── dungeon/                     # chest.tscn, exit.tscn, wall_torch.tscn
│   │
│   ├── rooms/                       # Plantillas de sala hechas a mano
│   │
│   ├── enemies/
│   │   ├── enemy_base.tscn
│   │   └── slime.tscn
│   │
│   ├── weapons/
│   │   └── sword.tscn
│   │
│   ├── projectiles/
│   │   └── arrow.tscn
│   │
│   ├── bosses/
│   │
│   ├── preview/
│   │   └── art_preview.tscn         # Vista previa del estilo de arte (no está en main)
│   │
│   └── ui/
│
├── scripts/
│   │
│   ├── player/
│   │   ├── player.gd
│   │   ├── player_stats.gd
│   │   └── player_controller.gd
│   │
│   ├── profile/
│   │   └── profile_state.gd        # Perfil persistente (user://)
│   │
│   ├── game/
│   │   └── run_manager.gd          # Estado de la expedición
│   │
│   ├── inventory/
│   │   └── inventory.gd            # Slots con apilado (mochila y almacén)
│   │
│   ├── guild/
│   │   ├── guild_room.gd           # Arte de la sala: tiles, pasadas, calcos y objetos
│   │   ├── guild_npc.gd
│   │   └── guild_interactable.gd
│   │
│   ├── town/
│   │   ├── hondoval.gd             # Hub del pueblo: áreas, puertas, tiendas, saludos y pedido de expedición
│   │   ├── town_area.gd            # Un lugar del pueblo; se prende de a uno
│   │   ├── town_exterior.gd        # Exterior: sólidos y puertas desde un mapa de texto, arte de assets/art/town/
│   │   └── town_door.gd
│   │
│   ├── world/
│   │   └── world_clock.gd          # Fases día/noche: tinte, locales cerrados y dormir
│   │
│   ├── dungeon/
│   │   ├── dungeon_generator.gd     # Grid-merging + TileMap renderer
│   │   ├── dungeon_manager.gd       # Orquestación del piso
│   │   ├── door_controller.gd       # Puertas y transiciones entre zonas
│   │   ├── camera_limit_manager.gd  # Cámara por zona y deslizamiento entre zonas
│   │   ├── spawner.gd               # Spawn de contenido por tipo de zona
│   │   ├── floor_dressing.gd        # Ambiente sembrado: antorchas, objetos colgados, calcos
│   │   ├── dungeon_geometry.gd      # Constantes de geometría y roles de tiles
│   │   └── zone.gd                  # Data structures: Zone, Door, ZoneType
│   │
│   ├── audio/
│   │   ├── sfx.gd                   # Sonido suelto que sobrevive al dueño
│   │   └── health_sounds.gd         # Sonidos de golpe y muerte de una entidad
│   │
│   ├── combat/
│   │   ├── health_component.gd
│   │   ├── hurtbox.gd
│   │   ├── hitbox.gd
│   │   ├── hit_stop.gd
│   │   └── damage_info.gd
│   │
│   ├── enemies/
│   │   └── enemy.gd
│   │
│   ├── preview/                     # Scripts y shader de la vista previa de arte
│   │
│   ├── tools/
│   │   ├── build_art_preview_tileset.gd  # Tilesets de la vista previa y del guild (tilesets/guild.tres)
│   │   └── build_crypt_tileset.gd   # Genera tilesets/crypt_dark.tres
│   │
│   └── resources/
│       ├── floor_data.gd
│       └── dungeon_data.gd          # Dungeon: id, pisos, jefe
│
├── resources/
│   ├── items/                       # ItemData, DropTable y sus .tres
│   ├── weapons/                     # WeaponData, SwingData y sus .tres
│   └── dungeons/                    # DungeonData (.tres)
│
├── tilesets/
│
├── art/
│   ├── characters/
│   ├── enemies/
│   ├── weapons/
│   ├── environment/
│   └── effects/
│
├── assets/
│   └── audio/
│       └── sfx/                     # SFX (.wav) y sus AudioStreamRandomizer (.tres)
│
├── tools/
│   └── art/                         # Pipeline de arte fuera del motor (export_room.py, build_crypt_atlas.py)
│
├── docs/
│   └── agents/                      # Detalle de AGENTS.md por tema (arquitectura, combate, dungeon, arte, roadmap)
│
└── ui/
```

No es necesario crear todos los directorios o archivos desde el inicio. Esta estructura representa la arquitectura objetivo y debe crecer de forma incremental.

---

# 5. Escena Main

`main.tscn` es el punto de entrada principal.

Estructura aproximada:

```text
Main
│
├── RunManager
├── ProfileState
│
├── World
│   ├── Hondoval      (exterior, gremio, tienda, botica, herrería, WorldClock)
│   ├── Player
│   ├── DungeonManager
│   │   └── Dungeon          (se crea en cada piso)
│   └── CameraLimitManager
│
└── UI
    ├── HUD              (scenes/ui/hud.tscn: barras, arma, oro, piedra azul, toast)
    ├── BackpackPanel    (scenes/ui/backpack_panel.tscn: mochila y almacén)
    ├── DeathScreen      (scenes/ui/death_screen.tscn: negro breve al volver al guild tras morir)
    └── PauseMenu
```

Responsabilidades de `Main`:

- iniciar la partida;
- inicializar los sistemas principales;
- crear o cargar el estado de partida;
- iniciar el primer piso;
- conectar sistemas globales cuando sea necesario.

`Main` NO debe convertirse en el lugar donde vive toda la lógica del juego.

---

# 6. Estado global y RunManager

## 6.1. GameManager

`GameManager` representa sistemas generales de la aplicación/juego.

Debe utilizarse para lógica verdaderamente global.

## 6.2. RunManager

`RunManager` representa el estado de **una expedición concreta**. No contiene progreso permanente.

Puede contener datos como:

```text
run_seed
current_floor
weapons_obtained
current_weapon
backpack_loot
enemies_defeated
```

El estado que debe sobrevivir al cambio de piso debe pertenecer al `RunManager` o a un sistema equivalente.

No duplicar ese estado dentro de cada escena de piso.

---

# 7. Player

La escena inicial del jugador será:

```text
Player (CharacterBody2D)
│
├── Visuals
│   └── Sprite2D
│
├── CollisionShape2D
│
├── Camera2D
│
├── Hurtbox (Area2D)
│   └── CollisionShape2D
│
└── Weapons
```

## Responsabilidades

El jugador debe encargarse principalmente de:

- recibir input;
- movimiento;
- interacción con el mundo;
- coordinar sus sistemas de combate;
- recibir daño;
- administrar el estado general del personaje.

Evitar convertir `player.gd` en un script gigantesco.

---

# 8. Movimiento

El movimiento inicial será top-down en 8 direcciones.

Debe utilizar acciones abstractas del Input Map:

```text
move_up
move_down
move_left
move_right
```

La implementación inicial debe basarse en `CharacterBody2D`.

Patrón esperado:

```gdscript
var direction := Input.get_vector(
    "move_left",
    "move_right",
    "move_up",
    "move_down"
)

velocity = direction * speed
move_and_slide()
```

No acoplar el código a teclas concretas.

Esto permitirá soportar posteriormente:

- teclado;
- gamepad;
- Steam Deck;
- otros dispositivos de entrada.

---

# 9. Input Map

Acciones actuales del Input Map:

```text
move_up
move_down
move_left
move_right

attack             # Space / clic izquierdo / X (oeste)
swap_weapon        # Tab / Y (norte): cambia el arma equipada
roll               # Shift / B (este): voltereta de esquive (D26 propone reemplazarla por un dash)
ability_1          # 1 / RB: habilidad del slot 1 del arma equipada (D12)
use_potion         # H / LB: toma un vial de sangre de la mochila (D25)

aim_up / aim_down / aim_left / aim_right   # stick derecho: apuntado con gamepad

interact           # F / A (sur)
inventory          # I / Back: muestra la mochila y el almacén
transfer_one       # Shift sostenido / X: en el almacén del gremio mueve una unidad en vez de la pila

pause              # Esc / Start
debug_next_floor   # solo builds de debug
```

El gamepad es el control principal (D8): el movimiento también va en el stick izquierdo y la cruceta.

Las acciones podrán ampliarse conforme aparezcan nuevas mecánicas. Los slots de habilidad del arma equipada (activas 1-4, buffs/debuff Q/E/R) están previstos en D12 y todavía no existen.

Las escenas y scripts deben utilizar los nombres de las acciones, no códigos de teclas directamente.

---

# 33. Dependencias entre sistemas

La dirección de dependencias debe mantenerse aproximadamente así:

```text
Main
 │
 ├── RunManager
 │
 └── DungeonManager
       │
       └── DungeonGenerator

Player
 │
 ├── Movement
 ├── Combat
 └── Health

Combat
 │
 ├── Weapons
 ├── Abilities
 └── Hitbox

Entities
 │
 ├── Hurtbox
 └── Health
```

Evitar dependencias circulares.

Especialmente evitar:

```text
Player → DungeonGenerator → Player
```

Si dos sistemas necesitan comunicarse, preferir:

- señales;
- interfaces simples;
- datos compartidos;
- managers apropiados.

---

# 34. Reglas para nuevos sistemas

Antes de crear un nuevo sistema, comprobar:

1. ¿Tiene una responsabilidad claramente definida?
2. ¿Puede reutilizar un sistema existente?
3. ¿Debe ser un componente, Resource, escena o manager?
4. ¿Está acoplado innecesariamente al Player?
5. ¿Está acoplado innecesariamente al Dungeon?
6. ¿Puede probarse de forma independiente?
7. ¿Necesita realmente ser global?
8. ¿Está agregando complejidad antes de que exista una necesidad?

Si la respuesta indica demasiado acoplamiento, refactorizar antes de continuar.

---

# 35. Regla específica para Player.gd

`player.gd` no debe convertirse en un "God Object".

Si comienza a contener simultáneamente:

- movimiento;
- ataque;
- inventario;
- habilidades;
- buffs;
- estadísticas;
- UI;
- generación de dungeon;
- progresión;

se debe detener el desarrollo de esa funcionalidad y extraer responsabilidades.

El jugador debe coordinar sistemas, no implementar todo el juego.

---

# 36. Regla específica para DungeonGenerator

`DungeonGenerator` debe encargarse de la estructura procedural.

No debe implementar:

- combate;
- IA;
- daño;
- UI;
- lógica de armas;
- lógica de habilidades.

Su responsabilidad termina cuando la estructura del piso está definida y las habitaciones necesarias pueden ser instanciadas.

---

# 39. Datos versus lógica

Regla general:

```text
Resource
    ↓
¿Qué es / qué valores tiene?

Scene / Script
    ↓
¿Cómo se comporta?
```

Ejemplo:

```text
SwordData
    damage = 20
    stamina_cost = 15
    knockback = 30
```

mientras:

```text
Sword.gd
```

determina cómo ejecutar el ataque.

Otros recursos: `DungeonData` (id, pisos, jefe, trofeo, escena de cierre) y `DialogueData` (diálogo data-driven del pueblo y la historia).
