class_name FloorData
extends Resource

@export var floor_number: int = 1
@export var grid_min_w: int = 4
@export var grid_max_w: int = 8
@export var grid_min_h: int = 4
@export var grid_max_h: int = 6
@export var zone_count_min: int = 3
@export var zone_count_max: int = 5
@export var multi_door_threshold: int = 100
@export var max_doors_per_edge: int = 1
@export var max_generation_retries: int = 5
@export var reward_ratio: float = 0.3
@export var zone_count_by_floor_depth: Dictionary = {1: [3, 5], 10: [6, 12]}
@export var enemy_health_multiplier: float = 1.0
@export var enemy_damage_multiplier: float = 1.0
## Tamaño mínimo de una zona en celdas (ancho × alto). El generador particiona la
## grilla en rectángulos que nunca bajan de este mínimo; 2×2 = 512×512 px, el
## rectángulo más chico que contiene el viewport de 480×270 px.
## Minimum zone size in cells (width × height). The generator partitions the grid
## into rectangles that never go below this minimum; 2×2 = 512×512 px, the
## smallest rectangle that contains the 480×270 px viewport.
@export var zone_min_cells: Vector2i = Vector2i(2, 2)

## Tamaño máximo de la zona START en celdas; el generador aísla la esquina START
## a este tamaño. Debe ser >= zone_min_cells (0 = sin tope).
## Max START zone size in grid cells; the generator isolates the START corner at
## this size. Must be >= zone_min_cells (0 = no cap).
@export var start_zone_max_cells: Vector2i = Vector2i(2, 2)
