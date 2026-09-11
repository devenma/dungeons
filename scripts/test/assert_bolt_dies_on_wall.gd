extends SceneTree

## Magic bolt lifecycle assertion (R-magic-bolt, arrow death flow reused):
## a magic_bolt.tscn bolt frees itself on contact with a world body
## (StaticBody2D, layer 1) and the arrow.gd max_lifetime timer frees a bolt
## that never hits anything. Exit 0 = pass, 1 = fail.

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

	var bolt_packed: PackedScene = load("res://scenes/projectiles/magic_bolt.tscn") as PackedScene

	# Bolt starts overlapping the wall, moving DOWN into it.
	var wall_bolt: Area2D = bolt_packed.instantiate() as Area2D
	wall_bolt.speed = 280.0
	wall_bolt.direction = Vector2.DOWN
	container.add_child(wall_bolt)
	wall_bolt.global_position = Vector2(0, -6)
	for i in range(10):
		await physics_frame
	_check(is_instance_valid(wall_bolt) == false, "MB-3: bolt freed on wall contact")

	# Bolt far from wall, no hits -> freed by arrow.gd max_lifetime (~2s).
	var lifetime_bolt: Area2D = bolt_packed.instantiate() as Area2D
	lifetime_bolt.speed = 280.0
	lifetime_bolt.direction = Vector2.RIGHT
	container.add_child(lifetime_bolt)
	lifetime_bolt.global_position = Vector2(1000, 1000)
	for i in range(150):
		await physics_frame
		if not is_instance_valid(lifetime_bolt):
			break
	_check(is_instance_valid(lifetime_bolt) == false,
			"MB-4: bolt freed after arrow.gd max_lifetime")

	_check(_failures == 0, "bolt dies on wall: all checks passed")
	quit(0 if _failures == 0 else 1)
