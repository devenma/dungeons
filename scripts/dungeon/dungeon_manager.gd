extends Node

@export var player_node_path: NodePath
@export var run_manager_node_path: NodePath
@export var floor_data: FloorData

@onready var player: Node2D = get_node(player_node_path)

# Pixel geometry for tile_rect comes from DungeonGeometry (single source of
# truth; zones render from the editor-authored 32px tileset).

func _get_run_manager():
	return get_node(run_manager_node_path) if run_manager_node_path else null

var _current_layout
var _dead_handling: bool = false

# Runtime nodes
var _dungeon: Node2D
var _tilemap: TileMap
var _door_controller: Node
var _spawner: Node

# Local alias: referenced by preloaded script instead of any global
# `ReturnExit`/class_name, which is not registered in headless runs
# without an editor scan (spawner.gd precedent).
const ExitScene: PackedScene = preload("res://scenes/dungeon/exit.tscn")
const ExitScript: GDScript = preload("res://scripts/dungeon/exit_area.gd")


func _ready() -> void:
	if floor_data == null:
		floor_data = FloorData.new()
	# Hook player death BEFORE the floor starts (DR-1, §44.16).
	var health := player.get_node_or_null("Health") as HealthComponent
	if health != null:
		health.died.connect(_on_player_died)
	var run_manager = _get_run_manager()
	if run_manager != null:
		run_manager.start_new_run()
	_start_floor()


func _on_player_died() -> void:
	if _dead_handling:
		return
	_dead_handling = true
	await get_tree().create_timer(0.5).timeout
	var health := player.get_node_or_null("Health") as HealthComponent
	if health != null:
		health.reset_health()
	_refill_stamina()
	var run_manager = _get_run_manager()
	if run_manager != null:
		run_manager.start_new_run()
	_start_floor()
	_dead_handling = false


## Refill stamina to full (ST-reset): called at the top of `_start_floor()`
## for every floor transition; death routing also refills here, so no
## second hook exists and a double call is idempotent.
func _refill_stamina() -> void:
	var stamina := player.get_node_or_null("Stamina") as StaminaComponent
	if stamina != null:
		stamina.reset_full()


func _start_floor() -> void:
	var run_manager = _get_run_manager()
	if run_manager == null:
		return

	_refill_stamina()

	# Clear previous floor
	_clear_floor()

	run_manager.current_floor += 1

	# 1  Generate floor layout
	var generator : = DungeonGenerator.new()
	var layout = generator.generate_floor(
		run_manager.current_floor,
		run_manager.run_seed,
		floor_data
	)
	_current_layout = layout

	# 2  Create dungeon container
	# Keep a direct reference: re-resolving via get_node("Dungeon") during
	# this same frame can return the PREVIOUS floor's node, which is still
	# queue_free-pending and would swallow the ExitArea.
	var dungeon := Node2D.new()
	dungeon.name = "Dungeon"
	_dungeon = dungeon
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

	# PF-1: chest grants flow Spawner -> RunManager (add + auto-equip).
	# Wired BEFORE spawn_content: spawn may place chests that can grant
	# immediately (§44.16).
	if _spawner.has_signal("weapon_granted"):
		_spawner.weapon_granted.connect(_on_weapon_granted)

	if _door_controller.has_signal("zone_entered"):
		var cam_manager :Node = _find_camera_limit_manager()
		if cam_manager != null and cam_manager.has_method("_on_zone_entered"):
			_door_controller.zone_entered.connect(cam_manager._on_zone_entered)

	# 7  Now call spawn (zone_cleared signals will reach DoorController)
	_spawner.spawn_content(layout, dungeon)

	# 8  Create exit Area2D in EXIT zone
	_spawn_exit(layout)

	# 9  Spawn player in START zone
	_spawn_player(layout)

	# 10  Initialize camera limits
	_initialize_camera_limits(layout)


func _on_weapon_granted(data: WeaponData) -> void:
	# PF-1: a granted weapon is added to the run inventory and immediately
	# equipped so the mount/HUD react via weapon_equipped (§3(b)).
	if data == null:
		return
	var run_manager: Node = _get_run_manager()
	if run_manager == null:
		return
	var new_index: int = run_manager.add_weapon(data)
	if new_index >= 0:
		run_manager.equip_weapon(new_index)


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
		cam_manager.initialize(layout, player)


func _spawn_exit(layout) -> void:
	# Find EXIT zone
	var exit_zone = null
	for z in layout.zones:
		if z.type == Zone.ZoneType.EXIT:
			exit_zone = z
			break
	if exit_zone == null:
		return

	var exit := ExitScene.instantiate() as ExitScript
	# Exit zone center
	exit.position = Vector2(
		(exit_zone.tile_rect.position.x + exit_zone.tile_rect.size.x / 2.0) * DungeonGeometry.TILE_SIZE,
		(exit_zone.tile_rect.position.y + exit_zone.tile_rect.size.y / 2.0) * DungeonGeometry.TILE_SIZE
	)
	exit.zone_id = exit_zone.id
	# Relay must be connected BEFORE add_child (§44.16): the scene may emit
	# synchronously during ready-phase entry.
	exit.exit_requested.connect(_go_to_next_floor)
	if _dungeon != null:
		_dungeon.add_child(exit)


func _clear_floor() -> void:
	if _dungeon != null and is_instance_valid(_dungeon):
		# The node stays in the tree until the deferred queue_free lands at
		# frame end; rename it so the next floor can take the "Dungeon" name
		# without an add_child collision.
		_dungeon.name = "%s_old_%d" % [_dungeon.name, _dungeon.get_instance_id()]
		_dungeon.queue_free()
	_dungeon = null
	_tilemap = null
	_door_controller = null
	_spawner = null


func _go_to_next_floor() -> void:
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
		(start_zone.tile_rect.position.x + start_zone.tile_rect.size.x / 2.0) * DungeonGeometry.TILE_SIZE,
		(start_zone.tile_rect.position.y + start_zone.tile_rect.size.y / 2.0) * DungeonGeometry.TILE_SIZE
	)
	player.position = zone_center

	# Reset camera limits to start zone via the camera manager
	var cam_manager :Node = _find_camera_limit_manager()
	if cam_manager != null and cam_manager.has_method("_on_zone_entered"):
		cam_manager._on_zone_entered(start_zone.id)
