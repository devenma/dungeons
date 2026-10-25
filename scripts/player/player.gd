extends CharacterBody2D

## Movimiento en 8 direcciones y orientación; el resto vive en componentes hijos (§35).
## 8-direction movement and facing; everything else lives in child components (§35).
## La animación la elige PlayerAnimator / The animation is picked by PlayerAnimator.

## Velocidad de caminata (px/s) / Walk speed (px/s)
@export var speed: float = 60.0
@onready var knockback: KnockbackComponent = get_node_or_null("Knockback") as KnockbackComponent

# Last nonzero move direction; aim for weapons defaults to Down (SW-3).
var last_move_direction: Vector2 = Vector2.DOWN


func _ready() -> void:
	add_to_group("player")


func aim_direction() -> Vector2:
	return last_move_direction


func _physics_process(delta: float) -> void:
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = direction * speed
	# Un empuje activo reemplaza al input (aturdimiento breve) / An active push overrides input (brief stagger)
	var push: Vector2 = knockback.consume(delta) if knockback != null else Vector2.ZERO
	if push != Vector2.ZERO:
		velocity = push
	move_and_slide()
	if direction != Vector2.ZERO:
		last_move_direction = direction.normalized()
