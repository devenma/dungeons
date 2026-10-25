extends "res://scripts/ui/resource_bar.gd"

## Code-bound stamina bar (ST-hud): tracks the player's
## stamina_changed(current, maximum) signal and initializes from current
## stamina so it is correct at boot and after each floor/death refill.

@export var stamina_node_path: NodePath = NodePath("../../../World/Player/Stamina")


func _ready() -> void:
	super()
	var stamina := get_node_or_null(stamina_node_path) as StaminaComponent
	if stamina == null:
		return
	stamina.stamina_changed.connect(set_value)
	set_value(stamina.current_stamina, stamina.max_stamina)
