extends Label

## Panel de mochila (acción `inventory`, I): lista objetos y cantidades de la mochila y del depósito.
## Backpack panel (`inventory` action, I): lists backpack and guild storage items with counts.

@export var run_manager_node_path: NodePath = NodePath("../../RunManager")
@export var profile_state_node_path: NodePath = NodePath("../../ProfileState")

var _run_manager: RunManager
var _profile: ProfileState


func _ready() -> void:
	hide()
	_run_manager = get_node_or_null(run_manager_node_path) as RunManager
	_profile = get_node_or_null(profile_state_node_path) as ProfileState
	if _run_manager != null:
		_run_manager.backpack_changed.connect(_refresh)
	if _profile != null:
		_profile.profile_changed.connect(_refresh)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		visible = not visible
		_refresh()


func _refresh() -> void:
	if not visible:
		return
	var lines: PackedStringArray = []
	if _run_manager != null:
		lines.append("Backpack (%d gold)" % _run_manager.backpack_gold)
		lines.append_array(_slot_lines(_run_manager.backpack))
	if _profile != null:
		lines.append("")
		lines.append("Guild storage")
		lines.append_array(_slot_lines(_profile.storage))
	text = "\n".join(lines)


func _slot_lines(inventory: Inventory) -> PackedStringArray:
	var lines: PackedStringArray = []
	if inventory.is_empty():
		lines.append("  (empty)")
	for slot in inventory.slots:
		var item: ItemData = slot["item"]
		var count: int = slot["count"]
		lines.append("  %s x%d" % [item.display_name(), count])
	return lines
