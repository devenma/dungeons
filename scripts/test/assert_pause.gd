extends SceneTree

## Run: godot --headless -s scripts/test/assert_pause.gd
## Pause menu: the `pause` action pauses the tree and shows the menu, a
## second press resumes and hides it, Resume also unpauses, and pausable
## nodes stop processing while paused. Exit 0 = pass, 1 = fail.

const PauseMenuScene: PackedScene = preload("res://scenes/ui/pause_menu.tscn")

var _failures: int = 0


class TickCounter:
	extends Node
	var ticks: int = 0

	func _process(_delta: float) -> void:
		ticks += 1


func _initialize() -> void:
	_run()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		print("FAIL: " + label)


func _press_pause() -> void:
	var press := InputEventAction.new()
	press.action = "pause"
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventAction.new()
	release.action = "pause"
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	await process_frame
	await process_frame


func _run() -> void:
	var menu: Control = PauseMenuScene.instantiate() as Control
	root.add_child(menu)
	var counter: TickCounter = TickCounter.new()
	root.add_child(counter)
	await process_frame
	await process_frame

	_check(not paused and not menu.visible, "starts unpaused with the menu hidden")

	await _press_pause()
	_check(paused, "pause action pauses the tree")
	_check(menu.visible, "menu shown while paused")
	var ticks_at_pause: int = counter.ticks
	for i in range(5):
		await process_frame
	_check(counter.ticks == ticks_at_pause, "pausable nodes stop processing")

	await _press_pause()
	_check(not paused, "second pause press resumes")
	_check(not menu.visible, "menu hidden after resuming")

	await _press_pause()
	var resume: Button = menu.get_node("%ResumeButton") as Button
	resume.pressed.emit()
	await process_frame
	_check(not paused and not menu.visible, "Resume button unpauses and hides the menu")

	quit(0 if _failures == 0 else 1)
