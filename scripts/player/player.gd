extends CharacterBody2D

@export var speed := 100.0
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
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
	# animaciones
	if direction != Vector2.ZERO:
		last_move_direction = direction.normalized()
		sprite.play("Walk_Down")
		if direction.x != 0.0:
			sprite.flip_h = direction.x < 0.0
	else:
		sprite.play("Idle_Down")
