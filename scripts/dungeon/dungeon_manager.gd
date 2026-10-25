extends Node

## Floor orchestration (§24) plus the guild <-> expedition transition:
## boots in the guild, `start_expedition()` builds floor 1, and death
## routes through `_return_to_guild()` (D1 + blue stone rule).

# Referenced by preloaded script instead of a class_name, which is not
# registered in headless runs without an editor scan.
const ExitScene: PackedScene = preload("res://scenes/dungeon/exit.tscn")
const ExitScript: GDScript = preload("res://scripts/dungeon/exit_area.gd")
const FloorDressingScript: GDScript = preload("res://scripts/dungeon/floor_dressing.gd")
# Espera entre la muerte y la vuelta al gremio (s) / Delay between death and the return to the guild (s)
const DEATH_RETURN_SECONDS: float = 0.5

@export var player_node_path: NodePath
@export var run_manager_node_path: NodePath
## Perfil persistente; vacío = sin perfil (rigs de test) / Persistent profile; empty = none (test rigs)
@export var profile_state_node_path: NodePath
## Gremio de partida y de vuelta; vacío = arranca directo en un piso / Start and return guild; empty = boot straight into a floor
@export var guild_node_path: NodePath
## Parámetros de generación; null = valores por defecto / Generation parameters; null = defaults
@export var floor_data: FloorData

@onready var player: Node2D = get_node(player_node_path)

var _current_layout: DungeonGenerator.FloorLayout
var _dead_handling: bool = false
var _guild: Node2D
var _in_guild: bool = false

# Nodos del piso actual / Current floor nodes
var _dungeon: Node2D
var _tilemap: TileMap
var _door_controller: Node
var _spawner: Node


func _ready() -> void:
	if floor_data == null:
		floor_data = FloorData.new()
	# Hook player death BEFORE the floor starts (DR-1, §44.16).
	var health := player.get_node_or_null("Health") as HealthComponent
	if health != null:
		health.died.connect(_on_player_died)
	var run_manager: RunManager = _get_run_manager()
	if run_manager != null:
		run_manager.start_new_run(_base_weapons())
	_guild = get_node_or_null(guild_node_path) as Node2D if guild_node_path else null
	if _guild == null:
		_start_floor()
		return
	_guild.expedition_requested.connect(start_expedition)
	_enter_guild()


func _get_run_manager() -> RunManager:
	return get_node(run_manager_node_path) as RunManager if run_manager_node_path else null


func _get_profile_state() -> ProfileState:
	return get_node_or_null(profile_state_node_path) as ProfileState if profile_state_node_path else null


func start_expedition() -> void:
	var run_manager: RunManager = _get_run_manager()
	if run_manager == null:
		return
	run_manager.start_new_run(_base_weapons())
	_in_guild = false
	if _guild != null:
		_guild.set_active(false)
	_start_floor()


## Con piedra azul se conservan mochila y armas recogidas (se aseguran en el perfil);
## sin ella se pierde todo lo de la expedición. La seed se re-rollea siempre.
## With a blue stone the backpack and picked-up weapons are kept (secured in the profile);
## without one the whole expedition is lost. The seed is always re-rolled.
func _return_to_guild() -> void:
	var run_manager: RunManager = _get_run_manager()
	var profile: ProfileState = _get_profile_state()
	if run_manager != null:
		if not run_manager.consume_blue_stone():
			run_manager.lose_backpack()
		elif profile != null:
			profile.owned_weapons = run_manager.owned_weapons.duplicate()
		run_manager.start_new_run(_base_weapons())
	if profile != null:
		profile.save_profile()
	_clear_floor()
	if _guild == null:
		_start_floor()
		return
	_enter_guild()


func _enter_guild() -> void:
	_in_guild = true
	_guild.set_active(true)
	player.position = _guild.spawn_position()
	var cam_manager: Node = _find_camera_limit_manager()
	if cam_manager != null and cam_manager.has_method("frame_rect"):
		cam_manager.frame_rect(player, _guild.camera_rect())


func _base_weapons() -> Array[WeaponData]:
	var profile: ProfileState = _get_profile_state()
	if profile == null:
		var none: Array[WeaponData] = []
		return none
	return profile.owned_weapons


func _on_player_died() -> void:
	if _dead_handling:
		return
	_dead_handling = true
	await get_tree().create_timer(DEATH_RETURN_SECONDS).timeout
	var health := player.get_node_or_null("Health") as HealthComponent
	if health != null:
		health.reset_health()
	_refill_stamina()
	_return_to_guild()
	_dead_handling = false


## Refill stamina to full (ST-reset): called at the top of `_start_floor()`
## for every floor transition; death routing also refills here, so no
## second hook exists and a double call is idempotent.
func _refill_stamina() -> void:
	var stamina := player.get_node_or_null("Stamina") as StaminaComponent
	if stamina != null:
		stamina.reset_full()


func _start_floor() -> void:
	var run_manager: RunManager = _get_run_manager()
	if run_manager == null:
		return

	_refill_stamina()
	_clear_floor()
	run_manager.current_floor += 1

	var generator: DungeonGenerator = DungeonGenerator.new()
	var layout: DungeonGenerator.FloorLayout = generator.generate_floor(
		run_manager.current_floor,
		run_manager.run_seed,
		floor_data
	)
	if layout == null:
		generator.queue_free()
		return
	_current_layout = layout

	# Keep a direct reference: re-resolving via get_node("Dungeon") during
	# this same frame can return the PREVIOUS floor's node, which is still
	# queue_free-pending and would swallow the ExitArea.
	var dungeon := Node2D.new()
	dungeon.name = "Dungeon"
	_dungeon = dungeon
	add_child(dungeon)

	_tilemap = TileMap.new()
	_tilemap.name = "FloorTileMap"
	dungeon.add_child(_tilemap)
	generator._render_layout(layout, _tilemap)
	generator.queue_free()

	# Right after the TileMap: decals and torches draw above the floor, below everything spawned.
	var dressing: Node2D = FloorDressingScript.new()
	dressing.name = "FloorDressing"
	dungeon.add_child(dressing)
	dressing.dress(layout)

	_door_controller = Node.new()
	_door_controller.name = "DoorController"
	_door_controller.set_script(preload("res://scripts/dungeon/door_controller.gd"))
	dungeon.add_child(_door_controller)
	_door_controller.initialize(layout, _tilemap)

	_spawner = Node.new()
	_spawner.name = "Spawner"
	_spawner.set_script(preload("res://scripts/dungeon/spawner.gd"))
	dungeon.add_child(_spawner)

	# Wire signals BEFORE spawn_content: it emits zone_cleared synchronously
	# and may place chests that grant immediately (§44.16).
	_spawner.zone_cleared.connect(_door_controller.on_zone_cleared)
	# PF-1: chest grants flow Spawner -> RunManager (add + auto-equip).
	_spawner.weapon_granted.connect(_on_weapon_granted)
	_spawner.loot_found.connect(_on_loot_found)

	var cam_manager: Node = _find_camera_limit_manager()
	if cam_manager != null and cam_manager.has_method("_on_zone_entered"):
		_door_controller.zone_entered.connect(cam_manager._on_zone_entered)

	_spawner.spawn_content(layout, dungeon)
	_spawn_exit(layout)
	_spawn_player(layout)
	_initialize_camera_limits(layout)


func _on_weapon_granted(data: WeaponData) -> void:
	# PF-1: a granted weapon is added to the run inventory and immediately
	# equipped so the mount/HUD react via weapon_equipped (§3(b)).
	if data == null:
		return
	var run_manager: RunManager = _get_run_manager()
	if run_manager == null:
		return
	var new_index: int = run_manager.add_weapon(data)
	if new_index >= 0:
		run_manager.equip_weapon(new_index)


func _on_loot_found(items: Array[ItemData], gold: int) -> void:
	var run_manager: RunManager = _get_run_manager()
	if run_manager != null:
		run_manager.add_loot(items, gold)


func _find_camera_limit_manager() -> Node:
	# CameraLimitManager is a sibling under World: ../CameraLimitManager
	if get_parent() != null:
		var by_path: Node = get_parent().get_node_or_null("CameraLimitManager")
		if by_path != null:
			return by_path
	# Fallback: search entire tree by script
	return _find_node_by_script(get_tree().root, "res://scripts/dungeon/camera_limit_manager.gd")


func _find_node_by_script(node: Node, script_path: String) -> Node:
	var script: Script = node.get_script() as Script
	if script != null and script.resource_path == script_path:
		return node
	for child in node.get_children():
		var found: Node = _find_node_by_script(child, script_path)
		if found != null:
			return found
	return null


func _initialize_camera_limits(layout: DungeonGenerator.FloorLayout) -> void:
	var cam_manager: Node = _find_camera_limit_manager()
	if cam_manager != null and cam_manager.has_method("initialize"):
		cam_manager.initialize(layout, player)


func _spawn_exit(layout: DungeonGenerator.FloorLayout) -> void:
	var exit_zone: Zone = _first_zone_of_type(layout, Zone.ZoneType.EXIT)
	if exit_zone == null:
		return
	var exit := ExitScene.instantiate() as ExitScript
	exit.position = _zone_center_px(exit_zone)
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


# Atajo de debug (N): salta al siguiente piso; no corre en release.
# Debug-only shortcut (N): skips to the next floor; inactive in release builds.
func _unhandled_input(event: InputEvent) -> void:
	if OS.is_debug_build() and event.is_action_pressed("debug_next_floor"):
		if _in_guild:
			start_expedition()
		else:
			_go_to_next_floor()


func _spawn_player(layout: DungeonGenerator.FloorLayout) -> void:
	var start_zone: Zone = _first_zone_of_type(layout, Zone.ZoneType.START)
	if start_zone == null:
		return
	player.position = _zone_center_px(start_zone)
	var cam_manager: Node = _find_camera_limit_manager()
	if cam_manager != null and cam_manager.has_method("_on_zone_entered"):
		cam_manager._on_zone_entered(start_zone.id)


func _first_zone_of_type(layout: DungeonGenerator.FloorLayout, type: Zone.ZoneType) -> Zone:
	for zone: Zone in layout.zones:
		if zone.type == type:
			return zone
	return null


func _zone_center_px(zone: Zone) -> Vector2:
	return (Vector2(zone.tile_rect.position) + Vector2(zone.tile_rect.size) / 2.0) \
			* DungeonGeometry.TILE_SIZE
