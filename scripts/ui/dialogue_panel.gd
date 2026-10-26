extends Control

## Panel de diálogo (D14): muestra un DialogueData línea por línea con el nombre de quien habla, escribiendo
## el texto de a poco. `interact` o `attack` completan la línea o pasan a la siguiente; al terminar se cierra
## y emite `finished`. Pausa el juego mientras está abierto. Toca las escenas de cierre de cada dungeon:
## escucha DungeonManager.dungeon_cleared.
## Dialogue panel (D14): shows a DialogueData line by line with the speaker's name, typing the text out.
## `interact` or `attack` complete the line or move to the next one; at the end it closes and emits
## `finished`. Pauses the game while open. Plays each dungeon's closing scene: it listens to
## DungeonManager.dungeon_cleared.

signal finished

const UiText: GDScript = preload("res://scripts/ui/ui_text.gd")

@export var dungeon_manager_node_path: NodePath = NodePath("../../World/DungeonManager")
## Letras por segundo al escribir / Characters per second while typing
@export var characters_per_second: float = 40.0

var _dialogue: DialogueData
var _index: int = 0

@onready var _speaker: Label = %Speaker
@onready var _text: Label = %Text


func _ready() -> void:
	add_to_group("dialogue_panel")
	hide()
	var manager: Node = get_node_or_null(dungeon_manager_node_path)
	if manager != null and manager.has_signal("dungeon_cleared"):
		manager.connect("dungeon_cleared", _on_dungeon_cleared)


func _process(delta: float) -> void:
	if visible and _text.visible_ratio < 1.0:
		var length: int = maxi(_text.get_total_character_count(), 1)
		_text.visible_ratio = minf(_text.visible_ratio + characters_per_second * delta / length, 1.0)


func _input(event: InputEvent) -> void:
	if not visible or not (event.is_action_pressed("interact") or event.is_action_pressed("attack")):
		return
	get_viewport().set_input_as_handled()
	advance()


func play(dialogue: DialogueData) -> void:
	if dialogue == null or dialogue.lines.is_empty():
		return
	_dialogue = dialogue
	_index = 0
	get_tree().paused = true
	show()
	_show_line()


## Completa la línea que se está escribiendo o pasa a la siguiente / Completes the line being typed or moves to the next
func advance() -> void:
	if not visible:
		return
	if _text.visible_ratio < 1.0:
		_text.visible_ratio = 1.0
		return
	_index += 1
	if _index < _dialogue.lines.size():
		_show_line()
		return
	hide()
	get_tree().paused = false
	finished.emit()


func _show_line() -> void:
	var speaker_key: String = _dialogue.speaker_at(_index)
	_speaker.visible = not speaker_key.is_empty()
	_speaker.text = UiText.tr_or(speaker_key, speaker_key)
	_text.text = UiText.tr_or(_dialogue.lines[_index], _dialogue.lines[_index])
	_text.visible_ratio = 0.0


func _on_dungeon_cleared(dungeon: DungeonData, first_time: bool) -> void:
	if first_time and dungeon != null:
		play(dungeon.closing_dialogue)
