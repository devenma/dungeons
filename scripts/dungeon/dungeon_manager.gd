extends Node

## Floor orchestration (§24) plus the guild <-> expedition transition:
## boots in the guild, `start_expedition()` builds floor 1, and death
## routes through `_return_to_guild()` (D1 + blue stone rule). While the
## death is being handled no exit or floor change goes through.
## Optional sound children (absent in test rigs): DungeonAmbience loops on
## the floors, DoorLockSound / DoorOpenSound follow the combat locks and
## TeleportSound plays when a blue stone saves the loot.

## Ya en el gremio tras morir; true = se gastó una piedra azul y se conservó el botín
## Back in the guild after dying; true = a blue stone was spent and the loot kept
signal returned_from_death(blue_stone_used: bool)
## Empezó un piso (0 = en el gremio) de floor_count / A floor started (0 = in the guild) out of floor_count
signal floor_started(floor_number: int, floor_count: int)

# Referenced by preloaded script instead of a class_name, which is not
# registered in headless runs without an editor scan.
const ExitScene: PackedScene = preload("res://scenes/dungeon/exit.tscn")
const ExitScript: GDScript = preload("res://scripts/dungeon/exit_area.gd")
const FloorDressingScript: GDScript = preload("res://scripts/dungeon/floor_dressing.gd")
const KeyDoorScript: GDScript = preload("res://scripts/dungeon/key_door.gd")
## Llave de la bóveda (D3) / Vault key (D3)
const KEY_ITEM: ItemData = preload("res://resources/items/llave_osario.tres")
# Espera entre la muerte y la vuelta al gremio (s) / Delay between death and the return to the guild (s)
const DEATH_RETURN_SECONDS: float = 0.5
# Parte de la vida máxima que se lleva cada ofrenda de carne (D23) / Share of max health each flesh offering takes (D23)
const FLESH_FRACTION: float = 0.2

@export var player_node_path: NodePath
@export var run_manager_node_path: NodePath
## Perfil persistente; vacío = sin perfil (rigs de test) / Persistent profile; empty = none (test rigs)
@export var profile_state_node_path: NodePath
## Gremio de partida y de vuelta; vacío = arranca directo en un piso / Start and return guild; empty = boot straight into a floor
@export var guild_node_path: NodePath
## Parámetros de generación sin dungeon_data; null = valores por defecto / Generation parameters without dungeon_data; null = defaults
@export var floor_data: FloorData
## Dungeon de la expedición: pisos, techo y jefe; null = pisos sin techo con floor_data (rigs de test)
## Expedition dungeon: floors, ceiling and boss; null = ceiling-less floors with floor_data (test rigs)
@export var dungeon_data: DungeonData

@onready var player: Node2D = get_node(player_node_path)

var _current_layout: DungeonGenerator.FloorLayout
var _dead_handling: bool = false
var _guild: Node2D
var _in_guild: bool = false

# Máximos del jugador sin mejoras ni ofrendas (los de player.tscn) / Player maxima without upgrades or offerings (player.tscn's)
var _base_max_health: int = 100
var _base_max_stamina: int = 100

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
		_base_max_health = health.max_health
	var stamina := player.get_node_or_null("Stamina") as StaminaComponent
	if stamina != null:
		_base_max_stamina = stamina.max_stamina
	var profile: ProfileState = _get_profile_state()
	if profile != null:
		profile.profile_changed.connect(_apply_player_stats)
	var run_manager: RunManager = _get_run_manager()
	if run_manager != null:
		run_manager.stats_changed.connect(_apply_player_stats)
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
	# Del gremio se sale curado, también lo que sumó una mejora recién comprada / You leave the guild healed, including what a freshly bought upgrade added
	var health := player.get_node_or_null("Health") as HealthComponent
	if health != null:
		health.heal_full()
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
	var blue_stone_used: bool = run_manager != null and run_manager.consume_blue_stone()
	if blue_stone_used:
		_play_sound("TeleportSound")
	_go_home(blue_stone_used)
	returned_from_death.emit(blue_stone_used)


## Escalera del Farol (D22): vuelve con todo, sin gastar piedra, y marca el dungeon como limpio.
## Lantern Stair (D22): returns with everything, no stone spent, and marks the dungeon as cleared.
func _return_victorious() -> void:
	if _dead_handling:
		return
	var profile: ProfileState = _get_profile_state()
	if profile != null and dungeon_data != null:
		profile.mark_cleared(dungeon_data.id)
	_play_sound("TeleportSound")
	_go_home(true)


## keep_loot conserva la mochila y asegura en el perfil las armas recogidas; si no, se pierde todo lo de
## la expedición. La seed se re-rollea siempre y el jugador vuelve curado.
## keep_loot keeps the backpack and secures the picked-up weapons in the profile; otherwise the whole
## expedition is lost. The seed is always re-rolled and the player comes back healed.
func _go_home(keep_loot: bool) -> void:
	var run_manager: RunManager = _get_run_manager()
	var profile: ProfileState = _get_profile_state()
	if run_manager != null:
		if not keep_loot:
			run_manager.lose_backpack()
		elif profile != null:
			profile.owned_weapons = run_manager.owned_weapons.duplicate()
		run_manager.start_new_run(_base_weapons())
	if profile != null:
		profile.advance_day()
		profile.save_profile()
	var health := player.get_node_or_null("Health") as HealthComponent
	if health != null:
		health.reset_health()
	_refill_stamina()
	_clear_floor()
	if _guild == null:
		_start_floor()
	else:
		_enter_guild()


## Máximos del jugador: base + mejoras del perfil (D11), menos un 20 % de vida por ofrenda de carne (D23).
## Player maxima: base + profile upgrades (D11), minus 20% health per flesh offering (D23).
func _apply_player_stats() -> void:
	var profile: ProfileState = _get_profile_state()
	var run_manager: RunManager = _get_run_manager()
	var health_bonus: int = profile.stat_bonus(UpgradeData.Stat.MAX_HEALTH) if profile != null else 0
	var stamina_bonus: int = profile.stat_bonus(UpgradeData.Stat.MAX_STAMINA) if profile != null else 0
	var offerings: int = run_manager.flesh_offerings if run_manager != null else 0
	var health := player.get_node_or_null("Health") as HealthComponent
	if health != null:
		health.set_max_health(roundi((_base_max_health + health_bonus) * (1.0 - FLESH_FRACTION * offerings)))
	var stamina := player.get_node_or_null("Stamina") as StaminaComponent
	if stamina != null:
		stamina.set_max_stamina(_base_max_stamina + stamina_bonus)


func _play_sound(sound_name: String) -> void:
	var sound: AudioStreamPlayer = get_node_or_null(sound_name) as AudioStreamPlayer
	if sound != null:
		sound.play()


func _enter_guild() -> void:
	_in_guild = true
	var ambience: AudioStreamPlayer = get_node_or_null("DungeonAmbience") as AudioStreamPlayer
	if ambience != null:
		ambience.stop()
	_guild.set_active(true)
	floor_started.emit(0, _floor_count())
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
	_return_to_guild()
	_dead_handling = false


## Refill stamina and mana to full (ST-reset, D19): called at the top of `_start_floor()`
## for every floor transition; death routing also refills here, so no
## second hook exists and a double call is idempotent.
func _refill_stamina() -> void:
	for pool_name: String in ["Stamina", "Mana"]:
		var pool := player.get_node_or_null(pool_name) as StaminaComponent
		if pool != null:
			pool.reset_full()


func _start_floor() -> void:
	var run_manager: RunManager = _get_run_manager()
	if run_manager == null:
		return

	_refill_stamina()
	_clear_floor()
	run_manager.current_floor += 1
	var ambience: AudioStreamPlayer = get_node_or_null("DungeonAmbience") as AudioStreamPlayer
	if ambience != null and not ambience.playing:
		ambience.play()

	var data: FloorData = _current_floor_data()
	var generator: DungeonGenerator = DungeonGenerator.new()
	var layout: DungeonGenerator.FloorLayout = generator.generate_floor(
		run_manager.current_floor,
		run_manager.run_seed,
		data
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
	_spawner.floor_data = data
	if dungeon_data != null:
		_spawner.boss_scene = dungeon_data.boss_scene

	# Wire signals BEFORE spawn_content: it emits zone_cleared synchronously
	# and may place chests that grant immediately (§44.16).
	_spawner.zone_cleared.connect(_door_controller.on_zone_cleared)
	_door_controller.doors_locked.connect(func(_zone_id: int) -> void: _play_sound("DoorLockSound"))
	_door_controller.doors_opened.connect(func(_zone_id: int) -> void: _play_sound("DoorOpenSound"))
	# PF-1: chest grants flow Spawner -> RunManager (add + auto-equip).
	_spawner.weapon_granted.connect(_on_weapon_granted)
	_spawner.loot_found.connect(_on_loot_found)
	_spawner.boss_defeated.connect(_on_boss_defeated)

	var cam_manager: Node = _find_camera_limit_manager()
	if cam_manager != null and cam_manager.has_method("_on_zone_entered"):
		_door_controller.zone_entered.connect(cam_manager._on_zone_entered)

	_spawner.spawn_content(layout, dungeon)
	_spawn_exit(layout)
	_spawn_key_doors(layout)
	_spawn_player(layout)
	_initialize_camera_limits(layout)
	floor_started.emit(run_manager.current_floor, _floor_count())


func _current_floor_data() -> FloorData:
	var run_manager: RunManager = _get_run_manager()
	if dungeon_data == null or dungeon_data.floors.is_empty() or run_manager == null:
		return floor_data
	return dungeon_data.floor_data(run_manager.current_floor)


## Pisos del dungeon; 0 = sin techo / Dungeon floors; 0 = no ceiling
func _floor_count() -> int:
	return dungeon_data.floors.size() if dungeon_data != null else 0


## La primera vez da el trofeo; después aparece la Escalera del Farol donde estaba la pila (D21-D22).
## The first time grants the trophy; then the Lantern Stair appears where the pile was (D21-D22).
func _on_boss_defeated(at: Vector2) -> void:
	var profile: ProfileState = _get_profile_state()
	var run_manager: RunManager = _get_run_manager()
	if dungeon_data != null and dungeon_data.first_clear_trophy != null and run_manager != null \
			and (profile == null or not profile.has_cleared(dungeon_data.id)):
		var trophy: Array[ItemData] = [dungeon_data.first_clear_trophy]
		run_manager.add_loot(trophy, 0)
	var pile: Vector2i = Vector2i((at / DungeonGeometry.TILE_SIZE).floor())
	var stairs: Vector2i = pile - Vector2i(1, DungeonGeometry.STAIRS_DOWN_SIZE.y)
	DungeonGenerator.paint_stairs(_tilemap, stairs)
	var exit := ExitScene.instantiate() as ExitScript
	exit.position = DungeonGeometry.stairs_exit_rect(stairs).get_center()
	# Connect BEFORE add_child (§44.16).
	exit.exit_requested.connect(_return_victorious)
	_dungeon.add_child(exit)


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


## Un área de `interact` sobre cada puerta trabada con llave (D3); una puerta norte se alcanza desde el
## piso de la zona de abajo, pasando el arco.
## An `interact` area over each key-locked door (D3); a north door is reached from the floor of the zone
## below, past the arch.
func _spawn_key_doors(layout: DungeonGenerator.FloorLayout) -> void:
	var tile: float = DungeonGeometry.TILE_SIZE
	for d in layout.doors:
		var door: Zone.Door = d
		if not door.key_locked:
			continue
		var area: Area2D = KeyDoorScript.new() as Area2D
		area.set("door_id", door.id)
		var shape: CollisionShape2D = CollisionShape2D.new()
		var rect: RectangleShape2D = RectangleShape2D.new()
		var cell: Vector2 = Vector2(DungeonGeometry.door_cell(door)) * tile
		if door.edge_axis == "v":
			rect.size = Vector2(4.0, 2.0) * tile
			area.position = cell + Vector2(0.0, tile / 2.0)
		else:
			rect.size = Vector2(3.0, 5.0) * tile
			area.position = cell + Vector2(tile / 2.0, tile * 1.5)
		shape.shape = rect
		area.add_child(shape)
		area.connect("unlock_requested", _on_unlock_requested.bind(area))
		_dungeon.add_child(area)


func _on_unlock_requested(door_id: int, _area: Node) -> void:
	var run_manager: RunManager = _get_run_manager()
	if run_manager != null and run_manager.backpack.count_of(KEY_ITEM) > 0 and _door_controller.unlock(door_id):
		run_manager.backpack.remove(KEY_ITEM, 1)
		# Una llave abre todas las puertas de la bóveda / One key opens every vault door
		for other: Node in _dungeon.get_children():
			if other.has_signal("unlock_requested"):
				other.queue_free()
		return
	_play_sound("DoorLockSound")


func _spawn_exit(layout: DungeonGenerator.FloorLayout) -> void:
	var exit_zone: Zone = _first_zone_of_type(layout, Zone.ZoneType.EXIT)
	if exit_zone == null:
		return
	var exit := ExitScene.instantiate() as ExitScript
	# El área de la escena mide stairs_exit_rect; se centra ahí / The scene's area is stairs_exit_rect in size; centred on it
	exit.position = DungeonGeometry.stairs_exit_rect(layout.exit_stairs).get_center()
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


# Muerto no se cambia de piso: la muerte ya vuelve al gremio / Dead there is no floor change: death already returns to the guild
func _go_to_next_floor() -> void:
	if _dead_handling:
		return
	_start_floor()


# Atajo de debug (N): salta al siguiente piso; en el último lleva a la antesala del jefe. No corre en release.
# Debug-only shortcut (N): skips to the next floor; on the last one it goes to the boss antechamber. Inactive in release builds.
func _unhandled_input(event: InputEvent) -> void:
	if OS.is_debug_build() and event.is_action_pressed("debug_next_floor"):
		if _in_guild:
			start_expedition()
		elif _current_layout != null and _current_layout.antechamber_zone_id >= 0:
			_go_to_antechamber()
		else:
			_go_to_next_floor()


func _go_to_antechamber() -> void:
	for zone: Zone in _current_layout.zones:
		if zone.id == _current_layout.antechamber_zone_id:
			player.position = _zone_center_px(zone)
			var cam_manager: Node = _find_camera_limit_manager()
			if cam_manager != null and cam_manager.has_method("_on_zone_entered"):
				cam_manager._on_zone_entered(zone.id)


func _spawn_player(layout: DungeonGenerator.FloorLayout) -> void:
	var start_zone: Zone = _first_zone_of_type(layout, Zone.ZoneType.START)
	if start_zone == null:
		return
	# The camera snaps to START in _initialize_camera_limits, with this floor's layout.
	player.position = _zone_center_px(start_zone)


func _first_zone_of_type(layout: DungeonGenerator.FloorLayout, type: Zone.ZoneType) -> Zone:
	for zone: Zone in layout.zones:
		if zone.type == type:
			return zone
	return null


func _zone_center_px(zone: Zone) -> Vector2:
	return (Vector2(zone.tile_rect.position) + Vector2(zone.tile_rect.size) / 2.0) \
			* DungeonGeometry.TILE_SIZE
