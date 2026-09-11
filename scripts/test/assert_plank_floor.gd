extends SceneTree

# Render-contract assertions for the prebuilt dungeon tileset (Phase 6,
# task 6.1, prebuilt-tileset). Two test layers exist:
#
#   - scripts/test/assert_prebuilt_tileset.gd
#       resource-only contract of res://tilesets/dungeon.tres.
#   - THIS script
#       the .tres contract summary PLUS the render contract on a REAL
#       generation run (generate_floor -> _render_layout via the normal
#       path), determinism of cell placement across two runs, and the
#       cheap geometry invariants shared with the spawner.
#
# No skipped or faked checks: every contract point either holds or the run
# fails with a loud push_error naming the failed check. Where a check fully
# duplicates assert_prebuilt_tileset.gd, the duplication is intentional
# (defense in depth between the resource-only and resource+render layers).
#
# Run: godot --headless -s scripts/test/assert_plank_floor.gd
# Exit 0 on pass; nonzero + push_error on failure.

const RENDER_SEED := 987654
const RENDER_FLOOR := 1

var _fails: int = 0
var _gen: Node = null
var _layout: DungeonGenerator.FloorLayout = null
var _map: TileMap = null


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		_fails += 1
		push_error("ASSERT_PLANK_FLOOR FAILED CHECK: " + msg)
		print("VERIFY_FAIL: " + msg)


func _check_matrix(ok: bool, first_offender: String, msg: String) -> void:
	if ok:
		print("PASS: " + msg)
	else:
		_fails += 1
		push_error("ASSERT_PLANK_FLOOR FAILED CHECK: %s (first offender: %s)"
				% [msg, first_offender])
		print("VERIFY_FAIL: %s (first offender: %s)" % [msg, first_offender])


func _init() -> void:
	_run_tileset_contract_checks()
	_run_real_generation_checks()
	_run_determinism_checks()
	_run_geometry_invariant_checks()
	_finish()


# ── .tres contract (compact mirror of assert_prebuilt_tileset.gd) ───────────

func _run_tileset_contract_checks() -> void:
	var ts: TileSet = load(DungeonGeometry.DUNGEON_TILESET_PATH)
	if ts == null:
		push_error("FATAL: cannot load " + DungeonGeometry.DUNGEON_TILESET_PATH)
		_fails += 1
		return
	_check(ts.tile_size == Vector2i(DungeonGeometry.TILE_SIZE, DungeonGeometry.TILE_SIZE),
			".tres tile_size is 32x32")
	_check(ts.get_source_count() == 3, ".tres has exactly 3 sources")

	var wall_src: TileSetAtlasSource = ts.get_source(DungeonGeometry.WALL_SOURCE_ID)
	var fill_src: TileSetAtlasSource = ts.get_source(DungeonGeometry.FLOOR_SOURCE_ID)
	if wall_src == null or fill_src == null:
		push_error("FATAL: sources %d/%d missing from the .tres"
				% [DungeonGeometry.WALL_SOURCE_ID, DungeonGeometry.FLOOR_SOURCE_ID])
		_fails += 1
		return

	# Wall source: 12 wall tiles with full-tile collision, 4 trim tiles without.
	var wall_roles: Array[Vector2i] = [
		DungeonGeometry.WALL_CORNER_TL, DungeonGeometry.WALL_CORNER_TR,
		DungeonGeometry.WALL_CORNER_BL, DungeonGeometry.WALL_CORNER_BR,
		DungeonGeometry.WALL_TOP_A, DungeonGeometry.WALL_TOP_B,
		DungeonGeometry.WALL_LEFT_A, DungeonGeometry.WALL_LEFT_B,
		DungeonGeometry.WALL_RIGHT_A, DungeonGeometry.WALL_RIGHT_B,
		DungeonGeometry.WALL_BOTTOM_A, DungeonGeometry.WALL_BOTTOM_B,
	]
	var edge_roles: Array[Vector2i] = [
		DungeonGeometry.FLOOR_EDGE_TL, DungeonGeometry.FLOOR_EDGE_TR,
		DungeonGeometry.FLOOR_EDGE_BL, DungeonGeometry.FLOOR_EDGE_BR,
	]
	var wall_ok := true
	var wall_detail := ""
	for coords in wall_roles:
		if not wall_src.has_tile(coords):
			wall_ok = false
			wall_detail = "missing wall tile " + str(coords)
			break
		var td: TileData = wall_src.get_tile_data(coords, 0)
		if td == null or td.get_collision_polygons_count(0) != 1 \
				or td.get_collision_polygon_points(0, 0).size() != 4:
			wall_ok = false
			wall_detail = "wall tile " + str(coords) + " lacks one full-tile polygon"
			break
	_check_matrix(wall_ok, wall_detail,
			"wall source: all 12 wall tiles carry one full-tile collision polygon")

	var edge_ok := true
	var edge_detail := ""
	for coords in edge_roles:
		if not wall_src.has_tile(coords):
			edge_ok = false
			edge_detail = "missing trim tile " + str(coords)
			break
		var td2: TileData = wall_src.get_tile_data(coords, 0)
		if td2 == null or td2.get_collision_polygons_count(0) != 0:
			edge_ok = false
			edge_detail = "trim tile " + str(coords) + " carries collision"
			break
	_check_matrix(edge_ok, edge_detail,
			"wall source: all 4 trim tiles carry no collision")

	# Fill source: 4 plain tiles without collision + frozen tint alternatives.
	var fill_tiles: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1),
	]
	var fill_ok := true
	var fill_detail := ""
	var tints_ok := true
	var tints_detail := ""
	for coords2 in fill_tiles:
		if not fill_src.has_tile(coords2):
			fill_ok = false
			fill_detail = "missing fill tile " + str(coords2)
			break
		var tf: TileData = fill_src.get_tile_data(coords2, 0)
		if tf == null or tf.get_collision_polygons_count(0) != 0:
			fill_ok = false
			fill_detail = "fill tile " + str(coords2) + " carries collision"
			break
		if not fill_src.has_alternative_tile(coords2, DungeonGeometry.FLOOR_ALT_START) \
				or not fill_src.has_alternative_tile(coords2, DungeonGeometry.FLOOR_ALT_REWARD) \
				or not fill_src.has_alternative_tile(coords2, DungeonGeometry.FLOOR_ALT_EXIT) \
				or not fill_src.has_alternative_tile(coords2, DungeonGeometry.DOOR_CLOSED_ALT):
			tints_ok = false
			tints_detail = "fill tile " + str(coords2) + " misses an alternative"
			break
		if fill_src.get_tile_data(coords2, DungeonGeometry.FLOOR_ALT_START).modulate \
				!= DungeonGeometry.FLOOR_TINT_START \
				or fill_src.get_tile_data(coords2, DungeonGeometry.FLOOR_ALT_REWARD).modulate \
					!= DungeonGeometry.FLOOR_TINT_REWARD \
				or fill_src.get_tile_data(coords2, DungeonGeometry.FLOOR_ALT_EXIT).modulate \
					!= DungeonGeometry.FLOOR_TINT_EXIT:
			tints_ok = false
			tints_detail = "fill tile " + str(coords2) + " has a wrong tint"
			break
	_check_matrix(fill_ok, fill_detail, "fill source: all 4 fill tiles carry no collision")
	_check_matrix(tints_ok, tints_detail,
			"fill source: START/REWARD/EXIT alternatives exist with the frozen modulate values")

	# Closed-door alternative: dark, with exactly one full-tile polygon
	# (alternatives do NOT inherit the base tile's physics).
	var door_closed_ok := true
	var door_closed_detail := ""
	for coords3 in fill_tiles:
		var tdc: TileData = fill_src.get_tile_data(coords3, DungeonGeometry.DOOR_CLOSED_ALT)
		if tdc == null or tdc.modulate != DungeonGeometry.DOOR_TINT_CLOSED \
				or tdc.get_collision_polygons_count(0) != 1 \
				or tdc.get_collision_polygon_points(0, 0).size() != 4:
			door_closed_ok = false
			door_closed_detail = "fill tile " + str(coords3)
			break
	_check_matrix(door_closed_ok, door_closed_detail,
			"DOOR_CLOSED_ALT=%d alternative is dark with one full-tile collision polygon"
					% DungeonGeometry.DOOR_CLOSED_ALT)

	# Open-door variant: the plain (white) base fill tile, no collision.
	var open_td: TileData = fill_src.get_tile_data(DungeonGeometry.DOOR_FILL_ATLAS,
			DungeonGeometry.DOOR_OPEN_ALT)
	_check(open_td != null and open_td.modulate == Color(1, 1, 1)
			and open_td.get_collision_polygons_count(0) == 0,
			"DOOR_OPEN_ALT=%d is the plain fill tile without collision"
					% DungeonGeometry.DOOR_OPEN_ALT)


# ── Render contract on a REAL generation run ────────────────────────────────

func _zone_fill_alt(type: int) -> int:
	# Independent expectation (from DungeonGeometry consts, not the generator).
	match type:
		Zone.ZoneType.START:
			return DungeonGeometry.FLOOR_ALT_START
		Zone.ZoneType.REWARD:
			return DungeonGeometry.FLOOR_ALT_REWARD
		Zone.ZoneType.EXIT:
			return DungeonGeometry.FLOOR_ALT_EXIT
		_:
			return 0


func _run_real_generation_checks() -> void:
	_gen = load("res://scripts/dungeon/dungeon_generator.gd").new()
	var data: FloorData = FloorData.new()
	_layout = _gen.generate_floor(RENDER_FLOOR, RENDER_SEED, data)
	_map = TileMap.new()
	_gen._render_layout(_layout, _map)

	_check(_map.tile_set != null,
			"render assigns the prebuilt tileset loaded from the .tres")
	_check(_map.get_layers_count() == 3, "render ensures the 3 layers (floor/wall/door)")
	_check(_map.get_used_cells(0).size() > 0, "layer 0 (floor) is non-empty")
	_check(_map.get_used_cells(1).size() > 0, "layer 1 (walls) is non-empty")
	_check(_layout.zones.size() >= 3, "real floor generates its zone count")

	# Punched corridor cells across all doors (shared full-depth formula:
	# offsets -R..R-1 cross-axis, DOOR_GAP_TILES centered along-axis).
	var punched: Dictionary = {}  # Vector2i -> true
	var punch_ok := true
	var punch_detail := ""
	for d in _layout.doors:
		var door: Zone.Door = d
		var door_tile: Vector2i
		if door.edge_axis == "v":
			door_tile = Vector2i(door.edge_line, door.pos_along)
		else:
			door_tile = Vector2i(door.pos_along, door.edge_line)
		var ring: int = DungeonGeometry.WALL_RING_TILES
		var edge: int = DungeonGeometry.FLOOR_EDGE_TILES
		var half_gap: int = DungeonGeometry.DOOR_GAP_TILES / 2
		for dz in range(-ring - edge, ring + edge):
			for g in range(-half_gap, half_gap + 1):
				var cell: Vector2i
				if door.edge_axis == "v":
					cell = Vector2i(door_tile.x + dz, door_tile.y + g)
				else:
					cell = Vector2i(door_tile.x + g, door_tile.y + dz)
				punched[cell] = true
				if _map.get_cell_source_id(1, cell) != -1:
					punch_ok = false
					punch_detail = "corridor cell " + str(cell) + " still has a wall tile"
				if _map.get_cell_source_id(0, cell) != DungeonGeometry.FLOOR_SOURCE_ID:
					punch_ok = false
					punch_detail = "corridor cell " + str(cell) + " shows no floor on layer 0"
	_check_matrix(punch_ok, punch_detail,
			"every door corridor is punched: walls erased, floor shows on layer 0")

	# Full-zone placement matrix against the frozen role constants.
	var wall_ok := true
	var wall_detail := ""
	var fill_ok := true
	var fill_detail := ""
	var trim_ok := true
	var trim_detail := ""
	for z_any in _layout.zones:
		var z: Zone = z_any
		var origin: Vector2i = z.tile_rect.position
		var size: Vector2i = z.tile_rect.size
		var fill_alt: int = _zone_fill_alt(z.type)
		for ty in size.y:
			for tx in size.x:
				var pos: Vector2i = origin + Vector2i(tx, ty)
				var depth: int = DungeonGeometry.tile_edge_depth(tx, ty, size.x, size.y)
				# Layer 1: wall band uses the wall source with the per-side
				# role tile, except where a corridor punched it open.
				if depth == 0:
					var ws: int = _map.get_cell_source_id(1, pos)
					if punched.has(pos):
						if ws != -1:
							wall_ok = false
							wall_detail = "punched cell " + str(pos) + " has a wall tile"
					elif ws != DungeonGeometry.WALL_SOURCE_ID \
							or _map.get_cell_atlas_coords(1, pos) \
								!= DungeonGeometry.wall_atlas_for(tx, ty, size.x, size.y):
						wall_ok = false
						wall_detail = "wall band cell " + str(pos) + " has the wrong wall tile"
				# Layer 0: fill everywhere, except unpunched trim-ring cells
				# which use baseboard tiles: corners from the wall sheet,
				# straight edges from the synthesized one-sided edge source.
				# Punched corridor cells are plain floor (punch overwrites
				# layer 0), so they fall in the else branch below.
				if punched.has(pos):
					continue
				var ls: int = _map.get_cell_source_id(0, pos)
				var lat: Vector2i = _map.get_cell_atlas_coords(0, pos)
				var lalt: int = _map.get_cell_alternative_tile(0, pos)
				if depth == 1 and DungeonGeometry.is_trim_corner(tx, ty, size.x, size.y):
					var trim: Vector2i = DungeonGeometry.floor_edge_atlas_for(
							tx, ty, size.x, size.y)
					if ls != DungeonGeometry.WALL_SOURCE_ID or lat != trim or lalt != 0:
						trim_ok = false
						trim_detail = "trim corner cell " + str(pos)
				elif depth == 1:
					var straight: Dictionary = DungeonGeometry.trim_cell_at(
							tx, ty, size.x, size.y)
					if ls != DungeonGeometry.EDGE_SOURCE_ID \
							or lat != straight.atlas or lalt != 0:
						trim_ok = false
						trim_detail = "trim straight-edge cell " + str(pos) \
								+ " (src=%d, atlas=%s)" % [ls, lat]
				else:
					var expected_atlas := Vector2i(tx % 2, ty % 2)
					var expected_alt: int = 0 if depth == 0 else fill_alt
					if ls != DungeonGeometry.FLOOR_SOURCE_ID \
							or lat != expected_atlas or lalt != expected_alt:
						fill_ok = false
						fill_detail = "floor cell " + str(pos) \
								+ " (src=%d, atlas=%s, alt=%d; want src=%d, alt=%d)" \
								% [ls, lat, lalt, DungeonGeometry.FLOOR_SOURCE_ID, expected_alt]
	_check_matrix(wall_ok, wall_detail, "all wall-band cells use the wall source (id 0) role tiles")
	_check_matrix(fill_ok, fill_detail,
			"all fill cells use the floor source (id 1) with the zone's tint alternative")
	_check_matrix(trim_ok, trim_detail,
			"trim ring complete: corners per frozen coords + straight edges via the edge source")

	# At least one START zone painted with its tint alternative (probe the
	# rect center: always a depth>=2 interior cell, never punched).
	var start_ok := false
	var start_detail := "no START zone found"
	for z_any2 in _layout.zones:
		var zs: Zone = z_any2
		if zs.type != Zone.ZoneType.START:
			continue
		var origin2: Vector2i = zs.tile_rect.position
		var size2: Vector2i = zs.tile_rect.size
		var probe: Vector2i = origin2 + Vector2i(size2.x / 2, size2.y / 2)
		if _map.get_cell_alternative_tile(0, probe) == DungeonGeometry.FLOOR_ALT_START:
			start_ok = true
			start_detail = ""
			break
		start_detail = "START probe cell " + str(probe) + " lacks the START tint"
	_check_matrix(start_ok, start_detail,
			"at least one START zone is painted with its tint alternative")


# ── Determinism: same seed → identical cell placement ───────────────────────

func _zones_equal(a: DungeonGenerator.FloorLayout,
		b: DungeonGenerator.FloorLayout) -> bool:
	if a.grid_w != b.grid_w or a.grid_h != b.grid_h:
		return false
	if a.zones.size() != b.zones.size() or a.doors.size() != b.doors.size():
		return false
	for za_any in a.zones:
		var za: Zone = za_any
		var found := false
		for zb_any in b.zones:
			var zb: Zone = zb_any
			if za.id == zb.id and za.type == zb.type \
					and za.cell_min == zb.cell_min and za.cell_max == zb.cell_max \
					and za.tile_rect == zb.tile_rect:
				found = true
				break
		if not found:
			return false
	for da_any in a.doors:
		var da: Zone.Door = da_any
		var door_found := false
		for db_any in b.doors:
			var db: Zone.Door = db_any
			if da.id == db.id and da.edge_axis == db.edge_axis \
					and da.edge_line == db.edge_line and da.pos_along == db.pos_along:
				door_found = true
				break
		if not door_found:
			return false
	return true


func _layers_identical(map_b: TileMap) -> bool:
	for layer in [0, 1]:
		var cells_a: Array[Vector2i] = _map.get_used_cells(layer)
		var cells_b: Array[Vector2i] = map_b.get_used_cells(layer)
		if cells_a.size() != cells_b.size():
			return false
		for c in cells_a:
			if map_b.get_cell_source_id(layer, c) != _map.get_cell_source_id(layer, c) \
					or map_b.get_cell_atlas_coords(layer, c) \
						!= _map.get_cell_atlas_coords(layer, c) \
					or map_b.get_cell_alternative_tile(layer, c) \
						!= _map.get_cell_alternative_tile(layer, c):
				return false
	return true


func _run_determinism_checks() -> void:
	if _gen == null or _map == null:
		return  # fatal already recorded by the contract checks
	var data: FloorData = FloorData.new()
	var layout_b: DungeonGenerator.FloorLayout = _gen.generate_floor(
			RENDER_FLOOR, RENDER_SEED, data)
	var map_b := TileMap.new()
	_gen._render_layout(layout_b, map_b)

	_check(_zones_equal(_layout, layout_b),
			"same seed produces an identical zone/door layout")
	_check(_layers_identical(map_b),
			"two runs with the same seed place identical (source, atlas, alt) tuples on layers 0/1")
	_check(_map.get_used_cells(2).is_empty() and map_b.get_used_cells(2).is_empty(),
			"doors start open: layer 2 is empty in both runs")
	map_b.free()


# ── Cheap camera/spawner geometry invariants ────────────────────────────────

func _run_geometry_invariant_checks() -> void:
	_check(DungeonGeometry.TILE_SIZE == 32,
			"shared TILE_SIZE is 32 (camera limits and spawner derive from it)")
	var spawner_script: GDScript = load("res://scripts/dungeon/spawner.gd")
	_check(spawner_script.INTERIOR_INSET_TILES
			== DungeonGeometry.WALL_RING_TILES + DungeonGeometry.FLOOR_EDGE_TILES,
			"spawner interior inset derives from the shared wall+trim bands")


# ── Summary ──────────────────────────────────────────────────────────────────

func _finish() -> void:
	if _map != null:
		_map.free()
	if _gen != null:
		_gen.free()
	if _fails == 0:
		print("ALL ASSERT_PLANK_FLOOR CHECKS PASSED")
		quit(0)
	else:
		print("ASSERT_PLANK_FLOOR: %d check(s) failed" % _fails)
		quit(1)
