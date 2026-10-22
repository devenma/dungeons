extends Control

## Pause overlay: the `pause` action toggles get_tree().paused and this
## menu. The node runs with PROCESS_MODE_ALWAYS (set in the scene) so it
## keeps receiving input while everything else is paused.

@onready var _resume_button: Button = %ResumeButton
@onready var _quit_button: Button = %QuitButton


func _ready() -> void:
	hide()
	_resume_button.pressed.connect(set_paused.bind(false))
	_quit_button.pressed.connect(_on_quit_pressed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()


func set_paused(paused: bool) -> void:
	get_tree().paused = paused
	visible = paused
	if paused:
		_resume_button.grab_focus()


func _on_quit_pressed() -> void:
	get_tree().quit()
