extends Control

## Pantalla breve tras morir: negro con lo que pasó con el botín mientras el jugador aparece en el
## gremio, y fundido de salida. La dispara DungeonManager.returned_from_death.
## Brief screen after dying: black with what happened to the loot while the player appears in the
## guild, then a fade out. Triggered by DungeonManager.returned_from_death.

## Tiempo en negro con el texto (s) / Time on black with the text (s)
@export var hold_seconds: float = 2.5
## Fundido de salida hacia el gremio (s) / Fade out into the guild (s)
@export var fade_seconds: float = 0.6
@export var dungeon_manager_node_path: NodePath = NodePath("../../World/DungeonManager")

@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _detail: Label = %Detail

var _tween: Tween


func _ready() -> void:
	hide()
	var manager: Node = get_node_or_null(dungeon_manager_node_path)
	if manager != null:
		manager.returned_from_death.connect(show_death)


func show_death(blue_stone_used: bool) -> void:
	if blue_stone_used:
		_title.text = "ui.death.with_stone.title"
		_subtitle.text = "ui.death.with_stone.subtitle"
		_detail.text = "ui.death.with_stone.kept"
	else:
		_title.text = "ui.death.title"
		_subtitle.text = "ui.death.no_stone.subtitle"
		_detail.text = "ui.death.no_stone.lost"
	modulate.a = 1.0
	show()
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_interval(hold_seconds)
	_tween.tween_property(self, "modulate:a", 0.0, fade_seconds)
	_tween.tween_callback(hide)
