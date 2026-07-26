# AGENTS.md — Dungeon 2D Procedural Roguelite

## 1. Propósito del proyecto

Este documento define la arquitectura, convenciones y dirección técnica del videojuego 2D desarrollado con Godot.

Su objetivo principal es mantener la coherencia entre iteraciones de desarrollo y evitar que nuevas mecánicas introduzcan acoplamiento innecesario o contradigan decisiones arquitectónicas existentes.

El juego es un dungeon crawler / roguelite 2D centrado en:

- avanzar a través de pisos generados proceduralmente;
- explorar habitaciones conectadas;
- combatir enemigos;
- conseguir mejoras, armas y habilidades;
- aumentar progresivamente la dificultad;
- superar jefes de piso cada cierta cantidad de pisos;
- construir diferentes builds mediante armas, estadísticas, habilidades, buffs y efectos de control.

La prioridad durante el desarrollo es construir primero un **vertical slice jugable** y ampliar el sistema progresivamente.

---

## 2. Principios generales

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
- `RunManager`: conserva el estado de la partida.
- `HealthComponent`: administra vida.
- `Hitbox`: representa una fuente de daño.
- `Hurtbox`: representa una entidad que puede recibir daño.

---

# 3. Arquitectura conceptual

La arquitectura principal debe mantenerse aproximadamente así:

```text
                         Main
                          │
             ┌────────────┼────────────┐
             │            │            │
             ▼            ▼            ▼
          World          UI       RunManager
             │
             ▼
       DungeonManager
             │
             ▼
      DungeonGenerator
             │
             ▼
           Floor
             │
      ┌──────┼──────┐
      ▼      ▼      ▼
    Room   Room    Room
      │
      ├── Enemies
      ├── Loot
      ├── Doors
      └── Triggers


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
Inicio
  │
  ▼
Crear / cargar Run
  │
  ▼
Generar piso
  │
  ▼
Explorar habitaciones
  │
  ▼
Combatir / conseguir recompensas
  │
  ▼
Encontrar salida
  │
  ├── Piso normal ──────► siguiente piso
  │
  └── Piso de jefe ─────► derrotar jefe
                              │
                              ▼
                         siguiente piso
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
│   ├── dungeon/
│   │   ├── dungeon.tscn
│   │   ├── room.tscn
│   │   └── exit.tscn
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
│   └── ui/
│
├── scripts/
│   │
│   ├── player/
│   │   ├── player.gd
│   │   ├── player_stats.gd
│   │   └── player_controller.gd
│   │
│   ├── dungeon/
│   │   ├── dungeon_generator.gd
│   │   ├── room_generator.gd
│   │   └── dungeon_manager.gd
│   │
│   ├── combat/
│   │   ├── health_component.gd
│   │   ├── hurtbox.gd
│   │   ├── hitbox.gd
│   │   └── damage_info.gd
│   │
│   ├── enemies/
│   │   └── enemy.gd
│   │
│   └── game/
│       ├── game_manager.gd
│       └── run_manager.gd
│
├── resources/
│   │
│   ├── weapons/
│   ├── abilities/
│   ├── enemies/
│   ├── rooms/
│   └── floors/
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
├── audio/
│   ├── music/
│   └── sfx/
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
├── World
│   ├── Dungeon
│   └── Player
│
└── UI
    ├── HUD
    ├── HealthBar
    └── FloorLabel
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

`RunManager` representa el estado de una partida concreta.

Puede contener datos como:

```text
current_floor
player_level
gold
current_weapon
abilities
upgrades
enemies_defeated
run_seed
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

Acciones iniciales previstas:

```text
move_up
move_down
move_left
move_right

attack
secondary_attack

ability_1
ability_2
ability_3

dash
interact

pause
```

Las acciones podrán ampliarse conforme aparezcan nuevas mecánicas.

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

El arma debe definir principalmente cómo produce su ataque.

No debe contener lógica específica del jugador.

---

# 14. WeaponData

Siempre que sea apropiado, utilizar un `Resource` para almacenar datos de armas.

Ejemplo conceptual:

```text
WeaponData
├── name
├── damage
├── attack_speed
├── range
├── knockback
├── crit_chance
├── cooldown
└── type
```

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

---

# 18. Ability System

Las habilidades deben ser independientes de las armas.

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
- reducción de cooldown.

---

# 19. AbilityData

Utilizar `Resource` cuando sea apropiado.

Ejemplo:

```text
AbilityData
├── name
├── cooldown
├── mana_cost
├── cast_time
├── damage
├── range
├── effect
└── projectile
```

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
GENERACIÓN LÓGICA
        ↓
HABITACIONES
        ↓
TILEMAP
```

No generar directamente un conjunto de tiles aleatorios sin una estructura lógica previa.

---

# 21. DungeonGenerator

Responsabilidad:

- generar la estructura lógica de un piso;
- crear el grafo de habitaciones;
- conectar habitaciones;
- asignar tipos de habitación;
- producir la información necesaria para construir el piso.

Flujo conceptual:

```text
generate_floor(floor_number)
       │
       ▼
crear seed
       │
       ▼
crear grafo
       │
       ▼
crear habitaciones
       │
       ▼
conectar habitaciones
       │
       ▼
asignar tipos
       │
       ▼
crear/spawnear habitaciones
```

No debe encargarse de lógica específica de combate.

---

# 22. Estructura lógica de una dungeon

Una dungeon puede representarse como un grafo:

```text
       [Boss]
         │
         │
[Start]─[Combat]─[Combat]─[Reward]
         │
       [Event]
```

Tipos iniciales:

```text
Start
Combat
Reward
Event
Boss
Exit
```

El generador debe producir primero esta estructura abstracta.

Después se seleccionan las escenas de habitaciones apropiadas.

---

# 23. Habitaciones

Las habitaciones deben ser reutilizables.

Ejemplo:

```text
rooms/
│
├── combat/
│   ├── combat_01.tscn
│   ├── combat_02.tscn
│   ├── combat_03.tscn
│   └── combat_04.tscn
│
├── treasure/
│   ├── treasure_01.tscn
│   └── treasure_02.tscn
│
├── event/
│   └── event_01.tscn
│
└── boss/
    └── boss_room_01.tscn
```

El generador decide qué tipo de habitación necesita y selecciona una variante válida.

Esto permite:

- diseño manual;
- variedad procedural;
- control artístico;
- control de dificultad.

No crear todas las habitaciones mediante generación matemática si una combinación de prefabs diseñados manualmente ofrece mejor resultado.

---

# 24. DungeonManager

`DungeonManager` administra el piso actualmente cargado.

Responsabilidades:

- iniciar un piso;
- cargar/generar habitaciones;
- administrar la salida;
- detectar finalización del piso;
- iniciar transición al siguiente piso;
- solicitar generación de un nuevo piso.

No debe almacenar permanentemente el estado completo de la partida.

Ese estado corresponde al `RunManager`.

---

# 25. FloorData

Los pisos pueden utilizar `FloorData` para definir parámetros de dificultad.

Datos posibles:

```text
floor_number
enemy_health_multiplier
enemy_damage_multiplier
enemy_count_multiplier
room_count
elite_chance
treasure_quality
boss
```

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

Debe únicamente determinar cuándo corresponde un piso de jefe y qué boss debe aparecer.

---

# 27. Progresión y dificultad

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
+ velocidad de ataque
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
+ reducción de cooldown
+ congelación
+ AoE
+ regeneración de mana
```

Ejemplo híbrido:

```text
Espada
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
START
  │
  ▼
Habitación de combate
  │
  ▼
Habitación de combate
  │
  ▼
Habitación de recompensa
  │
  ▼
SALIDA
  │
  ▼
PISO 2
```

Debe contener únicamente:

- movimiento;
- colisiones;
- cámara;
- generación procedural básica;
- una habitación de combate;
- un enemigo;
- espada;
- vida;
- daño;
- muerte;
- transición de piso.

No introducir inicialmente:

- múltiples clases;
- inventario complejo;
- árboles de habilidades;
- muchos tipos de enemigos;
- bosses complejos;
- sistemas de loot avanzados;
- efectos de estado completos.

El MVP debe servir para validar el loop fundamental.

---

# 30. Roadmap de desarrollo

## Fase 1 — Movimiento

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

## Fase 3 — Generación procedural inicial

Implementar:

```text
Seed
 ↓
Room graph
 ↓
Rooms
 ↓
Doors
 ↓
Dungeon
```

Inicialmente puede ser lineal:

```text
Start → Combat → Combat → Treasure → Exit
```

Después introducir ramificaciones.

Objetivo:

> Cada ejecución debe poder producir una dungeon diferente y válida.

---

## Fase 4 — Primer enemigo

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
- cooldown;
- hitbox;
- knockback.

---

## Fase 7 — Ranged

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

---

## Fase 8 — Habilidades

Implementar algunas habilidades representativas:

```text
Q → Ice Nova
W → Fireball
E → Speed Buff
```

El objetivo es validar:

- daño;
- AoE;
- control de masas;
- buffs;
- cooldowns.

---

## Fase 9 — Progresión

Añadir progresivamente:

```text
XP
Levels
Loot
Weapons
Stats
Abilities
Rarities
Upgrades
Gold
Shops
Elite rooms
Events
Bosses
```

---

# 31. Orden recomendado de implementación

Cuando haya dudas sobre qué desarrollar a continuación, priorizar:

```text
1. Movimiento
2. Colisiones
3. Habitación estática
4. Cámara
5. Dungeon procedural
6. Transición de pisos
7. Enemy base
8. Health
9. Hitbox / Hurtbox
10. Espada
11. Combate básico
12. Arco
13. Proyectiles
14. Bastón
15. Habilidades
16. Buffs / CC
17. Loot
18. Progresión
19. Enemigos adicionales
20. Elites
21. Bosses
22. Builds avanzadas
23. Balance
24. UI / polish
```

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
    attack_speed = 1.2
    knockback = 30
```

mientras:

```text
Sword.gd
```

determina cómo ejecutar el ataque.

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
[ ] Crear proyecto Godot
[ ] Crear estructura de directorios
[ ] Configurar Input Map
[ ] Crear Main
[ ] Crear Player
[ ] Implementar movimiento
[ ] Implementar colisiones
[ ] Crear primera habitación
[ ] Añadir cámara
[ ] Validar movimiento
```

Después:

```text
[ ] Crear DungeonManager
[ ] Crear DungeonGenerator
[ ] Crear Room
[ ] Generar primer mapa procedural
[ ] Implementar transición de pisos
```

Después:

```text
[ ] Crear Enemy base
[ ] Crear HealthComponent
[ ] Crear Hitbox
[ ] Crear Hurtbox
[ ] Crear primer enemigo
[ ] Crear espada
[ ] Implementar combate
```

Solo cuando esto sea estable:

```text
[ ] Arco
[ ] Proyectiles
[ ] Bastón
[ ] Habilidades
[ ] Buffs
[ ] Crowd Control
[ ] Loot
[ ] Progresión
[ ] Enemigos adicionales
[ ] Elites
[ ] Bosses
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

La velocidad de desarrollo importa, pero la arquitectura debe mantenerse suficientemente limpia para que el juego pueda crecer desde el MVP hasta un dungeon crawler roguelite completo sin requerir una reescritura general.
