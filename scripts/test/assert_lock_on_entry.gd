extends SceneTree

# Runtime assertions for combat-zone door locking:
#   1. Doors start OPEN at floor start (no START-zone deadlock).
#   2. Entering an uncleared COMBAT zone locks its doors.
#   3. Clearing the zone re-opens its doors (no leftover door tiles).
#   4. Re-entering a cleared zone does NOT re-lock.
#   5. Real render sanity (Phase 3/4, prebuilt-tileset): generate_floor on a
#      fixed seed renders tiles from the prebuilt .tres — wall cells use
#      source 0, fill uses source 1, closed combat doors place the dark fill
#      alternative on layer 2 and it drops when the zone clears.
# Run: godot --headless -s scripts/test/assert_lock_on_entry.gd

var _fails: int = 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		_fails += 1
		print("VERIFY_FAIL: " + msg)


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
	var door_src_id: int = gen._render_layout(layout, tilemap)

	var dc: Node = load("res://scripts/dungeon/door_controller.gd").new()
	dc.initialize(layout, tilemap, door_src_id)

	# The corridor spans BOTH wall rings' full depth: columns
	# [edge_line - R, edge_line + R - 1] at the door row.
	var corridor_tiles: Array[Vector2i] = []
	for dz in range(-DungeonGeometry.WALL_RING_TILES,
			DungeonGeometry.WALL_RING_TILES):
		corridor_tiles.append(Vector2i(cell + dz, cell / 2))

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

	# ── Check 3: clearing the zone re-opens the doors ──
	dc.on_zone_cleared(1)
	_check(door.state == 0, "door OPEN after zone cleared")
	for t in corridor_tiles:
		_check(tilemap.get_cell_source_id(2, t) == -1,
				"corridor tile %s erased after zone cleared" % str(t))

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
				# layer-0: fill everywhere except a punched corridor
				# (-1) and the trim-ring corners (wall-sheet baseboard).
				if fs != DungeonGeometry.FLOOR_SOURCE_ID:
					var is_trim_corner: bool = DungeonGeometry.tile_edge_depth(
							tx, ty, size.x, size.y) == 1 \
							and DungeonGeometry.is_trim_corner(
									tx, ty, size.x, size.y)
					if not (is_trim_corner and fs == DungeonGeometry.WALL_SOURCE_ID):
						fill_ok = false
	_check(walls_ok, "real render: wall band uses the wall source (id 0)")
	_check(fill_ok, "real render: every zone cell shows fill (id 1) on layer 0")

	# Closed-door mechanics on the real layout: enter an uncleared COMBAT
	# zone through one of its combat-locked doors and confirm the layer-2
	# dark door tiles appear, then clear and confirm they drop.
	var lock_ok := false
	if gen_lock_combat_zone(gen, real_layout, real_map, door_src_id):
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
		real_map: TileMap, source_id: int) -> Zone.Door:
	var dc: Node = load("res://scripts/dungeon/door_controller.gd").new()
	dc.initialize(real_layout, real_map, source_id)
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
		# Layer-2 closed tiles present on the corridor.
		var cells: Array = dc._corridor_cells(proved)
		var tiles_ok := true
		for cell_any in cells:
			var cellv: Vector2i = cell_any
			var src: int = real_map.get_cell_source_id(2, cellv)
			if src != DungeonGeometry.FLOOR_SOURCE_ID \
					or real_map.get_cell_alternative_tile(2, cellv) \
							!= DungeonGeometry.DOOR_CLOSED_ALT:
				tiles_ok = false
		# Clear the combat zone: tiles drop, state opens.
		target.cleared = true
		dc.on_zone_cleared(target.id)
		var open_ok := true
		if proved.state != 0:
			open_ok = false
		for cell_any2 in cells:
			var cellv2: Vector2i = cell_any2
			if real_map.get_cell_source_id(2, cellv2) != -1:
				open_ok = false
		dc.free()
		if open_ok and tiles_ok:
			return proved
	return null

