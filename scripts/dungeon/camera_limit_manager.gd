extends Node

@export var player_node_path: NodePath

@onready var player: Node2D = get_node(player_node_path)

var _last_transition_time: float = 0.0
const TRANSITION_COOLDOWN: float = 0.5


func _ready() -> void:
	# Start from the scene root so we find triggers in sibling rooms
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
	# Default to RoomStart bounds (0, 0, 1600, 1200)
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
	cam.limit_left = int(room_pos.x)
	cam.limit_top = int(room_pos.y)
	cam.limit_right = int(room_pos.x + 1600)
	cam.limit_bottom = int(room_pos.y + 1200)