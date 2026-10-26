extends Label

## Piso actual en el HUD ("Piso 2 de 3"); oculto en el gremio.
## Current floor on the HUD ("Floor 2 of 3"); hidden in the guild.

const UiText: GDScript = preload("res://scripts/ui/ui_text.gd")

@export var dungeon_manager_node_path: NodePath = NodePath("../../../World/DungeonManager")


func _ready() -> void:
	hide()
	var manager: Node = get_node_or_null(dungeon_manager_node_path)
	if manager != null and manager.has_signal("floor_started"):
		manager.floor_started.connect(_on_floor_started)


func _on_floor_started(floor_number: int, floor_count: int) -> void:
	visible = floor_number > 0
	if floor_count > 0:
		text = UiText.tr_or("ui.hud.floor_of", "Floor %d of %d") % [floor_number, floor_count]
	else:
		text = UiText.tr_or("ui.hud.floor", "Floor %d") % floor_number
