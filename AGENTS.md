# AGENTS.md — Dungeon 2D con historia

# 1. Propósito del proyecto

Este documento define la arquitectura, convenciones y dirección técnica del videojuego 2D desarrollado con Godot.

Su objetivo principal es mantener la coherencia entre iteraciones de desarrollo y evitar que nuevas mecánicas introduzcan acoplamiento innecesario o contradigan decisiones arquitectónicas existentes.

La fuente de verdad de diseño es [`DECISIONES.md`](DECISIONES.md). Si este documento la contradice, gana `DECISIONES.md` y hay que corregir este documento.

El juego es un **dungeon crawler con historia** 2D centrado en:

- **explorar el dungeon**, que es el núcleo de la experiencia;
- combatir en **tiempo real, estilo ARPG**: hack n' slash oscuro, duro y pesado, con sensación *beat 'em up* (peso, knockback, hit-stop y combos);
- avanzar a través de dungeons procedurales armados con salas diseñadas a mano;
- volver a un **pueblo persistente** con NPCs, tienda y economía;
- construir el poder del personaje mediante equipo y mejoras, no mediante XP;
- superar jefes al final de cada dungeon.

Referencias de juego: *Moonlighter* + *Stardew Valley*, con exploración de cámara cenital tipo *Minish Cap* / *A Link to the Past*. Referencia de atmósfera y ambiente: *Fear & Hunger* (D15), con paleta de tonos apagados (dirección visual en §38.1 y [`BIBLIA_ARTE.md`](BIBLIA_ARTE.md)).

La muerte **no borra el progreso**: se pierde la expedición y el loot de la mochila, no el perfil (oro bancado, equipo, desbloqueos y pueblo). Ver D1 en `DECISIONES.md`.

La prioridad durante el desarrollo es construir primero un **vertical slice jugable** y ampliar el sistema progresivamente.

---

# 2. Principios generales

### 2.1. Priorizar sistemas simples y componibles

No crear sistemas monolíticos.

Evitar especialmente:

- `Player.gd` con toda la lógica del personaje;
- `DungeonGenerator.gd` responsable de generar, dibujar, poblar y administrar habitaciones;
- enemigos que implementen directamente sistemas de daño incompatibles entre sí;
- armas con lógica completamente acoplada al jugador.

Preferir componentes y sistemas independientes.

### 2.2. Separar datos de comportamiento

Cuando un objeto tenga muchos valores configurables, considerar utilizar `Resource` personalizados.

Ejemplos:

- `WeaponData`
- `AbilityData`
- `EnemyData`
- `FloorData`
- eventualmente `UpgradeData`, `LootData`, etc.

El comportamiento debe vivir en scripts/escenas; los datos configurables deben poder modificarse desde el Inspector cuando sea razonable.

### 2.3. No sobrearquitecturar antes de necesitarlo

La arquitectura debe permitir crecimiento, pero no se deben crear abstracciones complejas sin una necesidad real.

Primero implementar la versión mínima funcional.

Después refactorizar cuando exista evidencia de que una abstracción mejora el código.

### 2.4. Cada sistema debe tener una responsabilidad clara

Ejemplos:

- `Player`: controla el personaje.
- `DungeonGenerator`: genera la estructura procedural.
- `DungeonManager`: administra el piso actual.
- `RunManager`: conserva el estado de la expedición.
- `ProfileState`: conserva el perfil persistente.
- `HealthComponent`: administra vida.
- `Hitbox`: representa una fuente de daño.
- `Hurtbox`: representa una entidad que puede recibir daño.

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
        └── Guild (hub: almacén y puerta de expedición)
              └── WorldClock (día/noche, previsto)


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

`ProfileState` es el perfil persistente (oro bancado, almacén del guild, armas aseguradas, desbloqueos). `RunManager` es **solo** el estado de la expedición (seed, piso actual, loot de la mochila, oro encima y armas recogidas en esta expedición) y muere con ella. `Guild` (`scenes/guild/`) es el hub donde arranca el juego y se vuelve al morir; `WorldClock` (fases día/noche) todavía no existe. No crear managers nuevos para estas responsabilidades: ya tienen dueño.

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
│   │   ├── guild.tscn               # Hub: sala, NPCs, almacén, tienda y portón de expedición
│   │   └── guild_npc.tscn           # NPC quieto con idle y saludo
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
│   │   ├── guild.gd                # Hub: depósito, tienda, saludos y pedido de expedición
│   │   ├── guild_room.gd           # Arte de la sala: tiles, pasadas, calcos y objetos
│   │   ├── guild_npc.gd
│   │   └── guild_interactable.gd
│   │
│   ├── world/
│   │   └── world_clock.gd          # Fases día/noche
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
│   ├── Guild
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

## 6.3. Perfil vs expedición

Dos capas de estado, separadas a propósito (D1 en `DECISIONES.md`):

| Capa | Vive en | Contenido | Persiste |
|---|---|---|---|
| Perfil | `ProfileState` (`user://profile.json`) | Oro bancado, almacén del guild, armas aseguradas, desbloqueos | Sí, entre sesiones |
| Expedición | `RunManager` | Seed del dungeon, piso actual, loot de la mochila, oro encima y armas recogidas en esta expedición | No, muere con la expedición |

Al morir sin piedra azul: se vuelve al guild, se pierde todo lo de la expedición (la mochila y lo que se agarró o equipó durante la expedición) y se re-rollea la seed del dungeon. Lo guardado en el guild (oro bancado, almacén, desbloqueos) queda. Si se muere con una piedra azul en la mochila, se gasta y se vuelve al guild conservando el loot (D1).

Ninguna capa debe absorber a la otra: `ProfileState` no conoce el piso actual y `RunManager` no guarda oro ni desbloqueos.

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
roll               # Shift / B (este): voltereta de esquive (reemplaza al dash previsto)
ability_1          # 1 / RB: habilidad del slot 1 del arma equipada (D12)

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

# 10. Sistema de combate

El combate debe ser independiente del tipo de arma.

Arquitectura conceptual:

```text
Player
 │
 └── CombatController
        │
        ├── Weapon
        ├── Ability
        └── Target
```

El sistema de daño debe ser reutilizable:

```text
Attacker
   │
   ▼
Hitbox
   │
   ▼
Hurtbox
   │
   ▼
Health
   │
   ▼
Death
```

Debe funcionar tanto para:

```text
Player → Enemy
```

como:

```text
Enemy → Player
```

y:

```text
Projectile → Enemy
Explosion → Player
Trap → Player
Boss attack → Player
Spell → Enemies
```

---

# 11. Hitbox y Hurtbox

## Hitbox

Una `Hitbox` representa algo que puede causar daño.

Ejemplos:

```text
SwordHitbox
ArrowHitbox
FireballHitbox
EnemyAttackHitbox
ExplosionHitbox
```

## Hurtbox

Una `Hurtbox` representa algo que puede recibir daño.

Ejemplos:

```text
Player
└── Hurtbox

Enemy
└── Hurtbox
```

No implementar sistemas de daño completamente diferentes para cada arma.

El objetivo es que todas las fuentes de daño utilicen el mismo protocolo.

---

# 12. Health y Damage

El sistema debe permitir separar:

```text
Health
Damage
Death
Knockback
Status Effects
```

Una entidad con vida debería poder recibir información de daño de forma genérica.

Estado actual: el knockback (`KnockbackComponent`, decae en 0.2 s), los i-frames del jugador (`HealthComponent.invulnerability_seconds`, 0.35 s), el hit flash (`HitFlash`), el hit-stop (`HitStop`, congela `Engine.time_scale` 60-110 ms por golpe aceptado, sin acumularse) y el combo de 3 de la espada (`WeaponData.combo` con un `SwingData` por golpe) ya existen. Cada golpe emite `swing_phase_changed`: `PlayerAnimator` reparte los frames de la animación de ataque en las fases del `SwingData` (preparación, golpe, recuperación) y la espada lanza el smear al activar la hitbox. `HitVfx` saca chispa, sangre y manchas de piso en cada golpe aceptado.

Peso del combate (D4): durante un golpe de espada el jugador queda plantado (solo avanza `SwingData.step_distance` en el golpe activo) y la orientación se fija al empezar. La voltereta (`RollComponent`) cuesta stamina, recorre una distancia fija, da invulnerabilidad con `HealthComponent.grant_invulnerability` y no se cancela; el ataque pedido durante ella sale al terminar. Un golpe aceptado aturde al enemigo (`EnemyData.stagger_seconds`) y corta su ataque, salvo que tenga `poise_while_attacking` y ya esté comprometido; empujado o aturdido no actúa. `CameraShake` (hijo de la `Camera2D`) solo mueve el `offset` en px enteros. Muerto, el jugador no se mueve, no rueda, no ataca y la salida no cambia de piso.

El sistema podrá crecer posteriormente para soportar:

- daño físico;
- daño mágico;
- críticos;
- resistencias;
- vulnerabilidades;
- knockback;
- efectos de estado;
- daño periódico.

No implementar todas estas características hasta que sean necesarias.

---

# 13. Armas

El juego tendrá inicialmente tres familias principales:

### Melee

```text
Espada
```

### Ranged físico

```text
Arco
```

### Ranged mágico

```text
Bastón
```

Estado actual: las tres familias existen bajo el nodo `Weapons` del jugador, pero
se equipa **una sola arma a la vez**, montada por `EquipmentController`. Se arranca
con la espada; el arco y el bastón se obtienen de cofres en zonas REWARD.

```text
attack       → ataca con el arma equipada
swap_weapon  → Tab: cambia el arma equipada
```

Todas las armas comparten el mismo slot de arma equipada. Atacar siempre cuesta
stamina; no hay cooldowns de arma. Con arco o bastón moverse no impide disparar,
pero abre un desvío de puntería (`WeaponData.aim_spread_*`) que se cierra quieto.

El arma debe definir principalmente cómo produce su ataque.

No debe contener lógica específica del jugador.

---

# 14. WeaponData

Siempre que sea apropiado, utilizar un `Resource` para almacenar datos de armas.

Ejemplo conceptual:

```text
WeaponData
├── type
├── scene
├── damage
├── knockback
├── stamina_cost
├── projectile_data
└── aim_spread_*       # desvío al moverse (arco y bastón)
```

`attack_speed` y `cooldown` están deprecados: el gating es la stamina, no un
cooldown de arma.

El ataque básico del bastón todavía no define si consume maná (D19); si lo hace,
`WeaponData` suma `mana_cost`.

Ejemplos de recursos:

```text
resources/weapons/
├── sword_basic.tres
├── sword_heavy.tres
├── bow_basic.tres
└── magic_staff.tres
```

La escena/script del arma utilizará estos datos para definir su comportamiento.

---

# 15. Espada

Flujo esperado:

```text
Player
 ↓
Attack
 ↓
Sword Hitbox
 ↓
Enemy Hurtbox
 ↓
Damage
```

Características posibles:

- daño alto;
- alcance corto;
- knockback;
- combos;
- ataques cargados;
- dash ofensivo.

Estas características se implementarán progresivamente.

---

# 16. Arco

Flujo esperado:

```text
Player
 ↓
Bow
 ↓
Arrow
 ↓
Projectile
 ↓
Enemy
```

Características posibles:

- daño moderado;
- largo alcance;
- velocidad de proyectil;
- penetración;
- múltiples flechas;
- flechas especiales.

El proyectil debe ser reutilizable para otros ataques que compartan comportamiento.

---

# 17. Bastón mágico

El bastón debe poder producir proyectiles mágicos:

```text
Staff
 ↓
Magic Projectile
 ↓
Enemy
```

Pero el sistema mágico debe poder evolucionar más allá del ataque básico.

Estado actual: el bastón se ataca con `attack` como cualquier arma equipada (no
tiene una acción de input propia) y el gating es stamina.

---

# 18. Ability System

Las habilidades **pertenecen al arma equipada**, no son un sistema suelto
(reframe Albion, D12). Cada arma tiene su propio kit intercambiable:

```text
Activas        → slots 1-4
Buffs/debuff   → slots Q/E/R
```

- Varias opciones por slot; **una sola activa por slot**.
- La maestría del arma desbloquea opciones nuevas.
- Cada habilidad declara su coste: **stamina** (físico), **maná** (mágico) o **ambos a la vez** (D19).
- El coste es atómico: si falta cualquiera de los recursos declarados, la habilidad no se ejecuta.
- Los ataques físicos de arma siguen costando solo stamina.
- Sin cooldown, salvo para el slot "ultimate".

Estado actual: cada `WeaponData.abilities` trae su slot 1 (`AbilityData` en `resources/abilities/`): tajo giratorio (espada, stamina), disparo triple (arco, stamina) y bola de fuego (bastón, maná). `AbilityCaster` (nodo `Abilities` del jugador) cobra el coste de forma atómica y crea el efecto: `burst` (golpe de área con empuje radial) o `volley` (proyectiles en abanico; `arrow.gd` puede explotar con `explosion_scene`). El maná es un segundo `StaminaComponent` (nodo `Mana`, 100 de pozo, 4/s) con su barra en el HUD. Faltan los slots 2-4 y Q/E/R, las opciones por slot y la maestría.

Para el vertical slice alcanza con 1-2 activas + 1 pasiva por arma, pero la
abstracción de slot se conserva para no reescribir después.

Categorías iniciales:

```text
Damage
Crowd Control
Buff
Debuff
```

Ejemplos:

### Crowd Control

- congelar;
- ralentizar;
- empujar;
- aturdir;
- atraer enemigos.

### Buffs

- aumentar velocidad;
- aumentar daño;
- aumentar crítico;
- regeneración;
- escudo;
- reducción de coste de stamina.

---

# 19. AbilityData

Utilizar `Resource` cuando sea apropiado.

Ejemplo:

```text
AbilityData
├── name
├── slot
├── stamina_cost
├── mana_cost
├── cast_time
├── damage
├── range
└── effect
```

El coste puede ser **stamina**, **maná** o **ambos** (D19); `mana_cost = 0`
significa que la habilidad no usa maná. Los cooldowns solo aplican al
slot "ultimate". `AbilityData` describe el kit del arma equipada, no habilidades
globales sueltas.

Ejemplos:

```text
resources/abilities/
├── fireball.tres
├── ice_nova.tres
├── speed_buff.tres
└── chain_lightning.tres
```

La implementación puede evolucionar hacia tipos como:

```text
Ability
├── ProjectileAbility
├── MeleeAbility
├── AreaAbility
├── BuffAbility
└── CrowdControlAbility
```

No crear toda esta jerarquía hasta que el proyecto realmente la necesite.

---

# 20. Dungeon

El sistema procedural debe separar tres niveles:

```text
GENERACIÓN LÓGICA (grid-merging)
        ↓
        ZONAS
        ↓
     TILEMAP
```

No generar directamente un conjunto de tiles aleatorios sin una estructura lógica previa.

El piso completo se renderiza en un **TileMap único** que consume el recurso pre-construido `res://tilesets/crypt_dark.tres` (cripta oscura, 32×32 px; atlas `assets/art/environment/crypt/crypt_tiles.png` armado por `tools/art/build_crypt_atlas.py`, `.tres` generado por `scripts/tools/build_crypt_tileset.gd`): el código solo coloca tiles — no construye tilesets ni colisiones en runtime. `scripts/dungeon/dungeon_geometry.gd` (`DungeonGeometry`) es la fuente única de las constantes de geometría y roles de tiles, y si el recurso falta la generación falla de forma ruidosa (sin fallback). Las habitaciones individuales `.tscn` fueron reemplazadas por un sistema de zonas generadas proceduralmente sobre una grilla.

Dirección (D3): **mundo exterior fijo + dungeons procedurales armadas con salas diseñadas a mano.** El grid-merging sigue definiendo la topología y los tipos de zona; el interior de cada zona sale de un pool de plantillas (`scenes/rooms/`) por tipo y tamaño, elegidas con la seed. El gating es por **llaves y puertas cerradas**, más un objeto que abre un atajo.

Eso impone dos requisitos al generador, ya cumplidos: `zone.tile_rect` es el rectángulo **exacto** de las celdas de la zona (cortes guillotina sin solapes) y cada zona tiene un **tamaño mínimo** (`FloorData.min_zone_cells`, 1×1 celda = una pantalla de sala: `DungeonGeometry.CELL_TILES` = 15×9 tiles = 480×288 px, que cubre el viewport de 480×270 px). `validate_layout()` los verifica en cada piso.

Algunas zonas pueden incluir **obstáculos movibles** (bloques, pilares caídos, escombros) que el jugador desplaza gastando **stamina**. No son habilidades: usan el mismo protocolo de gasto que los ataques. Su colocación viene de las plantillas de sala y no pueden romper la solvabilidad (D20).

---

# 21. DungeonGenerator

Responsabilidad:

- generar la estructura lógica de un piso;
- crear la grilla de celdas y mergearlas en zonas rectangulares;
- detectar adyacencia entre zonas;
- asignar tipos de zona (START, COMBAT, REWARD, EXIT; en el último piso BOSS y su antesala EVENT en lugar de EXIT);
- colocar puertas en posiciones irregulares sobre aristas compartidas;
- elegir la plantilla de sala de cada zona con la seed (`scenes/rooms/`);
- colocar llaves y puertas cerradas;
- validar la **solvabilidad** del piso (la llave debe estar antes que su puerta en la ruta), no solo la alcanzabilidad;
- renderizar el piso completo en un TileMap consumiendo el `TileSet` pre-construido (`res://tilesets/crypt_dark.tres`).

Reglas del render (BIBLIA_ARTE §1-3), todas en `DungeonGeometry`:

- Cada zona pinta su anillo dentro de su `tile_rect`: la fila norte es un **tope** visto desde arriba y debajo van las **2 filas de cara** de la pared norte, justo donde empieza el piso; las paredes laterales y la sur muestran solo su tope (la sur, sin cara exterior si otra zona queda abajo).
- Piso y topes son periódicos de 96 px: la variante sale de `(tx % 3, ty % 3)`.
- Las losas junto a una pared usan su variante con oclusión (AO) al pie de la pared.
- Puerta lateral = hueco en las dos paredes (`door_e` / `door_w`); puerta norte = pasillo entre los topes y arco en la cara de la zona de abajo. Cerrada: vuelve la pared (con colisión) y el arco muestra la puerta trabada.
- La salida es una escalera de bajada de 2×2 tiles que se entra **solo desde el sur**: su marco norte y los laterales tienen colisión (`DungeonGeometry.stairs_frame_rects`) y el `ExitArea` cubre la mitad sur (`stairs_exit_rect`). El generador la ubica con la seed (`FloorLayout.exit_stairs`) bajo la cara norte, con 1 tile libre a cada lado, 2 filas libres hasta la pared sur, fuera de las columnas de un arco norte (±1) y sin tocar la boca de ninguna puerta; si no entra, `validate_layout` rechaza el intento. Calcos y spawns no van sobre la escalera ni su entrada (`stairs_keep_clear`).
- Las paredes bloquean su tile completo: la cara norte frena los pies en el borde del piso.
- `floor_dressing.gd` agrega, sembrado por la seed, una antorcha encendida por zona en la cara norte (con `PointLight2D` que solo toca personajes; tiles y calcos tienen `light_mask = 0`), soportes apagados, objetos colgados y calcos de piso.

Flujo conceptual:

```text
generate_floor(floor_number, base_seed, data)
       │
       ▼
crear seed
       │
       ▼
dimensionar grilla
       │
       ▼
partir la grilla en zonas rectangulares (cortes guillotina, tamaño mínimo)
       │
       ▼
detectar vecinos
       │
       ▼
asignar tipos (START/EXIT/COMBAT/REWARD)
       │
       ▼
colocar puertas en aristas compartidas
       │
       ▼
elegir plantillas y colocar llaves/puertas cerradas
       │
       ▼
validar solvabilidad (llave antes que su puerta)
       │
       ▼
renderizar TileMap (floor/wall/door)
       │
       ▼
devolver FloorLayout
```

No debe encargarse de lógica específica de combate ni de spawn de enemigos.

---

# 22. Estructura lógica de una dungeon

Una dungeon puede representarse como un grafo de zonas en un espacio contiguo:

```text
       [Boss]
         │
         │
[Start]─[Combat]─[Combat]─[Reward]
         │
       [Event]
```

Tipos de zona:

```text
Start
Combat
Reward
Event
Boss
Exit
```

En el código existen START, COMBAT, REWARD, EXIT, **BOSS** y **EVENT**. En el último piso de un `DungeonData`
(`FloorData.boss_zone_cells`) el generador fija una arena BOSS de 2×2 celdas en la esquina sureste, sin EXIT,
con una sola puerta desde una antesala EVENT al oeste (D22). SHOP queda para más adelante.

Las zonas se generan mediante grid-merging: se divide el piso en una grilla de celdas, se mergean celdas contiguas en clusters rectangulares, y cada cluster recibe un tipo de zona. Todas las celdas pertenecen exactamente a una zona (sin espacios muertos ni solapes).

---

# 23. Zonas

Las zonas son la unidad funcional del piso. Cada zona tiene:

- un tipo (START, COMBAT, REWARD, EXIT, BOSS o EVENT)
- un rectángulo en la grilla (cell_min/cell_max)
- un rectángulo en tiles (tile_rect, para renderizado y cámara)
- una lista de zonas vecinas (por adyacencia de celdas)
- una lista de puertas que la conectan con sus vecinas
- un estado cleared (si el contenido fue resuelto)

El `tile_rect` es el rectángulo **exacto** de las celdas de la zona y cada zona tiene un **tamaño mínimo** (`min_zone_cells`) para que la cámara y la plantilla funcionen. El gating entre zonas se hace con **llaves y puertas cerradas**.

Las zonas se generan con cortes guillotina determinísticos por seed: START se recorta primero en el origen y el resto se corta sin perder capacidad hasta llegar a la cantidad de zonas. Si el mínimo no deja entrar esa cantidad, la grilla crece. Con `FloorData.min_size_zones_only` (por defecto) la grilla se elige con tantas celdas como zonas, así todas quedan de una pantalla; sin esa opción el tamaño de cada zona varía según dónde caen los cortes.

En el futuro, una zona COMBAT podría contener una sub-zona REWARD (reward pocket) asignando una celda interna con tipo diferente al de la zona padre.

---

# 24. DungeonManager

`DungeonManager` administra el piso actualmente cargado.

Responsabilidades:

- iniciar un piso;
- invocar al DungeonGenerator para obtener un FloorLayout;
- crear el TileMap, DoorController, Spawner y wirear señales;
- administrar la salida (ExitArea);
- detectar finalización del piso;
- iniciar transición al siguiente piso;
- respetar el techo de pisos por dungeon (`DungeonData`) y disparar el piso de jefe;
- arrancar en el guild y armar el piso 1 con `start_expedition()` (lo pide la puerta del guild);
- al morir, `_return_to_guild()`: vuelve al guild sin borrar el perfil; con piedra azul conserva la mochila y asegura las armas recogidas.

No debe almacenar permanentemente el estado completo de la partida.

Ese estado corresponde al `RunManager` (expedición) y a `ProfileState` (perfil).

---

# 25. FloorData

Los pisos pueden utilizar `FloorData` para definir parámetros de dificultad y generación.

Datos actuales:

```text
floor_number
grid_min_w / grid_max_w          # Grilla: cantidad de celdas en X
grid_min_h / grid_max_h          # Grilla: cantidad de celdas en Y
zone_count_min / zone_count_max  # Rango de zonas del piso
multi_door_threshold             # Tiles mínimos para múltiples puertas en una arista
max_doors_per_edge               # Máximo de puertas por arista compartida
max_generation_retries           # Intentos (seed derivada) antes de fallar con push_error, sin fallback
reward_ratio                     # Probabilidad de que una zona no-START/EXIT sea REWARD
zone_count_by_floor_depth        # Mapa piso → [min, max] de zonas
start_zone_max_cells             # Tamaño de la zona START en celdas (1×1 por defecto; gana min_zone_cells si es mayor)
min_zone_cells                   # Tamaño mínimo de zona en celdas (1×1 = una pantalla de 480×288 px, cubre el viewport)
enemy_health_multiplier
enemy_damage_multiplier
boss_zone_cells                  # Arena BOSS en celdas en el último piso; ZERO = piso sin jefe
```

`DungeonManager` pasa `enemy_health_multiplier` y `enemy_damage_multiplier` al `Spawner`, que se los da a cada enemigo antes de `add_child` (San Ulmo: 1,0/1,0, 1,1/1,1 y 1,2/1,15). `boss_zone_cells` (≠ 0) marca el piso de jefe.

La dificultad no debe aumentar únicamente mediante multiplicadores de estadísticas.

También debe aumentar mediante:

```text
Pisos iniciales
    ↓
enemigos básicos

Pisos intermedios
    ↓
nuevos enemigos

Pisos avanzados
    ↓
elites + variantes

Pisos de jefe
    ↓
boss
```

La progresión debe priorizar variedad y nuevas amenazas sobre inflar artificialmente la vida de los enemigos.

Estado actual: cada `FloorData` trae su `enemy_pool` (`EnemySpawnData`) y `threat_budget_per_cell`; el `Spawner` sortea grupos con la seed hasta gastar el presupuesto y puede dejar una zona al élite (`elite_scene`, `elite_chance`). Los comportamientos nuevos son datos de `EnemyData` sobre el mismo `enemy.gd`: `projectile_scene` + `keep_distance` (a distancia), `summon_*` (invocar), `knockback_scale` (D24). El escudo frontal es un nodo `Guard` (`guard_component.gd`) que la `Hurtbox` consulta antes de la vida; `DamageInfo.guard_break` lo rompe.

---

# 26. Bosses

Los bosses deben ser escenas independientes.

Estructura aproximada:

```text
Boss
├── Health
├── Hurtbox
├── Hitbox
├── Movement
├── AttackController
└── PhaseController
```

El boss puede tener fases:

```text
100% HP
   ↓
Phase 1
   ↓
70% HP
   ↓
Phase 2
   ↓
30% HP
   ↓
Phase 3
```

El `DungeonGenerator` no debe implementar la lógica interna del boss.

El piso de jefe lo decide `DungeonData` (cantidad de pisos y jefe) junto con el generador; las fases y los ataques viven en la escena del boss.

Estado actual: la Madre de la Fosa (`scenes/bosses/madre_fosa.tscn`, D21) es el jefe de San Ulmo. Es fija y elige ataques por distancia; cada ataque es un `BossAttackData` (`resources/bosses/`) con tiempos por fase, y la forma vive en el script. La fase 2 entra con la mitad de la vida. `Hurtbox.damage_multiplier` arma los puntos débiles. La barra del jefe (`BossBar`) y el sesgo de cámara (`CameraLimitManager.set_focus`) se piden por grupos (`boss_bar`, `camera_focus`). Al caer, el `Spawner` tira su `drop_table` y `DungeonManager` pinta la Escalera del Farol, que vuelve al guild con todo y marca el dungeon como limpio (`ProfileState.has_cleared`). Falta la *Nana* y los charcos de bilis.

---

# 27. Progresión y dificultad

Hay dos capas de progreso (D11): el **equipo del pueblo** es permanente y sobrevive a la muerte (`ProfileState`); las **mejoras de expedición** son temporales y mueren con la run (`RunManager`). No hay XP ni niveles: el poder viene del equipo y de las mejoras.

La progresión debe considerar varias dimensiones:

```text
Enemy HP
Enemy Damage
Enemy Count
Enemy Variety
Elite Chance
Room Complexity
Bosses
Rewards
Loot Quality
```

Evitar una progresión basada únicamente en:

```text
floor_number * enemy_hp
```

El objetivo es que avanzar de piso cambie también las decisiones y amenazas disponibles.

---

# 28. Builds

El diseño del juego debe permitir crear builds.

Ejemplo melee:

```text
Espada
+ crítico
+ coste de stamina reducido
+ knockback
+ dash
+ sangrado
```

Ejemplo arquero:

```text
Arco
+ velocidad de proyectil
+ multishot
+ penetración
+ crítico
+ daño a distancia
```

Ejemplo mágico:

```text
Bastón
+ poder mágico
+ coste de stamina reducido
+ congelación
+ AoE
+ regeneración de stamina
+ regeneración de maná
```

Ejemplo híbrido:

```text
Espada con su kit
+
Ice Nova
+
Speed Buff
+
Fireball
```

La arquitectura de armas, habilidades y upgrades debe permitir estas combinaciones sin obligar a que cada build tenga código completamente separado.

---

# 29. MVP / Vertical Slice

El primer objetivo jugable es:

```text
Pueblo mínimo (tienda)
  │
  ▼
1 dungeon de 3 pisos
  │
  ▼
Jefe
  │
  ▼
Volver al pueblo con loot
  │
  ▼
Comprar 1 mejora
  │
  ▼
Repetir
```

Debe contener únicamente:

- movimiento, colisiones y cámara;
- generación procedural básica con plantillas de sala simples;
- combate cuerpo a cuerpo (espada) con knockback e i-frames;
- un enemigo;
- un dungeon de 3 pisos con jefe;
- perfil persistente mínimo y oro;
- pueblo mínimo con tienda;
- muerte que vuelve al pueblo sin borrar el perfil.

No introducir inicialmente:

- múltiples clases;
- crafting ni inventario con peso, rarezas o equipo por slots del cuerpo (el inventario inicial es de slots con apilado);
- árboles de habilidades;
- muchos tipos de enemigos;
- bosses complejos (el primero con 1-2 fases);
- sistemas de loot avanzados;
- efectos de estado completos;
- granja ni crafting.

El MVP debe servir para validar el loop fundamental: expedición → recompensa → mejora → nueva expedición.

---

# 30. Roadmap de desarrollo

## Fase 1 — Movimiento

**Estado: ✅ hecho.**

Implementar:

- Player;
- `CharacterBody2D`;
- movimiento 8-direcciones;
- colisiones;
- cámara;
- animación básica.

Objetivo:

> Poder caminar por una habitación y comprobar que el movimiento es cómodo.

---

## Fase 2 — Dungeon estático

**Estado: ✅ hecho.**

Crear manualmente:

```text
Room
├── Floor
├── Walls
├── Door
└── Spawn
```

Objetivo:

> Validar movimiento y colisiones en un entorno de juego real.

---

## Fase 3 — Generación procedural (grid-merging + TileMap)

**Estado: ✅ hecho.**

Implementar:

```text
Seed
 ↓
Grid cells
 ↓
Cortes guillotina → Zonas rectangulares exactas (tamaño mínimo)
 ↓
Tipo de zona (START/COMBAT/REWARD/EXIT; BOSS/EVENT en el último piso)
 ↓
Puertas en aristas compartidas (posición irregular)
 ↓
TileMap único (consume res://tilesets/crypt_dark.tres)
```

La generación produce un piso contiguo sin espacios muertos. Las zonas se asignan a tipos funcionales. Las puertas se colocan en posiciones irregulares — si la arista compartida es suficientemente larga pueden haber múltiples puertas.

Cada celda del grid mide `DungeonGeometry.CELL_TILES` = 15×9 tiles: una pantalla de sala con su anillo de pared, estilo Zelda. Al cruzar una puerta la cámara se desliza a la zona nueva (`CameraLimitManager.slide_seconds`, 0.4 s) con el juego en pausa y el jugador entra caminando solo hasta el piso, frente a la puerta; las puertas de combate se traban recién ahí. Dentro de una zona de varias pantallas sigue al jugador, limitada a la zona y en píxeles enteros. El TileMap consume el `TileSet` pre-construido `res://tilesets/crypt_dark.tres` (cripta oscura, 32×32 px) — el código solo coloca tiles; `DungeonGeometry` es la fuente única de las constantes de geometría y roles de tiles.

**Advertencia:** `tilesets/crypt_dark.tres` se genera con `scripts/tools/build_crypt_tileset.gd` (colisiones desde `DungeonGeometry.is_solid_atlas`): no editarlo a mano, se pisa al regenerar.

Objetivo:

> Cada ejecución produce un piso procedural único con zonas de distintos tamaños conectadas por puertas en posiciones variables.

---

## Fase 4 — Primer enemigo

**Estado: ✅ hecho.**

Crear un enemigo básico, por ejemplo un slime.

Comportamiento:

```text
detectar Player
      ↓
seguir Player
      ↓
atacar
```

No introducir IA compleja todavía.

---

## Fase 5 — Sistema de daño

**Estado: ✅ hecho.**

Implementar:

```text
Health
Hitbox
Hurtbox
Damage
Death
```

Probar:

```text
Player → Enemy
Enemy → Player
```

---

## Fase 6 — Espada

**Estado: ✅ hecho** (el feel base: knockback, i-frames y hit flash llegaron en el PR #6).

Implementar:

```text
Player
 ↓
Attack
 ↓
Sword Hitbox
 ↓
Enemy Hurtbox
 ↓
Damage
```

Añadir progresivamente:

- animación;
- ventana de hitbox;
- knockback.

---

## Fase 7 — Ranged

**Estado: ✅ hecho.**

Implementar:

```text
Bow
 ↓
Arrow
 ↓
Projectile
 ↓
Enemy
```

Posteriormente reutilizar la arquitectura para:

```text
Staff
 ↓
Magic Projectile
```

Estado actual: el bastón (tercera familia, ranged mágico) reutiliza el script
del arco (`staff.gd` hereda de `bow.gd`), dispara el proyectil mágico reutilizando
`arrow.gd` (`magic_bolt.tscn`) y se ataca con `attack` (misma acción que el resto
de las armas). Sin cooldowns: el gating es de stamina únicamente.

---

## Fase 8 — Habilidades

**Estado:** parte A ✅ hecha y archivada; parte B ✅ primer corte (maná + slot 1 por arma).

- **Parte A — `weapon-equip`:** una sola arma equipada a la vez (`EquipmentController`), cambio con Tab.
- **Parte B — `abilities`:** kits de habilidad por arma (D12).
  - Recurso de maná (`ManaComponent`) + barra en el HUD + coste dual `stamina_cost` / `mana_cost` en `AbilityData` (D19).

Implementar algunas habilidades representativas del kit del arma:

```text
Activa 1 → Ice Nova
Activa 2 → Fireball
Buff Q   → Speed Buff
```

El objetivo es validar:

- daño;
- AoE;
- control de masas;
- buffs;
- coste de recursos (stamina y/o maná) y slots.

---

## Fase 9 — Progresión

**Estado: ⏳ pendiente.**

Añadir progresivamente:

```text
Loot
Weapons
Stats
Rarities
Upgrades
Elite rooms
```

Sin XP ni niveles: el poder viene del equipo del pueblo y de las mejoras de expedición (D11).

---

## Fase 10 — Pueblo y economía

**Estado:** perfil, oro, inventario, guild, tienda y NPCs ✅ hechos; `WorldClock` ⏳ pendiente.

- ✅ `ProfileState` persistente en `user://profile.json` (oro bancado, almacén, armas aseguradas, desbloqueos).
- ✅ Oro, loot e inventario (mochila y almacén), con panel `inventory` (I).
- ✅ Guild mínimo en `scenes/guild/`: se arranca ahí y se vuelve ahí al morir (`_return_to_guild()`).
- ✅ Tienda de la reducidora en el guild (`scripts/ui/shop_panel.gd`): compra lo de la mochila a su `ItemData.value` y vende piedras azules y las mejoras permanentes (`ShopData.upgrades`, `UpgradeData` en `resources/upgrades/`: vida y aguante máximos, D11), todo en oro bancado. Las mejoras viven en `ProfileState.owned_upgrades` y `DungeonManager._apply_player_stats` las suma a los máximos del jugador.
- ✅ 7 NPCs quietos con idle del kit y un saludo fijo (`npc.<id>.greet.N` con `tr()`); diálogo provisorio.
- `WorldClock` con fases día/noche.

---

## Fase 11 — Expedición con jefe

**Estado:** ✅ hecha salvo la *Nana* y los charcos de bilis de la Madre.

- ✅ `DungeonData` (id, cantidad de pisos, jefe) y techo de pisos: San Ulmo tiene 3 (`resources/dungeons/san_ulmo.tres`).
- ✅ Zonas BOSS y EVENT (antesala).
- ✅ Primer boss con 2 fases: la Madre de la Fosa (D21).
- ✅ Piedra azul (consumible) que conserva el loot al morir (D1).

---

## Fase 12 — Plantillas, llaves y solvabilidad

**Estado: ⏳ pendiente.**

- ✅ Arreglar `_merge_cells` (rectángulos exactos) y tamaño mínimo de zona.
- Pool de plantillas de sala en `scenes/rooms/`.
- Llaves y puertas cerradas.
- Validación de solvabilidad en el generador.

---

## Fase 13 — Historia

**Estado: ⏳ pendiente.**

- Sistema de diálogo data-driven (`DialogueData`).
- Escena de cierre al terminar cada dungeon.
- Localización ES/EN con `tr()`: la base ya existe (`locale/strings.csv`, textos de UI e ítems); faltan los de historia y diálogo.

---

# 31. Orden recomendado de implementación

Cuando haya dudas sobre qué desarrollar a continuación, priorizar:

```text
1. ✅ Arreglar `_merge_cells` (rectángulos exactos + tamaño mínimo de zona)
2. ✅ Hit-stop + combo de 3 (falta el arte del swing)
3. ✅ `ProfileState` + oro + inventario + piedra azul + `_return_to_guild()`
4. ✅ Guild con tienda (scenes/guild/)
5. Pool de plantillas de sala
6. `WorldClock` día/noche (✅ techo de pisos por dungeon + zona BOSS)
```

El paso 1 es prerrequisito del 5. Los pasos 2 y 3 son independientes entre sí y pueden ir en paralelo.

Fuera de este orden inmediato, el maná (D19) entra junto con los kits de habilidad (Fase 8 parte B) y los obstáculos movibles (D20) entran con el pool de plantillas de sala.

No saltar prematuramente a sistemas posteriores si los sistemas fundamentales todavía no son estables.

---

# 32. Convenciones de código

## Naming

Utilizar `snake_case` para archivos y variables GDScript:

```text
player.gd
dungeon_generator.gd
health_component.gd
current_floor
enemy_damage
```

Clases y escenas pueden utilizar PascalCase:

```text
Player
DungeonManager
HealthComponent
WeaponData
```

## Tipado explícito (OBLIGATORIO)

Toda variable local debe declararse con tipo explícito, **especialmente** cuando:

- se accede a valores dentro de arrays anidados (`cells[gy][gx].zone_id`);
- se accede a propiedades de objetos sin tipo (`zone.tile_rect.position`);
- se mezclan `Vector2` y `Vector2i`;
- se usan señales con parámetros (`body: Node2D` no tiene `velocity` — castear a `CharacterBody2D`).

Preferir:

```gdscript
var cid: int = cells[gy][gx].zone_id
var zone_center: Vector2 = Vector2(...)
var player: CharacterBody2D = body  # cast after is-check
```

Evitar inferencia de tipo (`:=`) cuando el tipo no sea obvio para el parser de GDScript.

El parser de Godot 4.7 no puede inferir tipos a través de:

- arrays anidados (`cells[y][x]`);
- diccionarios (`dict[key]`);
- referencias a objetos sin tipo explícito.

## Comentarios bilingües

El código nuevo usa **comentarios bilingües (español / inglés)**. Mantener esa convención al tocar o agregar código, para que el archivo sea legible en ambos idiomas.

## Señales

Utilizar nombres descriptivos:

```text
health_changed
died
damage_received
room_completed
floor_completed
attack_started
attack_finished
ability_cast
```

## Evitar

No utilizar nombres ambiguos:

```text
data
thing
obj
manager2
temp
stuff
```

salvo que su alcance sea realmente trivial.

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

# 37. Procedural generation

La generación debe ser reproducible mediante una `seed`.

El `RunManager` debe poder conservar:

```text
run_seed
```

Esto permitirá:

- reproducir una partida;
- depurar mapas problemáticos;
- probar bugs;
- comparar runs;
- eventualmente compartir seeds.

La generación debe producir dungeons válidas.

Una dungeon inválida debe detectarse y regenerarse o corregirse antes de presentarse al jugador.

---

# 38. Diseño de escenas

Preferir escenas pequeñas y reutilizables.

Ejemplos:

```text
player.tscn
enemy_base.tscn
slime.tscn
sword.tscn
arrow.tscn
room.tscn
exit.tscn
```

Una escena puede componerse de otras escenas cuando tenga sentido.

No duplicar estructuras enteras si pueden reutilizarse como componentes.

## 38.1. Dirección visual y estándar de pixel art

Base de esta sección: D4, D5 y D7 en [`DECISIONES.md`](DECISIONES.md). Si algo de acá las contradice, gana `DECISIONES.md`.

### Dirección visual

- **Atmósfera *Fear & Hunger***: lo más oscuro posible, gore y horror corporal permitidos (D15).
- **Cámara cenital con personajes de lado** (*Minish Cap*, *A Link to the Past*, *Moonlighter*): el suelo se ve desde arriba, las paredes muestran su cara frontal y los personajes se ven de frente, de espaldas o de perfil. No es una vista cenital pura ni un side-scroller.
- **Paleta apagada (importante)**: colores desaturados y terrosos, sombras frías, pocos tonos por material. El saturado se reserva para lo que hay que leer de un vistazo: hit flash, VFX, telegrafía de ataque, peligros, botín e interactuables (D5). Todo asset nuevo se revisa contra esta paleta.
- **Lectura de beat 'em up**: los ataques se leen de perfil, con anticipación e impacto claros. Las entidades deberían ordenarse por profundidad (Y) para que los grupos de enemigos se lean bien. Pendiente: hoy el orden es solo por `z_index`.
- La paleta exacta, la perspectiva y las reglas de iluminación están en [`BIBLIA_ARTE.md`](BIBLIA_ARTE.md) (D7). El estilo elegido es la cripta oscura para el entorno y "esbelto" para los personajes. HD-2D se decide después (D5).

### Tamaños

Decisión (D5): **la grilla del mundo es de 32×32 píxeles**, el mismo tamaño que los tiles de piso y pared (`DungeonGeometry.TILE_SIZE`). Los personajes se dibujan en un lienzo de 48×48 para que entren cara, manos y equipo legibles.

| Tipo | Tamaño del sprite | Ocupa |
|---|---|---|
| Tiles de piso y pared | 32×32 | 1 tile |
| Jugador, NPCs, enemigos comunes (slime, goblin) | 48×48 (figura de ~44 px; pies en x 24, suelas en y 45) | ~1 tile de base |
| Objetos (cofre, salida, items) | sobre la grilla de 32 | 1 tile |
| Enemigos grandes (troll, gigante, ogro) | 96×96 | 2×2 tiles de base |
| Jefes (dragón, etc.) | 128×128 o más | 3×3 a 4×4 tiles |

Los tamaños grandes no tienen que ser cuadrados (un dragón puede ser 128×80).

### Reglas

- **Misma densidad de píxel en todo el juego.** Una criatura grande se dibuja directamente más grande; nunca se escala un sprite a ×2.
- **Nunca escalar a factores no enteros** (×1.5, etc.): deforma los píxeles.
- **Silueta primero.** A 48×48 entran cara (ojos de 1–2 px, expresión simple), manos, ropa y equipo; no entran texto, joyas chicas ni dedos individuales. Cada enemigo tiene que reconocerse por su forma y colores.
- **Contorno de color, nunca negro**, en personajes y objetos, con 3–4 tonos por material más 1 de contorno (detalle en `BIBLIA_ARTE.md`).
- **Formato:** PNG con transparencia, sin suavizado. Varias poses o frames del mismo personaje van juntos en una hoja (spritesheet) con celdas del mismo tamaño.

### Animaciones (por personaje de 48×48)

| Animación | Frames |
|---|---|
| Idle | 2–4 |
| Caminar | 4–6 |
| Ataque | 3–5 |

Cada animación se dibuja en **4 direcciones** (abajo, arriba, izquierda y derecha), sin espejar con `flip_h`: los personajes de lado con cámara cenital lo exigen (D4). Las criaturas grandes pueden usar menos frames o armarse por partes (cabeza, cuerpo, alas) animadas en Godot, que es más barato que dibujar cada frame.

### Criaturas grandes en el juego

- Cada criatura es una escena que hereda de `enemy_base.tscn` (los jefes van como escenas aparte, §26) con su propio `EnemyData` y su propio arte.
- **Las colisiones no siguen al dibujo**: `Hurtbox` y `Hitbox` se dimensionan aparte. Un dragón puede tener la zona vulnerable en el cuerpo y cajas de ataque en la cabeza o la cola.
- **Las puertas miden 1 tile (32 px)**: un enemigo de 64 px no pasa entre zonas. Los enemigos grandes aparecen y pelean en su propia zona.
- Una celda mide 15×9 tiles (480×288 px, una pantalla): un jefe de 128 px entra, pero los jefes necesitan una zona BOSS de varias celdas.

### Pantalla

El juego dibuja a 480×270 (unos 15×8 tiles de 32) y se escala a la ventana con **escala entera** (`stretch/mode = viewport`, `scale_mode = integer`, ventana de 1920×1080 = ×4). Si la pantalla no da para ×4, usa el mayor entero que entra, con bordes.

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

Otros recursos: `DungeonData` (id, pisos, jefe, trofeo; ya existe) y, planificado, `DialogueData` (diálogo data-driven del pueblo y la historia).

---

# 40. Debugging y desarrollo incremental

Cada iteración debe intentar dejar el proyecto en un estado ejecutable.

Preferir:

```text
Movimiento funcional
        ↓
Dungeon funcional
        ↓
Enemigo funcional
        ↓
Combate funcional
```

en lugar de desarrollar simultáneamente cinco sistemas incompletos.

Cuando se agregue una mecánica, crear primero la versión mínima funcional y después mejorarla.

---

# 41. Criterio de aceptación de cada iteración

Una iteración se considera terminada cuando:

- el juego continúa ejecutándose;
- el nuevo sistema funciona de extremo a extremo;
- no rompe sistemas existentes;
- las responsabilidades siguen separadas;
- el código puede ser extendido razonablemente;
- la implementación no introduce duplicación evidente;
- el comportamiento puede probarse manualmente.

---

# 42. Filosofía de desarrollo

El proyecto debe evolucionar de:

```text
Movimiento
   ↓
Exploración
   ↓
Combate
   ↓
Recompensa
   ↓
Progresión
   ↓
Build
   ↓
Dificultad
   ↓
Replayability
```

La prioridad no es implementar muchas características rápidamente.

La prioridad es construir un **núcleo jugable sólido** sobre el que se puedan agregar sistemas sin reescribir la arquitectura.

---

# 43. Estado inicial del proyecto

Al comenzar el desarrollo, el objetivo inmediato es:

```text
[x] Crear proyecto Godot
[x] Crear estructura de directorios
[x] Configurar Input Map
[x] Crear Main
[x] Crear Player
[x] Implementar movimiento
[x] Implementar colisiones
[x] Crear primera habitación
[x] Añadir cámara
[x] Validar movimiento
```

Después:

```text
[x] Crear DungeonManager
[x] Crear DungeonGenerator
[x] Generar primer mapa procedural (grid-merging + TileMap + dungeons_v2.tres)
[x] Implementar transición de pisos
```

Después:

```text
[x] Crear Enemy base
[x] Crear HealthComponent
[x] Crear Hitbox
[x] Crear Hurtbox
[x] Crear primer enemigo
[x] Crear espada
[x] Implementar combate
```

Después:

```text
[x] Arco
[x] Proyectiles
[x] Bastón
[x] Una sola arma equipada + cambio con Tab (weapon-equip, Fase 8 parte A)
[x] P0 de combate: knockback, i-frames, hit flash y pausa
[x] Tope de la zona START
[x] Habilidades (kits por arma, Fase 8 parte B: slot 1)
[ ] Buffs
[ ] Crowd Control
[x] Loot (mochila, almacén del guild, tablas de botín)
[ ] Progresión (equipo + mejoras, sin XP)
[x] Enemigos adicionales (bestiario de la cripta: errante, rata, reptante, escupebilis, guardia, cultista)
[x] Elites (el Cosido)
[x] Bosses (la Madre de la Fosa, D21)
```

Pendiente para el vertical slice v2:

```text
[x] ProfileState + oro + retorno al guild + piedra azul
[x] Hit-stop + combo de 3
[x] Tienda en el guild
[ ] WorldClock
[x] DungeonData + techo de pisos + zona BOSS
[ ] Plantillas de sala + llaves + solvabilidad
[x] Maná (recurso + barra HUD)
[ ] Obstáculos movibles con coste de stamina
[ ] Historia + localización ES/EN
```

---

# 44. Instrucción para agentes de IA

Cualquier agente que trabaje sobre este repositorio debe:

1. Leer este `AGENTS.md` antes de modificar arquitectura o crear sistemas nuevos.
2. Respetar las responsabilidades descritas en este documento.
3. No mover lógica a sistemas globales sin justificación.
4. No crear nuevos managers si una responsabilidad puede vivir correctamente en un sistema existente.
5. Evitar convertir `Player`, `Main` o `DungeonGenerator` en clases monolíticas.
6. Reutilizar `Hitbox`, `Hurtbox`, `Health` y otros componentes comunes.
7. Preferir `Resource` para datos configurables.
8. Mantener la generación procedural separada del renderizado y del gameplay.
9. Mantener el juego ejecutable después de cada iteración.
10. Antes de realizar una refactorización estructural importante, explicar qué problema resuelve y qué sistemas afecta.
11. No introducir dependencias o frameworks externos sin una necesidad clara.
12. No implementar sistemas futuros de forma especulativa solamente porque aparecen en el roadmap.
13. Si una nueva característica contradice esta arquitectura, señalarlo antes de implementarla.
14. Mantener este documento actualizado si una decisión arquitectónica importante cambia de forma permanente.
15. **Toda variable debe declararse con tipo explícito** — no usar `:=` para inferencia cuando el tipo provenga de arrays anidados, diccionarios, o propiedades de objetos sin tipo. Ver sección 32 (Tipado explícito).
16. **Las señales que emiten eventos sincrónicos** (ej: `spawn_content()` que emite `zone_cleared`) deben conectarse ANTES de la llamada que dispara la emisión.
17. **Leer [`DECISIONES.md`](DECISIONES.md) antes de proponer arquitectura.** Es la fuente de verdad de diseño aprobada por el equipo.
18. **`tilesets/crypt_dark.tres` se genera con `scripts/tools/build_crypt_tileset.gd`** Sus colisiones salen de `DungeonGeometry.is_solid_atlas`; no editarlo a mano porque se pisa al regenerar.
19. **Si un documento contradice `DECISIONES.md`, gana `DECISIONES.md`** y hay que corregir el documento, no la decisión.

## 44.1. Organización y comentarios

- **Un archivo, una responsabilidad.** Cada script va en la carpeta de su sistema (§4). No se dejan scripts, escenas ni assets sueltos o sin uso: lo que no se usa se borra en el mismo cambio que lo deja huérfano.
- **Comentarios cortos y bilingües**: español primero, inglés después, en una línea cuando entra.
  ```gdscript
  # Tope de tamaño de la zona START (en celdas) / START zone size cap (in cells)
  @export var start_zone_max_cells: Vector2i = Vector2i(2, 1)
  ```
- **Obligatorio comentar** los valores configurables (`@export`, constantes, campos de `Resource`): qué controlan y en qué unidad (px, segundos, tiles, celdas). También las variables con nombre vago y cualquier número mágico.
- **No se comenta lo obvio.** El comentario explica el porqué o la unidad, no repite el código.
- Los nombres dicen qué son (`hit_stop_seconds`, no `t` ni `value`). Ver §32.

## 44.2. Código sin marcas de IA

El código tiene que parecer escrito por el equipo. Prohibido:

- Atribuciones o firmas: "Generated by…", "Co-Authored-By: <IA>", "As an AI…", ni en código, ni en commits, ni en PRs.
- Comentarios que narran pasos ("# Step 1: …", "# Now we…", "# This function…"), que resumen el cambio ("# Updated to…", "# Fixed:", "# NEW") o que le hablan al lector ("# Note that…", "# As requested…").
- Docstrings largos que repiten la firma de la función, y encabezados decorativos (líneas de `=====`, banners) que no usa el resto del código.
- Emojis en código y comentarios.
- Abstracciones, opciones, parámetros o manejo de errores "por si acaso" que nadie pidió. Tampoco `TODO` sin dueño ni fecha.
- Código defensivo redundante (chequear `null` lo que el motor ya garantiza) y `print` de depuración olvidados.

Copiar el estilo del archivo que se toca: nombres, densidad de comentarios y forma de los tests.

## 44.3. Flujo de trabajo de agentes

- **No commitear, pushear, abrir PRs ni comentar en GitHub sin el visto bueno explícito** de una persona del equipo para ese cambio puntual.
- Commits y PRs en español, uno por punto lógico, con el mismo estilo que el historial.
- Antes de dar algo por terminado: correr todos los tests headless (`scripts/test/`) y reportar el resultado real, con la salida de los que fallen.
- Las capturas de prueba no se commitean: van en los comentarios del PR.
- El arte nuevo sale con las herramientas de arte (kit de personajes y linter de pixel art, puntaje ≥ 90) y sigue `BIBLIA_ARTE.md`. Ningún archivo del repo apunta a rutas fuera del repo.
- `tilesets/crypt_dark.tres` se genera con `scripts/tools/build_crypt_tileset.gd` (colisiones desde `DungeonGeometry.is_solid_atlas`): no editarlo a mano, se pisa al regenerar.

---

# 45. Regla final

Cuando exista una duda entre:

```text
"¿Cómo implemento esta característica rápidamente?"
```

y:

```text
"¿Cómo implemento esta característica sin romper la arquitectura?"
```

priorizar la segunda.

La velocidad de desarrollo importa, pero la arquitectura debe mantenerse suficientemente limpia para que el juego pueda crecer desde el MVP hasta un dungeon crawler con historia completo sin requerir una reescritura general.
