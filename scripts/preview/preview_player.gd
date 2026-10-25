extends CharacterBody2D

## Jugador mínimo de la vista previa de arte: movimiento y animaciones idle/walk en 4 direcciones, sin combate.
## Minimal art-preview player: movement and 4-direction idle/walk animations, no combat.

const KitSpriteScript: GDScript = preload("res://scripts/visual/kit_sprite.gd")

# Velocidad en px/s, igual que player.gd / Speed in px/s, same as player.gd
@export var speed: float = 60.0

# Fila de la hoja hacia la que mira: S, E, N o W / Sheet row it faces: S, E, N or W
var _facing: String = "S"

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	sprite.play("idle_" + _facing)


func _physics_process(_delta: float) -> void:
	var direction: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = direction * speed
	move_and_slide()
	if direction == Vector2.ZERO:
		sprite.play("idle_" + _facing)
	else:
		_facing = KitSpriteScript.row_for(direction)
		sprite.play("walk_" + _facing)


## Mira hacia la dirección y queda en idle (capturas) / Faces the direction and idles (screenshots).
func face(direction: Vector2) -> void:
	_facing = KitSpriteScript.row_for(direction)
	sprite.play("idle_" + _facing)
