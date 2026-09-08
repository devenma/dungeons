extends SceneTree

# Runtime assertions for combat-zone door locking:
#   1. Doors start OPEN at floor start (no START-zone deadlock).
#   2. Entering an uncleared COMBAT zone locks its doors.
#   3. Clearing the zone re-opens its doors.
#   4. Re-entering a cleared zone does NOT re-lock.
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
	var z0: Zone = Zone.new()
	z0.id = 0
	z0.type = Zone.ZoneType.START
	z0.cell_min = Vector2i(0, 0)
	z0.cell_max = Vector2i(1, 1)
	z0.tile_rect = Rect2i(0, 0, 75, 75)
	z0.neighbors.append(1)

	var z1: Zone = Zone.new()
	z1.id = 1
	z1.type = Zone.ZoneType.COMBAT
	z1.cell_min = Vector2i(1, 0)
	z1.cell_max = Vector2i(2, 1)
	z1.tile_rect = Rect2i(75, 0, 75, 75)
	z1.neighbors.append(0)

	var door: Zone.Door = Zone.Door.new()
	door.id = 0
	door.zone_a_id = 0
	door.zone_b_id = 1
	door.edge_axis = "v"
	door.edge_line = 75          # first column of the right zone
	door.pos_along = 37          # middle of the shared span
	door.state = 0               # doors start OPEN
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

	var gap_tiles: Array = []
	for offset in range(-1, 2):
		gap_tiles.append(Vector2i(75, 37 + offset))

	# ── Check 1: floor starts with doors OPEN (START-zone deadlock fix) ──
	_check(door.state == 0, "door state is OPEN at floor start")
	for t in gap_tiles:
		_check(tilemap.get_cell_source_id(2, t) == -1,
				"gap tile %s empty at floor start (door passable)" % str(t))

	# ── Check 2: entering the combat zone locks its doors ──
	var entered: Array = []  # Array (reference type) so the lambda capture works
	dc.zone_entered.connect(func(zid: int) -> void: entered.append(zid))

	var player := CharacterBody2D.new()
	# Entry: player approaching from the left side of the door line
	player.position = Vector2(75 * 16 - 24, 37 * 16 + 8)
	player.velocity = Vector2(100, 0)
	dc._on_door_body_entered(player, door, dc._zones)
	# Exit: player fully past the line, moving right
	player.position = Vector2(75 * 16 + 40, 37 * 16 + 8)
	dc._on_door_body_exited(player, door, dc._zones)

	_check(entered.size() == 1 and entered[0] == 1,
			"zone_entered emitted exactly once for combat zone 1")
	_check(door.state == 1, "door CLOSED after entering combat zone")
	for t in gap_tiles:
		_check(tilemap.get_cell_source_id(2, t) == door_src_id,
				"gap tile %s has door tile after lock" % str(t))

	# ── Check 3: clearing the zone re-opens the doors ──
	dc.on_zone_cleared(1)
	_check(door.state == 0, "door OPEN after zone cleared")
	for t in gap_tiles:
		_check(tilemap.get_cell_source_id(2, t) == -1,
				"gap tile %s erased after zone cleared" % str(t))

	# ── Check 4: re-entering a cleared zone does NOT re-lock ──
	z1.cleared = true
	player.position = Vector2(75 * 16 - 24, 37 * 16 + 8)
	dc._on_door_body_entered(player, door, dc._zones)
	player.position = Vector2(75 * 16 + 40, 37 * 16 + 8)
	dc._on_door_body_exited(player, door, dc._zones)
	_check(door.state == 0, "cleared zone does not re-lock on re-entry")
	_check(entered.size() == 2 and entered[1] == 1,
			"zone_entered still emitted on re-entry of cleared zone")

	dc.free()
	gen.free()
	tilemap.free()

	if _fails == 0:
		print("VERIFY_ALL_OK")
		quit(0)
	else:
		print("VERIFY_FAILED fails=%d" % _fails)
		quit(1)
