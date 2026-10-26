extends SceneTree

## Run: godot --headless -s scripts/test/assert_room_transition.gd
## Real room-to-room walk through main.tscn (guild first, then expeditions, each with a new seed):
##   1. The player walks with the move actions through every door of START and through one door
##      of each axis, both ways, so every floor crosses right, left, down (north door) and up.
##      Each crossing ends with the walk-in: feet on the target zone's interior floor (no ring,
##      face rows, gap or arch) and the body clear of every wall and door tile.
##   2. Entering an uncleared COMBAT zone locks its doors only once the feet are on that floor
##      (recorded on doors_locked), and the closed tiles never land on the body.
##   3. A crossing back right after a slide starts re-targets the walk-in: the player ends on the
##      floor it came from and the zone it backed out of stays open.
##   4. While in the dungeon the guild's TileMapLayer has no collision (the guild shares the
##      world origin with the dungeon); back in the guild it collides again.
## Enemies and the exit stairs are disabled so nothing pushes the player or changes the floor.
## Exit 0 = pass, 1 = fail.

const Geometry: GDScript = preload("res://scripts/dungeon/dungeon_geometry.gd")
# Expediciones a recorrer (cada una con otra seed) / Expeditions to walk (each with a new seed)
const EXPEDITIONS: int = 4
# Semilla global antes de cada expedición: su seed sale de randi() / Global seed before each expedition: its seed comes from randi()
const TEST_SEED: int = 20261025
# Velocidad del jugador en el test, en px/s (acorta la caminata) / Player speed in the test, in px/s (shortens the walk)
const TEST_SPEED: float = 180.0
# Tope de frames de física por cruce (caminata + deslizamiento) / Physics frame cap per crossing (walk + slide)
const CROSS_FRAMES: int = 300

const ACTION_FOR: Dictionary = {
	Vector2i.RIGHT: "move_right",
	Vector2i.LEFT: "move_left",
	Vector2i.DOWN: "move_down",
	Vector2i.UP: "move_up",
}

var _fails: int = 0
var _player: CharacterBody2D
var _cams: Node
var _doors: Node
var _tilemap: TileMap
# Zonas emitidas por zone_entered desde el último cruce / Zones emitted by zone_entered since the last crossing
var _entered: Array[int] = []
# Un registro por doors_locked: zona, pies en el piso, celdas trabadas bajo el cuerpo
# One record per doors_locked: zone, feet on the floor, locked cells under the body
var _locks: Array[Dictionary] = []
# Cruces y trabas verificados por dirección / Crossings and locks verified per direction
var _crossed: Dictionary = {}
var _locked: Dictionary = {}


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		_fails += 1
		print("VERIFY_FAIL: " + msg)


func _initialize() -> void:
	_run()


func _run() -> void:
	var main: Node = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	main.get_node("ProfileState").set("save_path", "user://test_room_transition.json")
	root.add_child(main)
	for i: int in 10:
		await physics_frame
	var manager: Node = main.get_node("World/DungeonManager")
	_cams = main.get_node("World/CameraLimitManager")
	_player = main.find_child("Player", true, false)
	_player.set("speed", TEST_SPEED)
	var guild_tiles: TileMapLayer = main.get_node("World/Guild/Room/Tiles")
	_check(guild_tiles.collision_enabled, "guild tiles collide while in the guild")
	for dir: Vector2i in ACTION_FOR:
		_crossed[dir] = 0
		_locked[dir] = 0

	for expedition: int in EXPEDITIONS:
		seed(TEST_SEED + expedition)
		manager.call("start_expedition")
		for i: int in 20:
			await physics_frame
		_check(not guild_tiles.collision_enabled, "expedition %d: guild tiles do not collide in the dungeon" % expedition)
		_bind_floor(manager)
		await _walk_floor(manager.get("_current_layout"), expedition)
		manager.call("_return_to_guild")
		for i: int in 10:
			await physics_frame
		_check(guild_tiles.collision_enabled, "expedition %d: guild tiles collide again back in the guild" % expedition)

	for dir: Vector2i in ACTION_FOR:
		_check(_crossed[dir] > 0 and _locked[dir] > 0, "going %s: %d walk-in(s), %d of them into a combat lock on the floor" % [
				ACTION_FOR[dir], _crossed[dir], _locked[dir]])
	main.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_room_transition.json"))
	quit(1 if _fails > 0 else 0)


## Takes this floor's nodes, silences its enemies and exit, and records crossings and locks.
func _bind_floor(manager: Node) -> void:
	_doors = manager.get("_door_controller")
	_tilemap = manager.get("_tilemap")
	var dungeon: Node2D = manager.get("_dungeon")
	for child: Node in dungeon.get_children():
		if child is CharacterBody2D or child.name == "ExitArea":
			child.process_mode = Node.PROCESS_MODE_DISABLED
	_doors.zone_entered.connect(func(zone_id: int) -> void: _entered.append(zone_id))
	_doors.doors_locked.connect(_on_doors_locked)


func _on_doors_locked(zone_id: int) -> void:
	_locks.append({"zone": zone_id, "on_floor": _feet_on_floor(_zone(zone_id)), "under_body": _blocking_under_body()})


func _walk_floor(layout: DungeonGenerator.FloorLayout, expedition: int) -> void:
	var start: Zone = null
	for z: Zone in layout.zones:
		if z.type == Zone.ZoneType.START:
			start = z
	var picks: Array[Zone.Door] = []
	for door: Zone.Door in layout.doors:
		# Las puertas de la bóveda quedan trabadas hasta usar la llave / Vault doors stay shut until the key is used
		if door.key_locked:
			continue
		if door.zone_a_id == start.id or door.zone_b_id == start.id:
			picks.append(door)
	# One more door per axis, into an uncleared COMBAT zone when there is one, so locks get checked.
	for axis: String in ["v", "h"]:
		var pick: Zone.Door = null
		for door: Zone.Door in layout.doors:
			if door.edge_axis != axis or picks.has(door) or door.key_locked:
				continue
			if pick == null or _touches_combat(door):
				pick = door
			if _touches_combat(door):
				break
		if pick != null:
			picks.append(pick)
	var north_door: Zone.Door = null
	for door: Zone.Door in picks:
		# START primero, para salir de donde aparece el jugador / START first, leaving from where the player spawns
		var first: Zone = _zone(door.zone_a_id)
		var second: Zone = _zone(door.zone_b_id)
		if second == start:
			first = second
			second = _zone(door.zone_a_id)
		await _cross(door, first, second, expedition)
		await _cross(door, second, first, expedition)
		if door.edge_axis == "h" and north_door == null:
			north_door = door
	if north_door != null:
		await _cross_and_back(north_door, expedition)


## Walks from the source floor through door into target and checks the walk-in and the lock.
func _cross(door: Zone.Door, source: Zone, target: Zone, expedition: int) -> void:
	var dir: Vector2i = await _stand_before(door, source)
	var label: String = "expedition %d: door %d going %s, zone %d -> %d (%s)" % [
			expedition, door.id, ACTION_FOR[dir], source.id, target.id, Zone.ZoneType.keys()[target.type]]
	var lock_expected: bool = door.combat_locked and target.type == Zone.ZoneType.COMBAT and not target.cleared
	Input.action_press(ACTION_FOR[dir])
	var crossed: bool = false
	for i: int in CROSS_FRAMES:
		await physics_frame
		if _entered.has(target.id) and not _cams.is_sliding():
			crossed = true
			break
	Input.action_release(ACTION_FOR[dir])
	await physics_frame
	var feet_tile: Vector2i = Vector2i((_player.global_position / Geometry.TILE_SIZE).floor())
	_check(crossed, "%s: crossed and the slide ended" % label)
	_check(_feet_on_floor(target), "%s: feet land on the interior floor (tile %s)" % [label, feet_tile])
	var under: Array[Vector2i] = _blocking_under_body()
	_check(under.is_empty(), "%s: body clear of wall and door tiles %s" % [label, under])
	if lock_expected:
		var ok: bool = _locks.size() == 1 and _locks[0]["zone"] == target.id and _locks[0]["on_floor"] \
				and (_locks[0]["under_body"] as Array).is_empty() and door.state == 1
		_check(ok, "%s: doors lock once the feet are on the floor, never on the body %s" % [label, _locks])
		if ok:
			_locked[dir] += 1
		_doors.on_zone_cleared(target.id)
	else:
		_check(_locks.is_empty(), "%s: no lock outside an uncleared COMBAT zone" % label)
	if crossed and _feet_on_floor(target) and under.is_empty():
		_crossed[dir] += 1


## Starts down through a north door and crosses straight back while the slide has just begun:
## the walk-in turns around and ends on the floor it came from, and nothing locks.
func _cross_and_back(door: Zone.Door, expedition: int) -> void:
	var upper: Zone = _zone_on_side(door, -1)
	var lower: Zone = _zone_on_side(door, 1)
	await _stand_before(door, upper)
	var label: String = "expedition %d: door %d down and straight back mid-slide" % [expedition, door.id]
	Input.action_press("move_down")
	for i: int in CROSS_FRAMES:
		await physics_frame
		if _entered.has(lower.id):
			break
	Input.action_release("move_down")
	_check(_cams.is_sliding(), "%s: the first slide is running" % label)
	# The tree is paused, so the door area cannot report it: drive the crossing back by hand.
	_player.velocity = Vector2(0.0, -TEST_SPEED)
	_doors._on_door_body_entered(_player, door, _doors._zones)
	_doors._on_door_body_exited(_player, door, _doors._zones)
	for i: int in CROSS_FRAMES:
		await physics_frame
		if not _cams.is_sliding():
			break
	_check(_entered.back() == upper.id, "%s: the crossing back re-targets the slide" % label)
	_check(_feet_on_floor(upper), "%s: feet back on the upper floor" % label)
	var under: Array[Vector2i] = _blocking_under_body()
	_check(under.is_empty(), "%s: body clear of wall and door tiles %s" % [label, under])
	_check(door.state == 0 and _locks.is_empty(), "%s: the zone backed out of stays open" % label)


## Teleports the player one tile before the door on source's floor, frames the camera there and
## returns the walking direction.
func _stand_before(door: Zone.Door, source: Zone) -> Vector2i:
	var cell: Vector2i = Geometry.door_cell(door)
	# La celda de la puerta es la primera de la zona derecha/de abajo / The door cell is the first
	# cell of the right/lower zone
	var dir: Vector2i = Vector2i.RIGHT if door.edge_axis == "v" else Vector2i.DOWN
	if source.tile_rect.has_point(cell):
		dir = -dir
	var tile: float = float(Geometry.TILE_SIZE)
	var floor_rect: Rect2 = Geometry.floor_interior_px(source.tile_rect)
	var centre: Vector2 = (Vector2(cell) + Vector2(0.5, 0.5)) * tile
	_player.global_position = centre.clamp(floor_rect.position, floor_rect.end) - Vector2(dir) * tile
	_player.velocity = Vector2.ZERO
	_cams.call("_on_zone_entered", source.id)
	for i: int in CROSS_FRAMES:
		await physics_frame
		if not _cams.is_sliding():
			break
	_entered.clear()
	_locks.clear()
	return dir


## Feet tile inside the zone, past its wall ring and north face (so not on a gap, arch or passage).
func _feet_on_floor(zone: Zone) -> bool:
	var local: Vector2i = Vector2i((_player.global_position / Geometry.TILE_SIZE).floor()) - zone.tile_rect.position
	var ring: int = Geometry.WALL_RING_TILES
	return local.x >= ring and local.x < zone.tile_rect.size.x - ring \
			and local.y >= ring + Geometry.NORTH_FACE_ROWS and local.y < zone.tile_rect.size.y - ring


## Cells under the body's collision rect holding a closed door or a wall with collision.
func _blocking_under_body() -> Array[Vector2i]:
	var shape_node: CollisionShape2D = _player.get_node("CollisionShape2D")
	var size: Vector2 = (shape_node.shape as RectangleShape2D).size
	var body: Rect2 = Rect2(_player.global_position + shape_node.position - size / 2.0, size)
	var tile: float = float(Geometry.TILE_SIZE)
	var first: Vector2i = Vector2i((body.position / tile).floor())
	var last: Vector2i = Vector2i(((body.end - Vector2.ONE * 0.01) / tile).floor())
	var hits: Array[Vector2i] = []
	for y: int in range(first.y, last.y + 1):
		for x: int in range(first.x, last.x + 1):
			var cell: Vector2i = Vector2i(x, y)
			var wall: TileData = _tilemap.get_cell_tile_data(Geometry.LAYER_WALL, cell)
			if _tilemap.get_cell_source_id(Geometry.LAYER_DOOR, cell) != -1 \
					or (wall != null and wall.get_collision_polygons_count(0) > 0):
				hits.append(cell)
	return hits


func _touches_combat(door: Zone.Door) -> bool:
	return _zone(door.zone_a_id).type == Zone.ZoneType.COMBAT or _zone(door.zone_b_id).type == Zone.ZoneType.COMBAT


func _zone(zone_id: int) -> Zone:
	return _doors._zones[zone_id]


func _zone_on_side(door: Zone.Door, side: int) -> Zone:
	return _doors._zone_on_side(_doors._zones, door, side)
