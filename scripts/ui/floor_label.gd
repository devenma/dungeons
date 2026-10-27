extends Label

## Piso actual en el HUD ("Piso 2 de 3"); en el gremio, el día del pueblo ("Día 4", D2).
## Current floor on the HUD ("Floor 2 of 3"); in the guild, the town day ("Day 4", D2).

const UiText: GDScript = preload("res://scripts/ui/ui_text.gd")

@export var dungeon_manager_node_path: NodePath = NodePath("../../../World/DungeonManager")
@export var profile_state_node_path: NodePath = NodePath("../../../ProfileState")


func _ready() -> void:
	hide()
	var manager: Node = get_node_or_null(dungeon_manager_node_path)
	if manager != null and manager.has_signal("floor_started"):
		manager.floor_started.connect(_on_floor_started)
		# El juego arranca en el gremio antes de que el HUD escuche / The game boots in the guild before the HUD listens
		_on_floor_started(0, 0)


func _on_floor_started(floor_number: int, floor_count: int) -> void:
	var profile: ProfileState = get_node_or_null(profile_state_node_path) as ProfileState
	visible = floor_number > 0 or profile != null
	if floor_number == 0 and profile != null:
		text = UiText.tr_or("ui.hud.day", "Day %d") % profile.day
	elif floor_count > 0:
		text = UiText.tr_or("ui.hud.floor_of", "Floor %d of %d") % [floor_number, floor_count]
	else:
		text = UiText.tr_or("ui.hud.floor", "Floor %d") % floor_number
