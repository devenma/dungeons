extends Control

## Elección de reliquia (D28): el cofre de una zona REWARD ofrece hasta tres reliquias en tarjetas y se elige una,
## que pasa a RunManager.relics. Pausa el juego mientras está abierto y no se cancela: elegir es parte del cofre.
## `move_left` / `move_right` eligen y `attack` o `interact` confirman.
## Relic pick (D28): a REWARD zone chest offers up to three relics as cards and one is picked, going into
## RunManager.relics. Pauses the game while open and cannot be cancelled: picking is part of the chest.
## `move_left` / `move_right` pick and `attack` or `interact` confirm.

const UiText: GDScript = preload("res://scripts/ui/ui_text.gd")

@export var run_manager_node_path: NodePath = NodePath("../../RunManager")

var _choices: Array[RelicData] = []

@onready var _cards: Array[Button] = [%Card0, %Card1, %Card2]


func _ready() -> void:
	add_to_group("relic_panel")
	hide()
	for i in _cards.size():
		_cards[i].pressed.connect(pick.bind(i))


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("move_left") or event.is_action_pressed("move_right"):
		var focused: int = _cards.find(get_viewport().gui_get_focus_owner() as Button)
		var step: int = -1 if event.is_action_pressed("move_left") else 1
		_cards[posmod(focused + step, _choices.size())].grab_focus()
	elif event.is_action_pressed("attack") or event.is_action_pressed("interact"):
		var focused_card: int = _cards.find(get_viewport().gui_get_focus_owner() as Button)
		if focused_card >= 0:
			pick(focused_card)
	elif not event.is_action_pressed("pause"):
		return
	get_viewport().set_input_as_handled()


func offer(choices: Array[RelicData]) -> void:
	_choices = choices
	%Title.text = UiText.tr_or("ui.relic.title", "Relics")
	%Line.text = UiText.tr_or("ui.relic.line", "Take one. The rest stay with the dead.")
	for i in _cards.size():
		_cards[i].visible = i < choices.size()
		if i < choices.size():
			_cards[i].text = tr(choices[i].name_key) + "\n" + tr(choices[i].desc_key)
	get_tree().paused = true
	show()
	_cards[0].grab_focus()


func pick(index: int) -> void:
	if not visible or index >= _choices.size():
		return
	var run_manager: RunManager = get_node_or_null(run_manager_node_path) as RunManager
	if run_manager != null:
		run_manager.add_relic(_choices[index])
	hide()
	get_tree().paused = false
