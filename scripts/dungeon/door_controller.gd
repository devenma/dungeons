extends Node

## Door crossing detection for zone transitions (two-phase model):
##
##   1. body_entered + direction -> record the SOURCE side (the zone the player
##      came from). Nothing is emitted yet.
##   2. body_exited + movement direction -> determine the TARGET side. The
##      transition is applied only when the player is fully through the door,
##      and only when target != source (walking in and backing out is not a
##      crossing).
##
## Sides are resolved against the door's geometric edge line:
##   axis "v": line at x = edge_line * TILE_SIZE (left zone ends, right zone starts)
##   axis "h": line at y = edge_line * TILE_SIZE (top zone ends, bottom zone starts)

signal zone_entered(zone_id: int)

const TILE_SIZE := DungeonGeometry.TILE_SIZE

var _doors: Array = []        # of Zone.Door
var _tilemap: TileMap
var _door_src_id: int = -1    # door tile source (needed to re-place tiles on lock)
var _zone_doors: Dictionary = {}  # zone_id -> Array[Zone.Door]
var _zones: Dictionary = {}   # zone_id -> Zone
var _pending_crossings: Dictionary = {}  # door.id -> source_zone_id (single player)


func initialize(layout, tilemap: TileMap, door_src_id: int) -> void:
	_tilemap = tilemap
	_door_src_id = door_src_id
	_doors = layout.doors
	for z in layout.zones:
		_zones[z.id] = z

	# Build zone -> doors lookup
	for d in _doors:
		var door: Zone.Door = d
		if not _zone_doors.has(door.zone_a_id):
			_zone_doors[door.zone_a_id] = []
		if not _zone_doors.has(door.zone_b_id):
			_zone_doors[door.zone_b_id] = []
		_zone_doors[door.zone_a_id].append(d)
		_zone_doors[door.zone_b_id].append(d)

	# Create invisible Area2D per door for crossing detection
	_create_door_areas(layout)


func _create_door_areas(_layout) -> void:
	for d in _doors:
		var door: Zone.Door = d
		var area := Area2D.new()
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		# The door spans the punched corridor: the full depth of both wall
		# rings plus one tile of margin past each end so a combat lock placed
		# at exit time is never laid over the player body.
		var depth_px: float = (DungeonGeometry.DOOR_CORRIDOR_DEPTH_TILES + 2) * TILE_SIZE
		if door.edge_axis == "v":
			rect.size = Vector2(depth_px, DungeonGeometry.DOOR_GAP_TILES * TILE_SIZE)
		else:
			rect.size = Vector2(DungeonGeometry.DOOR_GAP_TILES * TILE_SIZE, depth_px)
		shape.shape = rect
		area.add_child(shape)

		# Position at door tile center (in pixels)
		var tile_pos: Vector2i
		if door.edge_axis == "v":
			tile_pos = Vector2i(door.edge_line, door.pos_along)
		else:
			tile_pos = Vector2i(door.pos_along, door.edge_line)

		# Area2D world position = tile center in pixels
		area.position = Vector2(
			tile_pos.x * TILE_SIZE + TILE_SIZE / 2.0,
			tile_pos.y * TILE_SIZE + TILE_SIZE / 2.0
		)

		area.name = "DoorArea_%d" % door.id
		# Detect only the player body (layer 2 after the Fase 4 flip).
		area.collision_layer = CollisionLayers.WORLD
		area.collision_mask = CollisionLayers.PLAYER_BODY
		add_child(area)

		# Connect crossing detection: entry records the source side,
		# exit + movement direction applies the transition.
		area.body_entered.connect(_on_door_body_entered.bind(door, _zones))
		area.body_exited.connect(_on_door_body_exited.bind(door, _zones))


func _on_door_body_entered(body: Node2D, door: Zone.Door,
		zone_by_id: Dictionary) -> void:
	if not (body is CharacterBody2D):
		return
	var player: CharacterBody2D = body

	# Entry + direction: record which side the player came FROM.
	# The position side is deterministic at entry; fall back to the opposite of
	# the movement direction if the player entered exactly on the boundary line.
	var entry_side: int = _side_of_line(door, player.position)
	if entry_side == 0:
		entry_side = -_dir_side(door, player.velocity)
	if entry_side == 0:
		return

	var source_zone: Zone = _zone_on_side(zone_by_id, door, entry_side)
	if source_zone == null:
		return
	_pending_crossings[door.id] = source_zone.id


func _on_door_body_exited(body: Node2D, door: Zone.Door,
		zone_by_id: Dictionary) -> void:
	if not (body is CharacterBody2D):
		return
	if not _pending_crossings.has(door.id):
		return
	var player: CharacterBody2D = body
	var source_id: int = _pending_crossings[door.id]
	_pending_crossings.erase(door.id)

	var z_a: Zone = zone_by_id.get(door.zone_a_id)
	var z_b: Zone = zone_by_id.get(door.zone_b_id)
	if z_a == null or z_b == null:
		return

	# Exit + movement direction: the zone the player ends up in is the one on
	# the side they leave toward. Fall back to the position side when velocity
	# is ~0 (player stopped inside the door area).
	var exit_side: int = _dir_side(door, player.velocity)
	if exit_side == 0:
		exit_side = _side_of_line(door, player.position)
	if exit_side == 0:
		return

	var target_zone: Zone = _zone_on_side(zone_by_id, door, exit_side)
	if target_zone == null:
		return
	if target_zone.id == source_id:
		# Walked in and backed out of the same side — not a crossing.
		return

	zone_entered.emit(target_zone.id)

	# Combat lock: entering an uncleared COMBAT zone seals its doors until the
	# zone is cleared. The lock is placed behind the player — the door areas
	# cover the full corridor plus one tile of margin, so at exit time the
	# body is past the whole wall ring and the placed tiles never overlap it.
	if target_zone.type == Zone.ZoneType.COMBAT and not target_zone.cleared:
		_lock_zone_doors(target_zone.id)


func _side_of_line(door: Zone.Door, pos: Vector2) -> int:
	# +1 = right of the edge line (axis "v") / below it (axis "h")
	# -1 = left of the edge line (axis "v") / above it (axis "h")
	#  0 = exactly on the line
	if door.edge_axis == "v":
		var line_x: float = door.edge_line * TILE_SIZE
		if pos.x > line_x:
			return 1
		if pos.x < line_x:
			return -1
		return 0
	var line_y: float = door.edge_line * TILE_SIZE
	if pos.y > line_y:
		return 1
	if pos.y < line_y:
		return -1
	return 0


func _dir_side(door: Zone.Door, velocity: Vector2) -> int:
	# Side implied by the movement direction; 0 when ~stationary or moving
	# parallel to the door edge.
	if velocity.length_squared() < 0.0001:
		return 0
	if door.edge_axis == "v":
		if velocity.x > 0.0:
			return 1
		if velocity.x < 0.0:
			return -1
		return 0
	if velocity.y > 0.0:
		return 1
	if velocity.y < 0.0:
		return -1
	return 0


func _zone_on_side(zone_by_id: Dictionary, door: Zone.Door, side: int) -> Zone:
	# Map a door side to the zone occupying that side of the edge line.
	var z_a: Zone = zone_by_id.get(door.zone_a_id)
	var z_b: Zone = zone_by_id.get(door.zone_b_id)
	var candidates: Array = [z_a, z_b]
	for c in candidates:
		var z: Zone = c
		if z == null:
			continue
		if door.edge_axis == "v":
			if side > 0 and z.tile_rect.position.x >= door.edge_line:
				return z
			if side < 0 and z.tile_rect.end.x <= door.edge_line:
				return z
		else:
			if side > 0 and z.tile_rect.position.y >= door.edge_line:
				return z
			if side < 0 and z.tile_rect.end.y <= door.edge_line:
				return z
	return null


func _lock_zone_doors(zone_id: int) -> void:
	# Seal every open combat-locked door of the zone (player just entered it).
	if not _zone_doors.has(zone_id):
		return
	for door in _zone_doors[zone_id]:
		var d: Zone.Door = door
		if not d.combat_locked or d.state != 0:
			continue
		d.state = 1  # CLOSED
		_place_door_tiles(d)


func _place_door_tiles(door: Zone.Door) -> void:
	# Place door tiles across the whole punched corridor — the full depth of
	# BOTH zone wall rings (mirrors the generator's punch and on_zone_cleared's
	# erase). Closed door = dark fill alternative, blocking via tile collision.
	var tile_pos: Vector2i
	if door.edge_axis == "v":
		tile_pos = Vector2i(door.edge_line, door.pos_along)
	else:
		tile_pos = Vector2i(door.pos_along, door.edge_line)
	for cell in _corridor_cells(door):
		_tilemap.set_cell(2, cell, DungeonGeometry.FLOOR_SOURCE_ID,
				DungeonGeometry.DOOR_FILL_ATLAS, DungeonGeometry.DOOR_CLOSED_ALT)


func _corridor_cells(door: Zone.Door) -> Array[Vector2i]:
	# The punched corridor: offsets -ring..ring-1 cross-axis from the edge
	# line (2 * WALL_RING_TILES = DOOR_CORRIDOR_DEPTH_TILES) across the
	# DOOR_GAP_TILES row/tile centered on pos_along. Identical derivation in
	# the generator (_punch_doors) and here.
	var tile_pos: Vector2i
	if door.edge_axis == "v":
		tile_pos = Vector2i(door.edge_line, door.pos_along)
	else:
		tile_pos = Vector2i(door.pos_along, door.edge_line)
	var ring := DungeonGeometry.DOOR_CORRIDOR_DEPTH_TILES
	var gap: int = DungeonGeometry.DOOR_GAP_TILES
	var half_gap: int = gap / 2
	var cells: Array[Vector2i] = []
	for dz in range(-ring, ring):
		for g in range(-half_gap, half_gap + 1):
			if door.edge_axis == "v":
				cells.append(Vector2i(tile_pos.x + dz, tile_pos.y + g))
			else:
				cells.append(Vector2i(tile_pos.x + g, tile_pos.y + dz))
	return cells


func on_zone_cleared(zone_id: int) -> void:
	if not _zone_doors.has(zone_id):
		return

	for door in _zone_doors[zone_id]:
		var d: Zone.Door = door
		if not d.combat_locked:
			continue
		# Only open if the OTHER side is also cleared (or not combat)
		# For now: open ALL combat_locked doors touching this zone
		d.state = 0  # OPEN

		# Remove door tiles from layer 2 — the whole punched corridor,
		# matching the tiles placed when the door was closed.
		for cell in _corridor_cells(d):
			_tilemap.erase_cell(2, cell)
