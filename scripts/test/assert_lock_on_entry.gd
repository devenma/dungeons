extends SceneTree

# Runtime assertions for combat-zone door locking:
#   1. Doors start OPEN at floor start (no START-zone deadlock).
#   2. Entering an uncleared COMBAT zone locks its doors.
#   3. Clearing the zone re-opens its doors (no leftover door tiles).
#   4. Re-entering a cleared zone does NOT re-lock.
#   5. Real render sanity (Phase 3/4, prebuilt-tileset): generate_floor on a
#      fixed seed renders tiles from the prebuilt .tres — wall cells use
#      source 0, fill uses source 1, closed combat doors place the dark fill
#      alternative on layer 2 across EXACTLY the punched corridor (full depth,
#      2 tiles — shared formula) and layer 2 is empty again on zone clear.
#      Phase 6 review: _corridor_cells iterated range(-DEPTH, DEPTH) and
#      painted 4 tiles (2 over unpunched cells outside the corridor); the
#      exact set-equality checks below pin the closed tiles to the corridor.
# Run: godot --headless -s scripts/test/assert_lock_on_entry.gd

var _fails: int = 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		_fails += 1
		print("VERIFY_FAIL: " + msg)


## Order-independent set equality for tile-coordinate arrays.
func _same_cell_set(a: Array[Vector2i], b: Array[Vector2i]) -> bool:
	if a.size() != b.size():
		return false
	for cell in a:
		if not b.has(cell):
			return false
	return true


func _init() -> void:
	var gen: Node = load("res://scripts/dungeon/dungeon_generator.gd").new()

	# ── Layout: START (left) ─ COMBAT (right), one door on the shared v-edge ──
	var cell: int = DungeonGeometry.CELL_TILES
	var z0: Zone = Zone.new()
	z0.id = 0
	z0.type = Zone.ZoneType.START
	z0.cell_min = Vector2i(0, 0)
	z0.cell_max = Vector2i(1, 1)
	z0.tile_rect = Rect2i(0, 0, cell, cell)
	z0.neighbors.append(1)

	var z1: Zone = Zone.new()
	z1.id = 1
	z1.type = Zone.ZoneType.COMBAT
	z1.cell_min = Vector2i(1, 0)
	z1.cell_max = Vector2i(2, 1)
	z1.tile_rect = Rect2i(cell, 0, cell, cell)
	z1.neighbors.append(0)

	var door: Zone.Door = Zone.Door.new()
	door.id = 0
	door.zone_a_id = 0
	door.zone_b_id = 1
	door.edge_axis = "v"
	door.edge_line = cell      # first column of the right zone
	door.pos_along = cell / 2  # middle of the shared span
	door.state = 0             # doors start OPEN
	door.combat_locked = true
	z0.doors.append(door)
	z1.doors.append(door)

	var layout: DungeonGenerator.FloorLayout = DungeonGenerator.FloorLayout.new()
	layout.grid_w = 2
	layout.grid_h = 1
	layout.zones = [z0, z1]
	layout.doors = [door]

	# ── Real render + real door controller ──
	var tilemap := TileMap.new()
	gen._render_layout(layout, tilemap)

	var dc: Node = load("res://scripts/dungeon/door_controller.gd").new()
	dc.initialize(layout, tilemap)

	# The corridor is the full punched depth: DOOR_CORRIDOR_DEPTH_TILES tiles
	# (2 * WALL_RING_TILES) starting R tiles before the edge line — the same
	# shared derivation as the generator's _punch_doors and the controller's
	# _corridor_cells (offsets -R..R-1 from the edge line).
	var corridor_tiles: Array[Vector2i] = []
	var ring: int = DungeonGeometry.WALL_RING_TILES
	for i in DungeonGeometry.DOOR_CORRIDOR_DEPTH_TILES:
		corridor_tiles.append(Vector2i(cell - ring + i, cell / 2))

	# ── Check 1: floor starts with doors OPEN (START-zone deadlock fix) ──
	_check(door.state == 0, "door state is OPEN at floor start")
	_check(tilemap.get_cell_source_id(0, Vector2i(cell - 1, cell / 2))
			== DungeonGeometry.FLOOR_SOURCE_ID,
			"corridor shows floor on layer 0 after being punched open")
	for t in corridor_tiles:
		_check(tilemap.get_cell_source_id(2, t) == -1,
				"corridor tile %s empty at floor start (door passable)" % str(t))

	# ── Check 2: entering the combat zone locks its doors ──
	var entered: Array = []  # Array (reference type) so the lambda capture works
	dc.zone_entered.connect(func(zid: int) -> void: entered.append(zid))

	var player := CharacterBody2D.new()
	# Entry: player approaching from the left side of the door line
	player.position = Vector2(cell * DungeonGeometry.TILE_SIZE - 24,
			(cell / 2) * DungeonGeometry.TILE_SIZE + 8)
	player.velocity = Vector2(100, 0)
	dc._on_door_body_entered(player, door, dc._zones)
	# Exit: player fully past the line, moving right
	player.position = Vector2(cell * DungeonGeometry.TILE_SIZE + 40,
			(cell / 2) * DungeonGeometry.TILE_SIZE + 8)
	dc._on_door_body_exited(player, door, dc._zones)

	_check(entered.size() == 1 and entered[0] == 1,
			"zone_entered emitted exactly once for combat zone 1")
	_check(door.state == 1, "door CLOSED after entering combat zone")
	var door_closed_ok := true
	for t in corridor_tiles:
		if tilemap.get_cell_source_id(2, t) != DungeonGeometry.FLOOR_SOURCE_ID \
				or tilemap.get_cell_atlas_coords(2, t) != DungeonGeometry.DOOR_FILL_ATLAS \
				or tilemap.get_cell_alternative_tile(2, t) != DungeonGeometry.DOOR_CLOSED_ALT:
			door_closed_ok = false
	_check(door_closed_ok,
			"corridor tiles show the dark closed-door fill alternative after lock")
	# Exactness: with exactly one door in this layout, layer 2 must hold the
	# corridor's tiles and NOTHING else (guards against overpaint outside the
	# punched corridor).
	_check(_same_cell_set(tilemap.get_used_cells(2), corridor_tiles),
			"layer 2 holds EXACTLY the corridor's closed tiles (no extras)")

	# ── Check 3: clearing the zone re-opens the doors ──
	dc.on_zone_cleared(1)
	_check(door.state == 0, "door OPEN after zone cleared")
	for t in corridor_tiles:
		_check(tilemap.get_cell_source_id(2, t) == -1,
				"corridor tile %s erased after zone cleared" % str(t))
	_check(tilemap.get_used_cells(2).is_empty(),
			"layer 2 is globally empty after the zone cleared")

	# ── Check 4: re-entering a cleared zone does NOT re-lock ──
	z1.cleared = true
	player.position = Vector2(cell * DungeonGeometry.TILE_SIZE - 24,
			(cell / 2) * DungeonGeometry.TILE_SIZE + 8)
	dc._on_door_body_entered(player, door, dc._zones)
	player.position = Vector2(cell * DungeonGeometry.TILE_SIZE + 40,
			(cell / 2) * DungeonGeometry.TILE_SIZE + 8)
	dc._on_door_body_exited(player, door, dc._zones)
	_check(door.state == 0, "cleared zone does not re-lock on re-entry")
	_check(entered.size() == 2 and entered[1] == 1,
			"zone_entered still emitted on re-entry of cleared zone")

	player.free()
	dc.free()
	tilemap.free()

	# ── Check 5: real generate_floor render sanity (deterministic seed) ──
	var data: FloorData = FloorData.new()
	var real_layout: DungeonGenerator.FloorLayout = gen.generate_floor(1, 987654, data)
	var real_map := TileMap.new()
	gen._render_layout(real_layout, real_map)

	_check(real_layout.zones.size() >= 3, "real floor generates its zone count")
	_check(real_map.get_used_cells(0).size() > 0, "real render produces tiles")

	var walls_ok := true
	var fill_ok := true
	for z in real_layout.zones:
		var zone: Zone = z
		var origin: Vector2i = zone.tile_rect.position
		var size: Vector2i = zone.tile_rect.size
		for ty in size.y:
			for tx in size.x:
				var pos: Vector2i = origin + Vector2i(tx, ty)
				if DungeonGeometry.tile_edge_depth(tx, ty, size.x, size.y) == 0:
					# wall band cells: either wall tile (source 0) or erased
					# by a punched door corridor (source -1), never fill.
					var ws: int = real_map.get_cell_source_id(1, pos)
					if ws != DungeonGeometry.WALL_SOURCE_ID and ws != -1:
						walls_ok = false
				var fs: int = real_map.get_cell_source_id(0, pos)
				# layer-0: fill everywhere except unpunched trim-ring cells
				# (corners: wall-sheet baseboard, straight edges: the
				# synthesized edge source). Punched corridors are plain fill.
				if fs != DungeonGeometry.FLOOR_SOURCE_ID:
					var depth1: int = DungeonGeometry.tile_edge_depth(
							tx, ty, size.x, size.y)
					if not (depth1 == 1 and (fs == DungeonGeometry.WALL_SOURCE_ID \
							or fs == DungeonGeometry.EDGE_SOURCE_ID)):
						fill_ok = false
	_check(walls_ok, "real render: wall band uses the wall source (id 0)")
	_check(fill_ok, "real render: every zone cell shows fill (id 1) on layer 0")

	# Closed-door mechanics on the real layout: enter an uncleared COMBAT
	# zone through one of its combat-locked doors and confirm the layer-2
	# dark door tiles appear, then clear and confirm they drop.
	var lock_ok := false
	if gen_lock_combat_zone(gen, real_layout, real_map):
		lock_ok = true
	_check(lock_ok, "real render: combat lock + clear works end-to-end")

	real_map.free()

	if _fails == 0:
		print("VERIFY_ALL_OK")
		quit(0)
	else:
		print("VERIFY_FAILED fails=%d" % _fails)
		quit(1)


## Walks a real generated layout through a combat lock + clear cycle using
## the real DoorController, and returns the door proving it. Finds a door
## whose far side is an uncleared COMBAT zone, approaches from the other
## side, crosses, then clears the combat zone.
func gen_lock_combat_zone(gen: Node, real_layout: DungeonGenerator.FloorLayout,
		real_map: TileMap) -> Zone.Door:
	var dc: Node = load("res://scripts/dungeon/door_controller.gd").new()
	dc.initialize(real_layout, real_map)
	for d in real_layout.doors:
		var door: Zone.Door = d
		if not door.combat_locked:
			continue
		# Resolve which side is the uncleared COMBAT zone; pick that target.
		var side_target: int = 0
		var z_right: Zone = dc._zone_on_side(dc._zones, door, 1) as Zone
		if z_right != null and z_right.type == Zone.ZoneType.COMBAT \
				and not z_right.cleared:
			side_target = 1
		else:
			var z_left: Zone = dc._zone_on_side(dc._zones, door, -1) as Zone
			if z_left == null or z_left.type != Zone.ZoneType.COMBAT \
					or z_left.cleared:
				continue
			side_target = -1
		var target: Zone = dc._zone_on_side(dc._zones, door, side_target) as Zone
		# Approach sign: the player starts on the OPPOSITE side.
		var sign_from: int = -side_target
		# The body is teleported; the controller calls below are direct, so
		# only the side math matters (entry left of the line, exit past it).
		var line: float = door.edge_line * DungeonGeometry.TILE_SIZE
		var entry_offset: float = -24.0 if sign_from < 0 else 40.0
		var exit_offset: float = 40.0 if sign_from < 0 else -24.0
		var player := CharacterBody2D.new()
		if door.edge_axis == "v":
			player.position = Vector2(line + entry_offset,
					door.pos_along * DungeonGeometry.TILE_SIZE + 8.0)
			player.velocity = Vector2(100.0 * side_target, 0.0)
		else:
			player.position = Vector2(door.pos_along * DungeonGeometry.TILE_SIZE + 8.0,
					line + entry_offset)
			player.velocity = Vector2(0.0, 100.0 * side_target)
		dc._on_door_body_entered(player, door, dc._zones)
		if door.edge_axis == "v":
			player.position.x = line + exit_offset
		else:
			player.position.y = line + exit_offset
		dc._on_door_body_exited(player, door, dc._zones)
		player.free()

		var proved: Zone.Door = door
		if proved.state != 1:
			dc.free()
			continue
		# Layer-2 closed tiles present on this corridor, and layer 2 holds
		# EXACTLY the union of the corridors of every currently-locked door
		# (_lock_zone_doors seals all open combat-locked doors of the zone)
		# — no tiles over unpunched cells outside those corridors.
		var cells: Array[Vector2i] = dc._corridor_cells(proved)
		var expected: Array[Vector2i] = []
		for d_locked in real_layout.doors:
			var locked: Zone.Door = d_locked
			if locked.state == 1:
				for c_locked in dc._corridor_cells(locked):
					expected.append(c_locked)
		var tiles_ok: bool = _same_cell_set(real_map.get_used_cells(2), expected)
		for cellv in cells:
			if real_map.get_cell_source_id(2, cellv) != DungeonGeometry.FLOOR_SOURCE_ID \
					or real_map.get_cell_alternative_tile(2, cellv) \
							!= DungeonGeometry.DOOR_CLOSED_ALT:
				tiles_ok = false
		# Clear the combat zone: tiles drop, state opens, layer 2 empty.
		target.cleared = true
		dc.on_zone_cleared(target.id)
		var open_ok := true
		if proved.state != 0:
			open_ok = false
		if not real_map.get_used_cells(2).is_empty():
			open_ok = false
		dc.free()
		if open_ok and tiles_ok:
			return proved
	return null

