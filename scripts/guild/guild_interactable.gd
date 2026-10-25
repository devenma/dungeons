extends Area2D

## Punto de interacción repetible del gremio: emite `interacted` con `interact` si el jugador lo pisa.
## Repeatable guild interaction spot: emits `interacted` on `interact` while the player overlaps it.

signal interacted


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and _player_overlaps():
		interacted.emit()


# Se consulta el solape en vez de seguir body_entered: el gremio se apaga y se
# prende sin que lleguen los body_exited / Overlap is queried instead of tracking
# body_entered: the guild is toggled off and on without body_exited arriving
func _player_overlaps() -> bool:
	for body in get_overlapping_bodies():
		if body.is_in_group("player"):
			return true
	return false
