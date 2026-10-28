extends Label

## Piso actual en el HUD ("Piso 2 de 3"); en el pueblo, el día y si es de noche ("Día 4, noche", D2, D25).
## Current floor on the HUD ("Floor 2 of 3"); in town, the day and whether it is night ("Day 4, night", D2, D25).

const UiText: GDScript = preload("res://scripts/ui/ui_text.gd")

@export var dungeon_manager_node_path: NodePath = NodePath("../../../World/DungeonManager")
@export var profile_state_node_path: NodePath = NodePath("../../../ProfileState")

# Último piso avisado; 0 = en el pueblo / Last floor announced; 0 = in town
var _floor_number: int = 0
var _floor_count: int = 0


func _ready() -> void:
	hide()
	var profile: ProfileState = get_node_or_null(profile_state_node_path) as ProfileState
	if profile != null:
		profile.profile_changed.connect(_refresh)
	var manager: Node = get_node_or_null(dungeon_manager_node_path)
	if manager != null and manager.has_signal("floor_started"):
		manager.floor_started.connect(_on_floor_started)
		# El juego arranca en el gremio antes de que el HUD escuche / The game boots in the guild before the HUD listens
		_on_floor_started(0, 0)


func _on_floor_started(floor_number: int, floor_count: int) -> void:
	_floor_number = floor_number
	_floor_count = floor_count
	_refresh()


func _refresh() -> void:
	var profile: ProfileState = get_node_or_null(profile_state_node_path) as ProfileState
	visible = _floor_number > 0 or profile != null
	if _floor_number == 0 and profile != null:
		if profile.night:
			text = UiText.tr_or("ui.hud.day_night", "Day %d, night") % profile.day
		else:
			text = UiText.tr_or("ui.hud.day", "Day %d") % profile.day
	elif _floor_count > 0:
		text = UiText.tr_or("ui.hud.floor_of", "Floor %d of %d") % [_floor_number, _floor_count]
	else:
		text = UiText.tr_or("ui.hud.floor", "Floor %d") % _floor_number
