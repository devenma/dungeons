extends Node

@export var player_node_path: NodePath
@export var run_manager_node_path: NodePath
@export var floor_data: FloorData

@onready var player: Node2D = get_node(player_node_path)

const TILE_SIZE := 16
const CELL_TILES := 8

func _get_run_manager():
	return get_node(run_manager_node_path) if run_manager_node_path else null

var _current_layout
var _last_transition_time: float = 0.0
const TRANSITION_COOLDOWN: float = 0.5
var _player_in_exit: bool = false

# Runtime nodes
var _tilemap: TileMap
var _door_controller: Node
var _spawner: Node
var _exit_area: Area2D


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

	# 1  Generate floor layout
	var generator := DungeonGenerator.new()
	var layout = generator.generate_floor(
		run_manager.current_floor,
		run_manager.run_seed,
		floor_data
	)
	_current_layout = layout

	# 2  Create dungeon container
	var dungeon := Node2D.new()
	dungeon.name = "Dungeon"
	add_child(dungeon)

	# 3  Create and render TileMap
	_tilemap = TileMap.new()
	_tilemap.name = "FloorTileMap"
	dungeon.add_child(_tilemap)
	generator._render_layout(layout, _tilemap)
	generator.queue_free()

	# 4  Create DoorController
	_door_controller = Node.new()
	_door_controller.name = "DoorController"
	_door_controller.set_script(preload("res://scripts/dungeon/door_controller.gd"))
	dungeon.add_child(_door_controller)
	_door_controller.initialize(layout, _tilemap)

	# 5  Create Spawner
	_spawner = Node.new()
	_spawner.name = "Spawner"
	_spawner.set_script(preload("res://scripts/dungeon/spawner.gd"))
	dungeon.add_child(_spawner)

	# 6  Wire signals BEFORE spawn_content (spawn emits zone_cleared synchronously)
	if _spawner.has_signal("zone_cleared") and _door_controller.has_method("on_zone_cleared"):
		_spawner.zone_cleared.connect(_door_controller.on_zone_cleared)

	if _door_controller.has_signal("zone_entered"):
		var cam_manager :Node = _find_camera_limit_manager()
		if cam_manager != null and cam_manager.has_method("_on_zone_entered"):
			_door_controller.zone_entered.connect(cam_manager._on_zone_entered)

	# 7  Now call spawn (zone_cleared signals will reach DoorController)
	_spawner.spawn_content(layout, dungeon)

	# 8  Create exit Area2D in EXIT zone
	_create_exit_area(layout)

	# 9  Spawn player in START zone
	_spawn_player(layout)

	# 10  Initialize camera limits
	_initialize_camera_limits(layout)


func _find_camera_limit_manager():
	# CameraLimitManager is a sibling under World: ../CameraLimitManager
	if get_parent() != null:
		var by_path :Node = get_parent().get_node_or_null("CameraLimitManager")
		if by_path != null:
			return by_path
	# Fallback: search entire tree by script
	return _find_node_by_script(get_tree().root, "res://scripts/dungeon/camera_limit_manager.gd")


func _find_node_by_script(node: Node, script_path: String):
	if node.get_script() and node.get_script().resource_path == script_path:
		return node
	for child in node.get_children():
		var found :Node = _find_node_by_script(child, script_path)
		if found != null:
			return found
	return null


func _initialize_camera_limits(layout) -> void:
	var cam_manager :Node = _find_camera_limit_manager()
	if cam_manager != null and cam_manager.has_method("initialize"):
		cam_manager.initialize(layout)


func _create_exit_area(layout) -> void:
	# Find EXIT zone
	var exit_zone = null
	for z in layout.zones:
		if z.type == Zone.ZoneType.EXIT:
			exit_zone = z
			break
	if exit_zone == null:
		return

	# Create an Area2D covering the exit zone center
	_exit_area = Area2D.new()
	_exit_area.name = "ExitArea"

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	# Size = half the zone in pixels
	var zone_px :Vector2i = exit_zone.tile_rect.size * TILE_SIZE
	rect.size = Vector2(minf(zone_px.x, 64), minf(zone_px.y, 64))
	shape.shape = rect
	_exit_area.add_child(shape)

	# Position at zone center
	var zone_center := Vector2(
		(exit_zone.tile_rect.position.x + exit_zone.tile_rect.size.x / 2.0) * TILE_SIZE,
		(exit_zone.tile_rect.position.y + exit_zone.tile_rect.size.y / 2.0) * TILE_SIZE
	)
	_exit_area.position = zone_center

	_exit_area.body_entered.connect(_on_exit_body_entered)
	_exit_area.body_exited.connect(_on_exit_body_exited)

	# Add to dungeon
	var dungeon := get_node_or_null("Dungeon")
	if dungeon != null:
		dungeon.add_child(_exit_area)


func _clear_floor() -> void:
	var existing := get_node_or_null("Dungeon")
	if existing != null and is_instance_valid(existing):
		existing.queue_free()
	_tilemap = null
	_door_controller = null
	_spawner = null
	_exit_area = null


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


func _spawn_player(layout) -> void:
	# Find START zone
	var start_zone = null
	for z in layout.zones:
		if z.type == Zone.ZoneType.START:
			start_zone = z
			break
	if start_zone == null:
		return

	# Center player in start zone
	var zone_center := Vector2(
		(start_zone.tile_rect.position.x + start_zone.tile_rect.size.x / 2.0) * TILE_SIZE,
		(start_zone.tile_rect.position.y + start_zone.tile_rect.size.y / 2.0) * TILE_SIZE
	)
	player.position = zone_center

	# Reset camera limits to start zone via the camera manager
	var cam_manager :Node = _find_camera_limit_manager()
	if cam_manager != null and cam_manager.has_method("_on_zone_entered"):
		cam_manager._on_zone_entered(start_zone.id)
