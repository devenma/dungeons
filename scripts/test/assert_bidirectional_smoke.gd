extends SceneTree

## Bidirectional combat smoke (phase 4 milestone): proves HP-2/HP-3/HP-4
## end-to-end with nonzero damage in both directions, plus the SW-3 aim
## default and the HC-4 died-once contract. Exit 0 = pass, 1 = fail.

var _failures: int = 0
var _player_died_count: int = 0
var _enemy_died_count: int = 0


func _initialize() -> void:
	_run()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		print("FAIL: " + label)


func _frames(count: int) -> void:
	for i in range(count):
		await physics_frame


func _on_player_died_count() -> void:
	_player_died_count += 1


func _on_enemy_died_count() -> void:
	_enemy_died_count += 1


func _build_double(hitbox_offset: Vector2) -> Node2D:
	# Code-built enemy double: body + Hurtbox(16) + Health(50) + Hitbox(mask 8).
	var body := CharacterBody2D.new()
	body.collision_layer = CollisionLayers.ENEMY_BODY
	body.collision_mask = CollisionLayers.WORLD | CollisionLayers.PLAYER_BODY \
			| CollisionLayers.ENEMY_BODY

	var body_shape := CollisionShape2D.new()
	var body_rect := RectangleShape2D.new()
	body_rect.size = Vector2(16, 16)
	body_shape.shape = body_rect
	body.add_child(body_shape)

	var hurtbox := Area2D.new()
	hurtbox.name = "Hurtbox"
	hurtbox.collision_layer = CollisionLayers.ENEMY_HURTBOX
	hurtbox.collision_mask = 0
	hurtbox.monitoring = false
	hurtbox.monitorable = true
	hurtbox.set_script(load("res://scripts/combat/hurtbox.gd"))
	hurtbox.set("layer_bit", CollisionLayers.ENEMY_HURTBOX)
	body.add_child(hurtbox)

	var hurtbox_shape := CollisionShape2D.new()
	var hurtbox_rect := RectangleShape2D.new()
	hurtbox_rect.size = Vector2(16, 16)
	hurtbox_shape.shape = hurtbox_rect
	hurtbox.add_child(hurtbox_shape)

	var health := load("res://scripts/combat/health_component.gd").new() as HealthComponent
	health.name = "Health"
	health.max_health = 50
	body.add_child(health)

	var hitbox := Area2D.new()
	hitbox.name = "EnemyHitbox"
	hitbox.collision_layer = 0
	hitbox.collision_mask = CollisionLayers.PLAYER_HURTBOX
	hitbox.monitoring = false
	hitbox.monitorable = false
	hitbox.set_script(load("res://scripts/combat/hitbox.gd"))
	hitbox.set("damage", 8)
	hitbox.set("target_mask", CollisionLayers.PLAYER_HURTBOX)
	hitbox.position = hitbox_offset
	body.add_child(hitbox)

	var hitbox_shape := CollisionShape2D.new()
	var hitbox_rect := RectangleShape2D.new()
	hitbox_rect.size = Vector2(24, 24)
	hitbox_shape.shape = hitbox_rect
	hitbox.add_child(hitbox_shape)

	return body


func _run() -> void:
	var player := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as Node2D
	root.add_child(player)

	# double_a takes the sword hit at +100 x (outside the Down swing box).
	var double_a := _build_double(Vector2.ZERO)
	double_a.position = Vector2(100, 0)
	root.add_child(double_a)

	# double_b attacks the player: its hitbox is offset to reach the hurtbox.
	var double_b := _build_double(Vector2(-92, 0))
	double_b.position = Vector2(100, 0)
	root.add_child(double_b)

	await _frames(2)

	var sword := player.get_node("Weapons/Sword") as Node2D
	var player_health := player.get_node("Health") as HealthComponent
	var enemy_health := double_a.get_node("Health") as HealthComponent
	player_health.died.connect(_on_player_died_count)

	# C — no move recorded: aim must default Down (SW-3).
	var swung: bool = sword.call("try_attack") as bool
	await _frames(3)
	_check(swung, "C: try_attack() accepted")
	_check(absf(sword.rotation - PI / 2.0) < 0.01, "C: aim defaults Down (rotation = PI/2)")

	# Cooldown (1/1.5 s) must elapse before the next swing.
	await _frames(50)

	# A — player sword → enemy hurtbox (HP-3, nonzero Player→Enemy damage).
	swung = sword.call("try_attack", Vector2.RIGHT) as bool
	await _frames(5)
	_check(swung, "A: try_attack(RIGHT) accepted")
	_check(absf(sword.rotation) < 0.01, "A: sword rotated to RIGHT")
	_check(enemy_health.current_health == 40, "A: enemy HP 50 -> 40 (took 10)")

	# B — enemy hitbox → player hurtbox, two swings (per-swing hit reset).
	var enemy_hitbox := double_b.get_node("EnemyHitbox") as Hitbox
	enemy_hitbox.begin_swing()
	await _frames(5)
	enemy_hitbox.end_swing()
	await _frames(2)
	enemy_hitbox.begin_swing()
	await _frames(5)
	enemy_hitbox.end_swing()
	await _frames(2)
	_check(player_health.current_health == 84, "B: player HP 100 -> 84 (took 8 x2)")
	_check(_player_died_count == 0, "B: player still alive after two hits")

	# D — death emits `died` exactly once (HC-4), health clamps at 0.
	enemy_health.died.connect(_on_enemy_died_count)
	enemy_health.take_damage(DamageInfo.new(50, Vector2.ZERO))
	enemy_health.take_damage(DamageInfo.new(50, Vector2.ZERO))
	_check(_enemy_died_count == 1, "D: died emitted exactly once")
	_check(enemy_health.current_health == 0, "D: health clamped at 0")

	_check(_failures == 0, "milestone: all checks passed")
	quit(0 if _failures == 0 else 1)
