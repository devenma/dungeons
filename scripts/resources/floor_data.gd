class_name FloorData
extends Resource

@export var floor_number: int = 1
@export var grid_min_w: int = 3
@export var grid_max_w: int = 6
@export var grid_min_h: int = 3
@export var grid_max_h: int = 5
@export var zone_count_min: int = 3
@export var zone_count_max: int = 5
@export var multi_door_threshold: int = 3
@export var max_doors_per_edge: int = 2
@export var max_generation_retries: int = 5
@export var reward_ratio: float = 0.3
@export var zone_count_by_floor_depth: Dictionary = {1: [3, 5], 10: [6, 12]}
@export var enemy_health_multiplier: float = 1.0
@export var enemy_damage_multiplier: float = 1.0
