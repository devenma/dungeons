extends SceneTree

## Layer-flip assertion (phase 8): after the player body moves to layer 2,
## mask-2 sensor areas (ExitArea / door Area2D semantics) MUST detect the
## player body and MUST NOT detect enemy bodies (HP-2 end state).
## Exit 0 = pass, 1 = fail.

var _failures: int = 0
var _sensor_hits: int = 0


func _initialize() -> void:
	_run()


func _frames(count: int) -> void:
	for i in range(count):
		await physics_frame


func _on_sensor_body_entered(_body: Node2D) -> void:
	_sensor_hits += 1


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		print("FAIL: " + label)


func _run() -> void:
	var sensor := Area2D.new()
	sensor.collision_layer = CollisionLayers.WORLD
	sensor.collision_mask = CollisionLayers.PLAYER_BODY
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(48, 48)
	shape.shape = rect
	sensor.add_child(shape)
	sensor.body_entered.connect(_on_sensor_body_entered)
	root.add_child(sensor)

	var player := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as Node2D
	player.position = Vector2.ZERO
	root.add_child(player)

	await _frames(3)
	_check(_sensor_hits >= 1, "flip: mask-2 sensor detects the player body (layer 2)")

	_sensor_hits = 0
	var enemy := CharacterBody2D.new()
	enemy.collision_layer = CollisionLayers.ENEMY_BODY
	enemy.collision_mask = 0
	var enemy_shape := CollisionShape2D.new()
	enemy_shape.shape = rect
	enemy.add_child(enemy_shape)
	enemy.position = Vector2.ZERO
	root.add_child(enemy)

	await _frames(3)
	_check(_sensor_hits == 0, "flip: mask-2 sensor ignores enemy bodies (layer 4)")

	_check(_failures == 0, "layer flip: all checks passed")
	quit(0 if _failures == 0 else 1)
