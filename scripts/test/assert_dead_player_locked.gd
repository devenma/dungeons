extends SceneTree

## Run: godot --headless -s scripts/test/assert_dead_player_locked.gd
## Dead player lock (audit bug): during the ~0.5 s between death and the
## return to the guild the dead player cannot walk, roll or attack, and the
## floor exit does not take it to the next floor. The killing hit also shakes
## the camera by whole pixels and the shake settles back to zero.
## Exit 0 = pass, 1 = fail.

const SAVE_PATH: String = "user://test_dead_player_locked.json"

# Mirror of sword.gd SwingState.
const IDLE: int = 0

var _failures: int = 0


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


func _action_event(action: String) -> InputEventAction:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _cleanup() -> void:
	for path in [SAVE_PATH, SAVE_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _run() -> void:
	_cleanup()
	var main := (load("res://scenes/main/main.tscn") as PackedScene).instantiate() as Node
	main.get_node("ProfileState").set("save_path", SAVE_PATH)
	root.add_child(main)
	current_scene = main
	await _frames(3)
	var run_manager: RunManager = main.get_node("RunManager")
	var dm: Node = main.get_node("World/DungeonManager")
	var player: CharacterBody2D = main.get_node("World/Player") as CharacterBody2D
	var health: HealthComponent = player.get_node("Health") as HealthComponent
	var roll: RollComponent = player.get_node("Roll") as RollComponent
	var camera: Camera2D = player.get_node("Camera2D") as Camera2D
	dm.call("start_expedition")
	await _frames(3)
	var sword: Node2D = (player.get_node("Weapons") as Node2D).get_child(0) as Node2D
	var exit_area: Node = main.get_node("World/DungeonManager/Dungeon/ExitArea")

	health.take_damage(DamageInfo.new(999, Vector2.ZERO))
	_check(player.call("is_dead") as bool, "player is dead")
	var shook: bool = false
	var whole_pixels: bool = true
	for i in range(4):
		await process_frame
		shook = shook or camera.offset != Vector2.ZERO
		whole_pixels = whole_pixels and camera.offset == camera.offset.round()
	_check(shook and whole_pixels, "the hit shakes the camera by whole pixels")

	var start: Vector2 = player.global_position
	Input.action_press("move_right")
	player._unhandled_input(_action_event("roll"))
	sword._unhandled_input(_action_event("attack"))
	await _frames(10)
	_check(player.global_position == start, "dead player does not walk")
	_check(not roll.is_rolling(), "dead player does not roll")
	_check(int(sword.get("_state")) == IDLE, "dead player does not attack")
	Input.action_release("move_right")

	exit_area.call("_trigger")
	await _frames(2)
	_check(run_manager.current_floor == 1, "the exit does not change floor while dead")

	await create_timer(1.0).timeout
	_check(run_manager.current_floor == 0 and not (player.call("is_dead") as bool), "death still returns to the guild alive")
	_check(camera.offset == Vector2.ZERO, "the shake settles back to zero")

	main.queue_free()
	_cleanup()
	quit(0 if _failures == 0 else 1)
