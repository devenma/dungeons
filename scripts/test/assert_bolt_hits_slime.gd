extends SceneTree

## Magic bolt hit assertion (R-magic-bolt): a magic_bolt.tscn bolt (arrow.gd
## unchanged) overlapping an enemy Hurtbox routes DamageInfo through
## take_hit, dropping Health by exactly the bolt damage, and frees itself.
## Exit 0 = pass, 1 = fail.

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

	var bolt_damage: int = 14
	var health: HealthComponent = enemy.get_node("Health") as HealthComponent
	var initial: int = health.current_health
	var expected: int = initial - bolt_damage

	var bolt_packed: PackedScene = load("res://scenes/projectiles/magic_bolt.tscn") as PackedScene
	var bolt: Area2D = bolt_packed.instantiate() as Area2D
	bolt.damage = bolt_damage
	bolt.knockback = Vector2(12, 0)
	bolt.speed = 280.0
	bolt.direction = Vector2.RIGHT
	container.add_child(bolt)
	bolt.global_position = Vector2(100, 100)
	for i in range(5):
		await physics_frame

	_check(is_instance_valid(bolt) == false, "MB-2: bolt freed after hit")
	_check(health.current_health == expected,
			"MB-1: enemy health %d -> %d (damage %d)" % [initial, expected, bolt_damage])

	_check(_failures == 0, "bolt hits slime: all checks passed")
	quit(0 if _failures == 0 else 1)
