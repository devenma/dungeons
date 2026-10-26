class_name FloorData
extends Resource

## Parámetros de generación de un piso (§25) / Floor generation parameters (§25)

## Piso al que aplica (informativo; el generador recibe el número aparte) / Floor it applies to (informative; the generator gets the number separately)
@export var floor_number: int = 1
## Ancho de la grilla en celdas, mín./máx. / Grid width in cells, min/max
@export var grid_min_w: int = 2
@export var grid_max_w: int = 4
## Alto de la grilla en celdas, mín./máx. / Grid height in cells, min/max
@export var grid_min_h: int = 2
@export var grid_max_h: int = 3
## Rango de zonas si zone_count_by_floor_depth no tiene entrada / Zone range when zone_count_by_floor_depth has no entry
@export var zone_count_min: int = 4
@export var zone_count_max: int = 6
## Largo de arista (tiles) desde el que caben varias puertas / Edge length (tiles) from which several doors fit
@export var multi_door_threshold: int = 100
## Máximo de puertas por arista compartida / Max doors per shared edge
@export var max_doors_per_edge: int = 1
## Intentos de generación antes de fallar (sin fallback) / Generation attempts before failing (no fallback)
@export var max_generation_retries: int = 5
## Probabilidad (0-1) de que una zona que no es START/EXIT sea REWARD / Chance (0-1) that a non-START/EXIT zone is REWARD
@export var reward_ratio: float = 0.3
## Piso desde el que aplica → [mín., máx.] de zonas / Floor it applies from → [min, max] zones
@export var zone_count_by_floor_depth: Dictionary = {1: [4, 6], 10: [7, 12]}
## Multiplicadores de vida y daño enemigo; los aplica el Spawner (§25) / Enemy health and damage multipliers; the Spawner applies them (§25)
@export var enemy_health_multiplier: float = 1.0
@export var enemy_damage_multiplier: float = 1.0
## Zona BOSS en celdas, en la esquina sureste, con una antesala EVENT como única entrada; el piso no
## tiene EXIT. ZERO = piso sin jefe (D22)
## BOSS zone in cells, at the south-east corner, with an EVENT antechamber as its only way in; the
## floor has no EXIT. ZERO = floor without a boss (D22)
@export var boss_zone_cells: Vector2i = Vector2i.ZERO

@export_group("Enemies")
## Pool de enemigos del piso; vacío = la lista fija del Spawner (rigs de test) / Floor enemy pool; empty = the Spawner's fixed list (test rigs)
@export var enemy_pool: Array[EnemySpawnData] = []
## Presupuesto de amenaza por pantalla de sala (D22) / Threat budget per room screen (D22)
@export var threat_budget_per_cell: int = 4
## Élite que ocupa sola una zona COMBAT; null = sin élite / Elite that takes a COMBAT zone alone; null = no elite
@export var elite_scene: PackedScene
## Probabilidad de que el piso tenga zona de élite (1 = garantizada) / Chance the floor has an elite zone (1 = guaranteed)
@export var elite_chance: float = 0.0
## Tamaño de la zona START en celdas, recortado en el origen (0 = sin tope); si es menor que
## min_zone_cells gana el mínimo. 1×1 = una pantalla.
## START zone size in grid cells, carved at the origin (0 = no cap); min_zone_cells wins if larger.
## 1×1 = one screen.
@export var start_zone_max_cells: Vector2i = Vector2i(1, 1)
## Tamaño mínimo de cada zona en celdas: 1×1 = una pantalla de sala (DungeonGeometry.CELL_TILES).
## La grilla crece más allá de grid_max_* si hace falta para que entren las zonas.
## Min size of every zone in grid cells: 1×1 = one room screen (DungeonGeometry.CELL_TILES).
## The grid grows past grid_max_* when needed to fit the zones.
@export var min_zone_cells: Vector2i = Vector2i(1, 1)
## Todas las zonas del tamaño mínimo (con 1×1, una pantalla cada una): la grilla se elige para que
## tenga tantas celdas como zonas. false = los cortes pueden dejar zonas más grandes.
## Every zone at the minimum size (one screen each with 1×1): the grid is picked so it holds exactly
## as many cells as zones. false = cuts may leave bigger zones.
@export var min_size_zones_only: bool = true
