class_name EnemyData
extends Resource

## Configurable enemy stats (ES-1, §39): data lives here, behavior in
## enemy.gd.

@export var health: int = 30
@export var speed: float = 60.0
@export var damage: int = 8
@export var detect_radius: float = 120.0
@export var attack_range: float = 20.0
@export var attack_cooldown: float = 1.2
