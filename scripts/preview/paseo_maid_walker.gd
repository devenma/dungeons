extends "res://scripts/preview/test_zone_walker.gd"

## Maid en la zona de pruebas: camina con move_* y corre manteniendo roll (Shift / B). Correr todavía no existe en el juego (D26).
## Maid in the test zone: walks with move_* and runs while holding roll (Shift / B). Running is not in the game yet (D26).

# Velocidad de carrera (px/s), la que trae la hoja / run speed (px/s), the sheet's
@export var run_speed: float = 150.0


func _process(_delta: float) -> void:
	var direction: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var running: bool = Input.is_action_pressed("roll")
	velocity = direction * (run_speed if running else walk_speed)
	move_and_slide()
	if direction == Vector2.ZERO:
		_sprite.play("idle_" + _facing)
		return
	_facing = KitSpriteScript.row_for(direction)
	var move_name: StringName = ("run_" if running else "walk_") + _facing
	_sprite.play(move_name, _sprite.call("playback_speed", move_name, velocity.length()))
