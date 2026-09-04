extends CharacterBody2D

@export var speed := 200.0
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

func _physics_process(_delta: float) -> void:
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = direction * speed
	move_and_slide()
	# animaciones
	if direction != Vector2.ZERO:
		sprite.play("Walk_Down")
		sprite.flip_h = direction.x < 0
	else:
		sprite.play("Idle_Down")
		sprite.flip_h = false
