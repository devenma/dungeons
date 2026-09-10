extends SceneTree

## Arrow hit assertion (PH-1/PH-2): an Arrow overlapping an enemy Hurtbox
## routes DamageInfo through take_hit, dropping Health by arrow damage,
## and frees itself. Exit 0 = pass, 1 = fail.

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

	var enemy_packed: PackedScene = load("res://scenes/enemies/enemy_base.tscn") as PackedScene
	var enemy: Node = enemy_packed.instantiate() as Node
	container.add_child(enemy)
	enemy.position = Vector2(100, 100)
	for i in range(3):
		await physics_frame

	var health := (enemy as Node).get_node("Health") as HealthComponent
	var initial: int = health.current_health
	var expected: int = initial - 8

	var arrow_packed: PackedScene = load("res://scenes/projectiles/arrow.tscn") as PackedScene
	var arrow: Area2D = arrow_packed.instantiate() as Area2D
	arrow.damage = 8
	arrow.knockback = Vector2(12, 0)
	arrow.speed = 400.0
	arrow.direction = Vector2.RIGHT
	container.add_child(arrow)
	arrow.global_position = Vector2(100, 100)
	for i in range(5):
		await physics_frame

	_check(is_instance_valid(arrow) == false, "PH-2: arrow freed after hit")
	_check(health.current_health == expected, "PH-1: enemy health %d -> %d" % [initial, expected])

	_check(_failures == 0, "arrow hits slime: all checks passed")
	quit(0 if _failures == 0 else 1)
