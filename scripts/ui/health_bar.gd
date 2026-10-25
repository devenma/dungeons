extends "res://scripts/ui/resource_bar.gd"

## Code-bound health bar (HB-1): tracks the player's
## health_changed(current, maximum) signal and initializes from current
## health so it is correct at boot and after each death reset.

@export var health_node_path: NodePath = NodePath("../../../World/Player/Health")


func _ready() -> void:
	super()
	var health := get_node_or_null(health_node_path) as HealthComponent
	if health == null:
		return
	health.health_changed.connect(set_value)
	set_value(health.current_health, health.max_health)
