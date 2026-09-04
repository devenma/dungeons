extends Node

signal zone_cleared(zone_id: int)

var _enemies_by_zone: Dictionary = {}  # zone_id -> Array[Node] (stub, unused for now)


func spawn_content(layout, parent_node: Node) -> void:
	for zone in layout.zones:
		match zone.type:
			Zone.ZoneType.START, Zone.ZoneType.EXIT:
				pass  # no spawn
			Zone.ZoneType.COMBAT:
				_spawn_combat_stub(zone, parent_node)
			Zone.ZoneType.REWARD:
				_spawn_reward_stub(zone, parent_node)


func _spawn_combat_stub(zone, parent_node: Node) -> void:
	# Placeholder: auto-clear combat zones
	zone.cleared = true
	zone_cleared.emit(zone.id)


func _spawn_reward_stub(zone, parent_node: Node) -> void:
	# Placeholder: auto-clear reward zones
	zone.cleared = true
