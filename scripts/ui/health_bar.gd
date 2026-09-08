extends ProgressBar

## Minimal code-bound health bar (HB-1): tracks the player's
## health_changed(current, maximum) signal and initializes from current
## health so it is correct at boot and after each death reset.

@export var health_node_path: NodePath = NodePath("../../World/Player/Health")


func _ready() -> void:
	var health := get_node_or_null(health_node_path) as HealthComponent
	if health == null:
		return
	health.health_changed.connect(_on_health_changed)
	_on_health_changed(health.current_health, health.max_health)


func _on_health_changed(current: int, maximum: int) -> void:
	max_value = maximum
	value = current
