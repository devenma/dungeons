class_name FloorData
extends Resource

## Parámetros de generación de un piso (§25) / Floor generation parameters (§25)

## Piso al que aplica (informativo; el generador recibe el número aparte) / Floor it applies to (informative; the generator gets the number separately)
@export var floor_number: int = 1
## Ancho de la grilla en celdas, mín./máx. / Grid width in cells, min/max
@export var grid_min_w: int = 3
@export var grid_max_w: int = 6
## Alto de la grilla en celdas, mín./máx. / Grid height in cells, min/max
@export var grid_min_h: int = 3
@export var grid_max_h: int = 5
## Rango de zonas si zone_count_by_floor_depth no tiene entrada / Zone range when zone_count_by_floor_depth has no entry
@export var zone_count_min: int = 3
@export var zone_count_max: int = 5
## Largo de arista (tiles) desde el que caben varias puertas / Edge length (tiles) from which several doors fit
@export var multi_door_threshold: int = 100
## Máximo de puertas por arista compartida / Max doors per shared edge
@export var max_doors_per_edge: int = 1
## Intentos de generación antes de fallar (sin fallback) / Generation attempts before failing (no fallback)
@export var max_generation_retries: int = 5
## Probabilidad (0-1) de que una zona que no es START/EXIT sea REWARD / Chance (0-1) that a non-START/EXIT zone is REWARD
@export var reward_ratio: float = 0.3
## Piso desde el que aplica → [mín., máx.] de zonas / Floor it applies from → [min, max] zones
@export var zone_count_by_floor_depth: Dictionary = {1: [3, 5], 10: [6, 12]}
## Multiplicadores de vida y daño enemigo; todavía no se leen (§25) / Enemy health and damage multipliers; not read yet (§25)
@export var enemy_health_multiplier: float = 1.0
@export var enemy_damage_multiplier: float = 1.0
## Tamaño de la zona START en celdas, recortado en el origen (0 = sin tope); si es menor que
## min_zone_cells gana el mínimo.
## START zone size in grid cells, carved at the origin (0 = no cap); min_zone_cells wins if larger.
@export var start_zone_max_cells: Vector2i = Vector2i(2, 2)
## Tamaño mínimo de cada zona en celdas: 2×2 = 16×16 tiles = 512×512 px, cubre el viewport de
## 480×270 px. La grilla crece más allá de grid_max_* si hace falta para que entren las zonas.
## Min size of every zone in grid cells: 2×2 = 16×16 tiles = 512×512 px, covers the 480×270 px
## viewport. The grid grows past grid_max_* when needed to fit the zones.
@export var min_zone_cells: Vector2i = Vector2i(2, 2)
