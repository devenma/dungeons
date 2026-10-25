extends SceneTree

## Run: godot --headless -s scripts/test/assert_sword_rooting.gd
## Sword rooting (D4): on the real player.tscn, holding a move direction does
## not move the player from anticipation through recovery; the only motion is
## the swing's small forward step during the active hit (SwingData.step_distance,
## along the aim, not the input). The attack keeps facing its aim while the
## input changes. Once the swing is over the player walks again. Exit 0 = pass.

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")

# Mirror of sword.gd SwingState.
const IDLE: int = 0
const ANTICIPATION: int = 1
const ACTIVE: int = 2
const RECOVERY: int = 3

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
	var container: Node2D = Node2D.new()
	root.add_child(container)
	current_scene = container
	var player: CharacterBody2D = PlayerScene.instantiate() as CharacterBody2D
	container.add_child(player)
	for i in range(3):
		await physics_frame
	var sword: Node2D = (player.get_node("Weapons") as Node2D).get_child(0) as Node2D
	var sprite: AnimatedSprite2D = player.get_node("AnimatedSprite2D") as AnimatedSprite2D
	var swing: SwingData = (sword.get("data") as WeaponData).combo[0]

	Input.action_press("move_right")
	_check(sword.call("try_attack", Vector2.LEFT) as bool, "swing toward W accepted while walking E")
	var moved_outside_active: float = 0.0
	var active_shift: float = 0.0
	var wrong_facing: int = 0
	var last: Vector2 = player.global_position
	var swapped_input: bool = false
	# The player moves before the sword updates its phase: a frame's motion belongs to the phase seen before it.
	var prev_state: int = int(sword.get("_state"))
	for i in range(240):
		await physics_frame
		var state: int = int(sword.get("_state"))
		var step: Vector2 = player.global_position - last
		last = player.global_position
		if prev_state == ACTIVE:
			active_shift += step.x
		else:
			moved_outside_active += step.length()
		prev_state = state
		if state == IDLE:
			break
		if state == RECOVERY and not swapped_input:
			Input.action_release("move_right")
			Input.action_press("move_up")
			swapped_input = true
		if sprite.animation != "attack_W":
			wrong_facing += 1
	_check(moved_outside_active < 0.01, "rooted in anticipation and recovery despite input (moved %.2f px)" % moved_outside_active)
	_check(absf(active_shift + swing.step_distance) <= 1.5,
			"active hit steps %.1f px along the aim, not the input (got %.2f)" % [swing.step_distance, active_shift])
	_check(wrong_facing == 0, "attack keeps facing W while the input changes (%d frames off)" % wrong_facing)

	var before_walk: Vector2 = player.global_position
	for i in range(10):
		await physics_frame
	_check(player.global_position.y < before_walk.y - 3.0, "walks again once the swing is over")
	Input.action_release("move_up")

	container.queue_free()
	quit(0 if _failures == 0 else 1)
