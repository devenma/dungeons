extends SceneTree

## Arrow lifecycle assertion (PL-1/PL-2): an Arrow frees itself on contact
## with a world body (StaticBody2D, layer 1) and a lifetime Timer frees an
## arrow that never hits anything. Exit 0 = pass, 1 = fail.

var _failures: int = 0


func _initialize() -> void:
	_run()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		print("FAIL: " + label)


func _run() -> void:
	# Headless spawn target: assign a Node2D container as current_scene.
	var container: Node2D = Node2D.new()
	root.add_child(container)
	current_scene = container

	var wall: StaticBody2D = StaticBody2D.new()
	wall.collision_layer = CollisionLayers.WORLD
	wall.collision_mask = 0
	var wall_shape: CollisionShape2D = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = Vector2(200, 20)
	wall_shape.shape = rect
	wall.add_child(wall_shape)
	wall.position = Vector2(0, 0)
	container.add_child(wall)

	var arrow_packed: PackedScene = load("res://scenes/projectiles/arrow.tscn") as PackedScene

	# PL-1: arrow starts overlapping the wall, moving DOWN into it.
	var wall_arrow: Area2D = arrow_packed.instantiate() as Area2D
	wall_arrow.speed = 400.0
	wall_arrow.direction = Vector2.DOWN
	container.add_child(wall_arrow)
	wall_arrow.global_position = Vector2(0, -6)
	for i in range(10):
		await physics_frame
	_check(is_instance_valid(wall_arrow) == false, "PL-1: arrow freed on wall contact")

	# PL-2: arrow far from wall, no hits -> freed by lifetime (~2s).
	var lifetime_arrow: Area2D = arrow_packed.instantiate() as Area2D
	lifetime_arrow.speed = 400.0
	lifetime_arrow.direction = Vector2.RIGHT
	container.add_child(lifetime_arrow)
	lifetime_arrow.global_position = Vector2(1000, 1000)
	for i in range(150):
		await physics_frame
		if not is_instance_valid(lifetime_arrow):
			break
	_check(is_instance_valid(lifetime_arrow) == false, "PL-2: arrow freed after max_lifetime")

	_check(_failures == 0, "arrow dies on wall: all checks passed")
	quit(0 if _failures == 0 else 1)
