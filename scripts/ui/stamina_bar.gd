extends ProgressBar

## Minimal code-bound stamina bar (ST-hud): tracks the player's
## stamina_changed(current, maximum) signal and initializes from current
## stamina so it is correct at boot and after each floor/death refill.

@export var stamina_node_path: NodePath = NodePath("../../World/Player/Stamina")


func _ready() -> void:
	var stamina := get_node_or_null(stamina_node_path) as StaminaComponent
	if stamina == null:
		return
	stamina.stamina_changed.connect(_on_stamina_changed)
	_on_stamina_changed(stamina.current_stamina, stamina.max_stamina)


func _on_stamina_changed(current: int, maximum: int) -> void:
	max_value = maximum
	value = current
