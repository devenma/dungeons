extends Node2D

## Minimal town (S6): `interact` starts a new expedition. The real town flow
## (shop, NPCs, day/night) replaces this placeholder in step 4.
## Pueblo mínimo (S6): `interact` inicia una nueva expedición. El flujo real del
## pueblo (tienda, NPCs, día/noche) reemplaza este placeholder en el paso 4.

const DUNGEON_SCENE_PATH: String = "res://scenes/main/main.tscn"


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		get_tree().change_scene_to_file(DUNGEON_SCENE_PATH)
