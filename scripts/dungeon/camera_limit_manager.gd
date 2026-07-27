extends Node

@export var player_node_path: NodePath

@onready var player: Node2D = get_node(player_node_path)

var _last_transition_time: float = 0.0
const TRANSITION_COOLDOWN: float = 0.5


func _ready() -> void:
	var root := get_tree().current_scene
	if root != null:
		_connect_all_triggers(root)
	_set_initial_limits()


func _set_initial_limits() -> void:
	if player == null:
		return
	var cam := player.get_node("Camera2D") as Camera2D
	if cam == null:
		return
	# Find the start room (room group) and use its bounds
	var rooms := get_tree().get_nodes_in_group("room")
	for room in rooms:
		if room.has_method("get_script") and room.get_script():
			if "room_type" in room and room.get("room_type") == 0:  # RoomType.START = 0
				var room_pos := (room as Node2D).position
				var rw = room.get("room_width") if "room_width" in room else 1600
				var rh = room.get("room_height") if "room_height" in room else 1200
				cam.limit_left = int(room_pos.x)
				cam.limit_top = int(room_pos.y)
				cam.limit_right = int(room_pos.x + rw)
				cam.limit_bottom = int(room_pos.y + rh)
				return
	# Fallback: default bounds
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = 1600
	cam.limit_bottom = 1200


func _connect_all_triggers(node: Node) -> void:
	for child in node.get_children():
		if child is Area2D and child.has_method("get_script") and child.get_script():
			if "target_room_path" in child:
				var trigger := child as Area2D
				var target_node := trigger.get_node_or_null(trigger.get("target_room_path"))
				if target_node == null:
					continue
				if trigger.room_entered.is_connected(_on_room_entered):
					continue
				trigger.room_entered.connect(_on_room_entered.bind(target_node))
		_connect_all_triggers(child)


func _on_room_entered(_player: Node2D, target_room: Node) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_transition_time < TRANSITION_COOLDOWN:
		return
	_last_transition_time = now

	if target_room == null:
		return
	var cam := player.get_node("Camera2D") as Camera2D
	if cam == null:
		return
	var room_pos := (target_room as Node2D).position
	var rw = target_room.get("room_width") if "room_width" in target_room else 1600
	var rh = target_room.get("room_height") if "room_height" in target_room else 1200
	cam.limit_left = int(room_pos.x)
	cam.limit_top = int(room_pos.y)
	cam.limit_right = int(room_pos.x + rw)
	cam.limit_bottom = int(room_pos.y + rh)