extends CharacterBody2D

## Personaje de la zona de pruebas: camina en 8 direcciones con move_* y juega idle/walk del kit hacia donde va.
## Test zone character: walks in 8 directions with move_* and plays the kit idle/walk toward where it goes.

const KitSpriteScript: GDScript = preload("res://scripts/visual/kit_sprite.gd")

# Velocidad de caminata (px/s), la del jugador / walk speed (px/s), the player's
@export var walk_speed: float = 60.0

# Fila (S, E, N o W) hacia la que mira / Row (S, E, N or W) it faces
var _facing: String = "S"

@onready var _sprite: AnimatedSprite2D = $Sprite


# En _process y no en _physics_process: la física va a 60 Hz y en un monitor de 120 Hz la cámara (hija del personaje)
# avanzaba un cuadro sí y uno no / In _process, not _physics_process: physics runs at 60 Hz and on a 120 Hz monitor the
# camera (child of the character) moved every other frame
func _process(_delta: float) -> void:
	var direction: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = direction * walk_speed
	move_and_slide()
	if direction == Vector2.ZERO:
		_sprite.play("idle_" + _facing)
		return
	_facing = KitSpriteScript.row_for(direction)
	var walk_name: StringName = "walk_" + _facing
	_sprite.play(walk_name, _sprite.call("playback_speed", walk_name, velocity.length()))
