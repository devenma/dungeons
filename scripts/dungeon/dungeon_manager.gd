extends Node

@export var player_node_path: NodePath
@export var dungeon_generator_path: NodePath
@export var run_manager_node_path: NodePath
@export var floor_data: FloorData

@onready var player: Node2D = get_node(player_node_path)
@onready var generator: Node = get_node(dungeon_generator_path)

func _get_run_manager():
	return get_node(run_manager_node_path) if run_manager_node_path else null

var _current_layout
var _last_transition_time: float = 0.0
const TRANSITION_COOLDOWN: float = 0.5
var _player_in_exit: bool = false


func _ready() -> void:
	set_process_input(true)
	if floor_data == null:
		floor_data = FloorData.new()
	var run_manager = _get_run_manager()
	if run_manager != null:
		run_manager.start_new_run()
	_start_floor()


func _start_floor() -> void:
	var run_manager = _get_run_manager()
	if run_manager == null:
		return

	# Clear previous floor
	_clear_floor()

	run_manager.current_floor += 1

	# Generate floor layout
	var layout = generator.generate_floor(
		run_manager.current_floor,
		run_manager.run_seed,
		floor_data
	)
	_current_layout = layout

	# Create dungeon container
	var dungeon := Node2D.new()
	dungeon.name = "Dungeon"
	add_child(dungeon)

	# Instantiate rooms (first pass)
	for room_node in layout.rooms:
		_instantiate_room(room_node, dungeon, layout)

	# Connect door triggers (second pass, after all rooms exist)
	for room_node in layout.rooms:
		_connect_room_triggers(room_node, dungeon, layout)

	# Spawn player in start room
	_spawn_player(layout)


func _clear_floor() -> void:
	var existing := get_node_or_null("Dungeon")
	if existing != null and is_instance_valid(existing):
		existing.queue_free()


func _instantiate_room(room_node, dungeon: Node2D, layout) -> void:
	var scene: PackedScene = load(room_node.scene_path)
	if scene == null:
		return

	var instance: Node2D = scene.instantiate()
	instance.name = "Room_%d_%s" % [room_node.id, _room_type_name(room_node.type)]
	instance.position = room_node.position

	# Set room type on the instance
	if instance.has_method("set") and "room_type" in instance:
		instance.set("room_type", room_node.type)

	dungeon.add_child(instance)


func _connect_room_triggers(room_node, dungeon: Node2D, layout) -> void:
	var instance = _find_room_instance(dungeon, room_node.id)
	if instance == null:
		return

	# Connect door triggers based on room graph
	for dir in room_node.doors:
		var neighbor_id = room_node.doors[dir]
		var neighbor = _find_room_in_layout(layout, neighbor_id)
		if neighbor == null:
			continue

		# Find the trigger in this room for that direction
		var trigger = _find_door_trigger(instance, dir)
		if trigger == null:
			continue

		# Find neighbor's room instance (already added to dungeon since second pass)
		var target = _find_room_instance(dungeon, neighbor_id)
		if target == null:
			continue

		# Connect the trigger signal to update camera limits
		if not trigger.room_entered.is_connected(_on_room_entered):
			trigger.room_entered.connect(_on_room_entered.bind(target))

	# Wire exit trigger for EXIT rooms
	if room_node.type == 4:  # RoomType.EXIT
		var exit_trigger := instance.get_node_or_null("ExitTrigger") as Area2D
		if exit_trigger != null:
			exit_trigger.body_entered.connect(_on_exit_body_entered)
			exit_trigger.body_exited.connect(_on_exit_body_exited)


func _on_room_entered(_player: Node2D, target_room: Node) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_transition_time < TRANSITION_COOLDOWN:
		return
	_last_transition_time = now

	# Update camera limits directly
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


func _on_exit_body_entered(body: Node2D) -> void:
	if body is CharacterBody2D:
		_player_in_exit = true


func _on_exit_body_exited(body: Node2D) -> void:
	if body is CharacterBody2D:
		_player_in_exit = false


func _input(event: InputEvent) -> void:
	if _player_in_exit and event.is_action_pressed("interact"):
		_go_to_next_floor()


func _go_to_next_floor() -> void:
	_player_in_exit = false
	_start_floor()


func _find_door_trigger(room_instance: Node, direction: String) -> Area2D:
	for child in room_instance.get_children():
		if child is Area2D and child.has_method("get_script") and child.get_script():
			if "exit_direction" in child and child.get("exit_direction") == direction:
				if child.has_signal("room_entered"):
					return child
		# Recurse
		var found = _find_door_trigger(child, direction)
		if found != null:
			return found
	return null


func _find_room_in_layout(layout, id: int):
	for room in layout.rooms:
		if room.id == id:
			return room
	return null


func _find_room_instance(dungeon: Node2D, id: int) -> Node2D:
	for child in dungeon.get_children():
		if child is Node2D and child.name.begins_with("Room_%d_" % [id]):
			return child
	return null


func _spawn_player(layout) -> void:
	var start_room_node = _find_room_by_type(layout.rooms, 0)  # RoomType.START = 0
	if start_room_node == null:
		return

	# Center player in start room
	var room_center = start_room_node.position + Vector2(800, 600)
	player.position = room_center

	# Reset camera limits to start room
	var cam := player.get_node("Camera2D") as Camera2D
	if cam != null:
		cam.limit_left = int(start_room_node.position.x)
		cam.limit_top = int(start_room_node.position.y)
		cam.limit_right = int(start_room_node.position.x + 1600)
		cam.limit_bottom = int(start_room_node.position.y + 1200)


func _find_room_by_type(rooms: Array, type: int):
	for room in rooms:
		if room.type == type:
			return room
	return null


func _room_type_name(type: int) -> String:
	match type:
		0: return "Start"
		1: return "Combat"
		2: return "Reward"
		3: return "Event"
		4: return "Exit"
	return "Unknown"
