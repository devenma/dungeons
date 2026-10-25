extends SceneTree

## Run: godot --headless -s scripts/test/assert_zone_partition.gd
## Zone partition invariants: across many seeds and floor depths every layout passes
## DungeonGenerator.validate_layout (exact rects, no overlap, full coverage, min size,
## START cap, exit stairs placed by stairs_fit, doors on shared edges, all zones reachable),
## with a zone count in range, and the same seed gives the same zones. The validator itself
## must reject broken layouts.
## Exit 0 = pass, 1 = fail.

# Seeds por profundidad de piso / Seeds per floor depth
const SEEDS: int = 500
const FLOORS: Array[int] = [1, 5, 10]

var _failures: int = 0


func _initialize() -> void:
	var data: FloorData = load("res://resources/floors/floor_data.tres") as FloorData
	var gen := DungeonGenerator.new()
	for floor_number in FLOORS:
		var zone_range: Vector2i = gen._get_zone_count_for_floor(floor_number, data)
		for s in range(SEEDS):
			_check_seed(gen, s, floor_number, zone_range, data)
	_check_validator_rejects(gen, data)
	gen.free()
	if _failures == 0:
		print("PASS: zone partition holds on %d seeds x %d floors" % [SEEDS, FLOORS.size()])
	quit(0 if _failures == 0 else 1)


func _check_seed(gen: DungeonGenerator, seed_value: int, floor_number: int,
		zone_range: Vector2i, data: FloorData) -> void:
	var tag: String = "seed %d floor %d" % [seed_value, floor_number]
	var layout: DungeonGenerator.FloorLayout = gen.generate_floor(floor_number, seed_value, data)
	if layout == null:
		_fail("%s: generation failed" % tag)
		return
	var error: String = gen.validate_layout(layout, data)
	_check(error.is_empty(), "%s: %s" % [tag, error])
	_check(layout.zones.size() >= zone_range.x and layout.zones.size() <= zone_range.y,
			"%s: %d zones outside %s" % [tag, layout.zones.size(), zone_range])
	if seed_value % 50 == 0:
		var again: DungeonGenerator.FloorLayout = gen.generate_floor(floor_number, seed_value, data)
		_check(_zones_signature(layout) == _zones_signature(again),
				"%s: same seed gives the same zones" % tag)


func _check_validator_rejects(gen: DungeonGenerator, data: FloorData) -> void:
	var broken: Array[String] = ["overlap", "gap", "small", "tile_rect", "door", "no_door",
			"stairs_face", "stairs_entry", "stairs_side"]
	for kind in broken:
		var layout: DungeonGenerator.FloorLayout = gen.generate_floor(1, 4242, data)
		var zone: Zone = layout.zones[layout.zones.size() - 1]
		match kind:
			"overlap":
				zone.cell_min -= Vector2i.ONE
				zone.tile_rect = gen._tile_rect_for_cells(zone.cell_min, zone.cell_max)
			"gap":
				zone.cell_max.x -= 1
				zone.tile_rect = gen._tile_rect_for_cells(zone.cell_min, zone.cell_max)
			"small":
				# Una zona sin celdas queda bajo cualquier mínimo / A zone without cells is below any minimum
				zone.cell_max.x = zone.cell_min.x
				zone.tile_rect = gen._tile_rect_for_cells(zone.cell_min, zone.cell_max)
			"tile_rect":
				zone.tile_rect.size.x -= 1
			"door":
				var door: Zone.Door = layout.doors[0]
				door.edge_line += 1
			"no_door":
				layout.doors.clear()
			"stairs_face", "stairs_entry", "stairs_side":
				var exit: Zone = gen._find_zone(layout, layout.exit_zone_id)
				var r: Rect2i = exit.tile_rect
				var x: int = r.position.x + 4
				if kind == "stairs_face":
					layout.exit_stairs = Vector2i(x, r.position.y + DungeonGeometry.NORTH_FACE_ROWS)
				elif kind == "stairs_entry":
					# Una sola fila libre hasta la pared sur / A single free row down to the south wall
					layout.exit_stairs = Vector2i(x, r.end.y - 2 - DungeonGeometry.STAIRS_DOWN_SIZE.y)
				else:
					layout.exit_stairs = Vector2i(r.position.x + 1, r.position.y + 4)
		_check(not gen.validate_layout(layout, data).is_empty(),
				"validator rejects a layout with a broken %s" % kind)


func _zones_signature(layout: DungeonGenerator.FloorLayout) -> String:
	var parts: PackedStringArray = []
	for z in layout.zones:
		var zone: Zone = z
		parts.append("%d:%d:%s:%s" % [zone.id, zone.type, zone.cell_min, zone.cell_max])
	parts.append("doors=%d stairs=%s" % [layout.doors.size(), layout.exit_stairs])
	return ",".join(parts)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fail(msg)


func _fail(msg: String) -> void:
	_failures += 1
	print("FAIL: " + msg)
