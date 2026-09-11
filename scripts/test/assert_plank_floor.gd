extends SceneTree

# Runtime assertions for the plank floor + wall-ring placement at 32px:
#
# NOTE (Phase 3, prebuilt-tileset): the legacy in-code tileset builder
# (_build_tileset) was deleted in Phase 3 — the builder-contract checks that
# mirrored it (FLOOR_PATCH_SCALE sheet slicing, 24x24 wall template slicing,
# per-variant tint alternative maps) no longer hold and were REMOVED here.
# TODO(Phase 6, task 6.1): full rewrite of this script to assert the .tres
# contract end-to-end; scripts/test/assert_prebuilt_tileset.gd covers the
# .tres resource contract in the meantime. Never re-fake builder checks.
#
# Remaining (kept, adapted to the 32px render contract):
#   1. Render returns a valid door fill source id (3 layers ensured).
#   2. Wall ring: depth-0 border cells use source 0 with the frozen
#      DungeonGeometry role tiles (corners + per-side alternation).
#   3. Trim ring corners use the wall-sheet baseboard tiles; interior and
#      trim edges use the plain fill source with the zone tint alternative.
#   4. Placement is deterministic per zone.
# Run: godot --headless -s scripts/test/assert_plank_floor.gd

var _fails: int = 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		_fails += 1
		print("VERIFY_FAIL: " + msg)


func _init() -> void:
	# ── Minimal layout: START (left) + COMBAT (right), 2x1 grid, 8-tile cells ──
	var z0: Zone = Zone.new()
	z0.id = 0
	z0.type = Zone.ZoneType.START
	z0.cell_min = Vector2i(0, 0)
	z0.cell_max = Vector2i(1, 1)
	z0.tile_rect = Rect2i(0, 0, DungeonGeometry.CELL_TILES, DungeonGeometry.CELL_TILES)

	var z1: Zone = Zone.new()
	z1.id = 1
	z1.type = Zone.ZoneType.COMBAT
	z1.cell_min = Vector2i(1, 0)
	z1.cell_max = Vector2i(2, 1)
	z1.tile_rect = Rect2i(DungeonGeometry.CELL_TILES, 0,
			DungeonGeometry.CELL_TILES, DungeonGeometry.CELL_TILES)
	z1.neighbors.append(0)
	z0.neighbors.append(1)

	var layout: DungeonGenerator.FloorLayout = DungeonGenerator.FloorLayout.new()
	layout.floor_number = 1
	layout.floor_seed = 12345
	layout.grid_w = 2
	layout.grid_h = 1
	layout.zones = [z0, z1]
	layout.doors = []

	# ── Real render from the prebuilt .tres ──
	var gen: Node = load("res://scripts/dungeon/dungeon_generator.gd").new()
	var tilemap := TileMap.new()
	gen._render_layout(layout, tilemap)
	_check(true, "render completed without error")

	_check(tilemap.get_layers_count() == 3, "floor renders on 3 layers")
	_check(tilemap.get_used_cells(0).size() > 0, "render produces tiles")
	_check(tilemap.tile_set != null,
			"tileset loaded from the prebuilt .tres resource")

	# ── Wall ring at the border, per-side role tiles ──
	var w: int = DungeonGeometry.CELL_TILES
	var probe_tl := Vector2i(0, 0)
	_check(tilemap.get_cell_source_id(1, probe_tl) == DungeonGeometry.WALL_SOURCE_ID
			and tilemap.get_cell_atlas_coords(1, probe_tl) == DungeonGeometry.WALL_CORNER_TL,
			"zone corner maps to the wall sheet's TL corner tile")
	var probe_top := Vector2i(4, 0)
	var top_expected: Vector2i = DungeonGeometry.wall_atlas_for(4, 0, w, DungeonGeometry.CELL_TILES)
	_check(tilemap.get_cell_source_id(1, probe_top) == DungeonGeometry.WALL_SOURCE_ID
			and tilemap.get_cell_atlas_coords(1, probe_top) == top_expected,
			"top-edge interior maps to the per-side wall top tile")
	var probe_right := Vector2i(w - 1, 4)
	var right_expected: Vector2i = DungeonGeometry.wall_atlas_for(w - 1, 4, w, DungeonGeometry.CELL_TILES)
	_check(tilemap.get_cell_source_id(1, probe_right) == DungeonGeometry.WALL_SOURCE_ID
			and tilemap.get_cell_atlas_coords(1, probe_right) == right_expected,
			"right-side edge maps to the per-side wall right tile")

	# ── Interior: no wall tile; tinted fill on layer 0 ──
	var inner := Vector2i(4, 4)
	_check(tilemap.get_cell_source_id(1, inner) == -1,
			"zone interior has no wall tile")
	_check(tilemap.get_cell_source_id(0, inner) == DungeonGeometry.FLOOR_SOURCE_ID,
			"zone interior uses the plank fill source")
	_check(tilemap.get_cell_atlas_coords(0, inner) == Vector2i(0, 0),
			"interior fill uses the sheet-order variant (4 mod 2, 4 mod 2)")
	_check(tilemap.get_cell_alternative_tile(0, inner) == DungeonGeometry.FLOOR_ALT_START,
			"START interior carries its tinted floor alternative")
	var inner_combat := Vector2i(DungeonGeometry.CELL_TILES + 4, 4)
	_check(tilemap.get_cell_alternative_tile(0, inner_combat) == 0,
			"COMBAT interior keeps the untinted base fill tile")

	# ── Trim ring corner: baseboard tile from the wall sheet ──
	var trim := Vector2i(1, 1)
	_check(tilemap.get_cell_source_id(0, trim) == DungeonGeometry.WALL_SOURCE_ID
			and tilemap.get_cell_atlas_coords(0, trim) == DungeonGeometry.FLOOR_EDGE_TL,
			"trim-ring corner uses the baseboard TL tile")
	var trim_edge := Vector2i(3, 1)
	_check(tilemap.get_cell_source_id(0, trim_edge) == DungeonGeometry.FLOOR_SOURCE_ID,
			"trim-ring straight edge falls back to plain tinted fill")

	# ── Determinism ──
	var tilemap_b := TileMap.new()
	gen._render_layout(layout, tilemap_b)
	var det_ok := true
	for probe in [probe_tl, probe_top, probe_right, inner, inner_combat, trim]:
		if tilemap.get_cell_source_id(1, probe) != tilemap_b.get_cell_source_id(1, probe) \
				or tilemap.get_cell_atlas_coords(1, probe) \
					!= tilemap_b.get_cell_atlas_coords(1, probe):
			det_ok = false
	_check(det_ok, "ring and interior placement is deterministic re-render")

	gen.free()
	tilemap.free()
	tilemap_b.free()

	# ── Summary ──
	if _fails == 0:
		print("ALL ASSERT_PLANK_FLOOR CHECKS PASSED")
		quit(0)
	else:
		print("ASSERT_PLANK_FLOOR: %d check(s) failed" % _fails)
		quit(1)
