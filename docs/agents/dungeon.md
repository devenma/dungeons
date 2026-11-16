# Dungeon procedural, pisos y jefes (AGENTS.md §20-26, §37)

Parte del contrato de [`AGENTS.md`](../../AGENTS.md); los números de sección son los de ese documento.

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
- arrancar en el gremio de Hondoval y armar el piso 1 con `start_expedition()` (lo pide la entrada a la cripta, en las afueras);
- al morir, `_return_to_guild()`: vuelve al guild sin borrar el perfil; con piedra azul conserva la mochila y asegura las armas recogidas. De la cripta siempre se vuelve al gremio y de noche (D25).

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

Estado actual: la Madre de la Fosa (`scenes/bosses/madre_fosa.tscn`, D21) es el jefe de San Ulmo. Es fija y elige ataques por distancia; cada ataque es un `BossAttackData` (`resources/bosses/`) con tiempos por fase, y la forma vive en el script. La fase 2 entra con la mitad de la vida. `Hurtbox.damage_multiplier` arma los puntos débiles. La barra del jefe (`BossBar`) y el sesgo de cámara (`CameraLimitManager.set_focus`) se piden por grupos (`boss_bar`, `camera_focus`). Al caer, el `Spawner` tira su `drop_table` y `DungeonManager` pinta la Escalera del Farol, que vuelve al guild con todo y marca el dungeon como limpio (`ProfileState.has_cleared`). La fase 2 suma el vómito (deja charcos de bilis) y la *Nana* (atrae, corta la regeneración de stamina y abraza; 60 de daño la cortan).

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
