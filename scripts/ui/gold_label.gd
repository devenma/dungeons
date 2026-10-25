extends Label

## Gold counter (S5). Reads RunManager's display gold, so changing the banking
## policy (immediate vs run loot) never touches this label.
## Contador de oro (S5). Lee el oro visible de RunManager: cambiar la política
## de banca (inmediata vs loot de la run) no toca este label.

@export var run_manager_node_path: NodePath = NodePath("../../RunManager")


func _ready() -> void:
	var run_manager := get_node_or_null(run_manager_node_path) as RunManager
	if run_manager == null:
		return
	run_manager.gold_changed.connect(_on_gold_changed)
	_on_gold_changed(run_manager.get_display_gold())


func _on_gold_changed(total: int) -> void:
	text = "Gold: %d" % total
