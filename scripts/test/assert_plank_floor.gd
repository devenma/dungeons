extends SceneTree

# Runtime assertions for the plank floor + Wall_Floor template wall rings:
#   1. Floor atlas: the Plank_Floor sheet at FLOOR_PATCH_SCALE sliced into
#      variant_count² tiles; tinted alternatives for START/REWARD/EXIT.
#   2. Wall atlas: the Wall_Floor_min_v2 room template scaled, fully sliced,
#      every tile with full collision.
#   3. Zones render their wall ring INSIDE their tile_rect: ring tiles on
#      layer 1 at borders (corners + edges), no layer-1 tile in the interior.
#   4. Ring placement is deterministic per zone.
# Run: godot --headless -s scripts/test/assert_plank_floor.gd

var _fails: int = 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		_fails += 1
		print("VERIFY_FAIL: " + msg)


func _init() -> void:
	var gen: Node = load("res://scripts/dungeon/dungeon_generator.gd").new()
	var scale: int = DungeonGenerator.FLOOR_PATCH_SCALE
	var ring: int = DungeonGenerator.WALL_RING_TILES
	var tpl_tiles: int = DungeonGenerator.WALL_TEMPLATE_TILES

	# ── Tileset build (same path _render_layout uses) ──
	var build: Dictionary = gen._build_tileset()
	var floor_src_id: int = build["floor_src_id"]
	var variant_count: int = build["floor_variant_count"]
	var floor_alt_ids: Dictionary = build["floor_alt_ids"]
	var wall_src_id: int = build["wall_src_id"]

	var ts: TileSet = build["tileset"]
	var floor_src: TileSetAtlasSource = ts.get_source(floor_src_id)
	var wall_src: TileSetAtlasSource = ts.get_source(wall_src_id)

	# ── Check 1: floor sheet sliced at FLOOR_PATCH_SCALE ──
	_check(floor_src.texture != null and floor_src.texture.get_width()
			== 64 * scale and floor_src.texture.get_height() == 64 * scale,
		"floor texture is the sheet upscaled to match FLOOR_PATCH_SCALE")
	_check(variant_count == 4 * scale,
		"floor variant grid spans 64*S/TILE tiles per side")
	var floor_tiles_ok := true
	for vy in variant_count:
		for vx in variant_count:
			if not floor_src.has_tile(Vector2i(vx, vy)):
				floor_tiles_ok = false
	_check(floor_tiles_ok, "every floor variant coordinate has a base tile")

	# ── Check 2: wall template source fully sliced + collisions ──
	_check(wall_src.texture != null and wall_src.texture.get_width()
			== tpl_tiles * 16,
		"wall template texture spans WALL_TEMPLATE_TILES tiles")
	var wall_tiles_ok := true
	var wall_coll_ok := true
	for vy in tpl_tiles:
		for vx in tpl_tiles:
			var coords := Vector2i(vx, vy)
			if not wall_src.has_tile(coords):
				wall_tiles_ok = false
				continue
			var td: TileData = wall_src.get_tile_data(coords, 0)
			if td == null or td.get_collision_polygons_count(0) != 1:
				wall_coll_ok = false
	_check(wall_tiles_ok, "every wall-template coordinate has a tile")
	_check(wall_coll_ok, "every wall-template tile has full collision")

	# ── Check 3: floor tinted alternatives per zone type ──
	_check(not floor_alt_ids.has(Zone.ZoneType.COMBAT),
		"COMBAT has no tinted alternatives (uses base tile)")
	var alts_ok := true
	for type_idx in [Zone.ZoneType.START, Zone.ZoneType.REWARD, Zone.ZoneType.EXIT]:
		if not floor_alt_ids.has(type_idx):
			alts_ok = false
			continue
		var per_variant: Dictionary = floor_alt_ids[type_idx]
		if per_variant.size() != variant_count * variant_count:
			alts_ok = false
	_check(alts_ok, "START/REWARD/EXIT have tinted alternatives for all variants")

	# ── Minimal layout: START (left) + COMBAT (right), 2×1 grid, 32-tile cells ──
	var z0: Zone = Zone.new()
	z0.id = 0
	z0.type = Zone.ZoneType.START
	z0.cell_min = Vector2i(0, 0)
	z0.cell_max = Vector2i(1, 1)
	z0.tile_rect = Rect2i(0, 0, 32, 32)

	var z1: Zone = Zone.new()
	z1.id = 1
	z1.type = Zone.ZoneType.COMBAT
	z1.cell_min = Vector2i(1, 0)
	z1.cell_max = Vector2i(2, 1)
	z1.tile_rect = Rect2i(32, 0, 32, 32)
	z1.neighbors.append(0)
	z0.neighbors.append(1)

	var layout: DungeonGenerator.FloorLayout = DungeonGenerator.FloorLayout.new()
	layout.floor_number = 1
	layout.floor_seed = 12345
	layout.grid_w = 2
	layout.grid_h = 1
	layout.zones = [z0, z1]
	layout.doors = []

	# ── Real render ──
	var tilemap := TileMap.new()
	var door_src_id: int = gen._render_layout(layout, tilemap)
	_check(door_src_id >= 0, "render returns a valid door source id")

	# ── Check 4: ring tiles at borders, none in the interior ──
	var tl: int = tilemap.get_cell_source_id(1, Vector2i(0, 0))
	var tl_coords: Vector2i = tilemap.get_cell_atlas_coords(1, Vector2i(0, 0))
	_check(tl == wall_src_id and tl_coords == Vector2i(0, 0),
		"zone corner maps to the template's TL corner tile")

	var top_mid := Vector2i(10, 0)
	var top_src: int = tilemap.get_cell_source_id(1, top_mid)
	var top_coords: Vector2i = tilemap.get_cell_atlas_coords(1, top_mid)
	var top_expected := Vector2i(ring + (10 - ring) % (tpl_tiles - 2 * ring), 0)
	_check(top_src == wall_src_id and top_coords == top_expected,
		"top-edge interior maps to the template's edge band")

	var inner := Vector2i(16, 16)
	_check(tilemap.get_cell_source_id(1, inner) == -1,
		"zone interior has no wall tile")
	var inner_floor_coords: Vector2i = tilemap.get_cell_atlas_coords(0, inner)
	_check(inner_floor_coords == Vector2i(16 % variant_count, 16 % variant_count)
			and tilemap.get_cell_source_id(0, inner) == floor_src_id,
		"zone interior uses sheet-order plank floor")
	var inner_alt: int = tilemap.get_cell_alternative_tile(0, inner)
	_check(inner_alt == int(floor_alt_ids[Zone.ZoneType.START][Vector2i(4, 4)]),
		"START interior carries its tinted floor alternative")

	var max_edge := Vector2i(31, 16)
	var max_coords: Vector2i = tilemap.get_cell_atlas_coords(1, max_edge)
	_check(tilemap.get_cell_source_id(1, max_edge) == wall_src_id
			and max_coords == Vector2i(tpl_tiles - 1,
				ring + (16 - ring) % (tpl_tiles - 2 * ring)),
		"max-side edge maps to the template's right/inner band")

	var ring_coll: TileData = wall_src.get_tile_data(tl_coords, 0)
	_check(ring_coll.get_collision_polygons_count(0) == 1,
		"ring wall tiles keep full-tile collision")

	# ── Check 5: deterministic rendering ──
	var tilemap_b := TileMap.new()
	gen._render_layout(layout, tilemap_b)
	var det_ok := true
	for probe in [Vector2i(0, 0), top_mid, max_edge, inner]:
		if tilemap.get_cell_source_id(1, probe) != tilemap_b.get_cell_source_id(1, probe) \
				or tilemap.get_cell_atlas_coords(1, probe) \
					!= tilemap_b.get_cell_atlas_coords(1, probe):
			det_ok = false
	_check(det_ok, "ring and interior placement is deterministic")

	# ── Summary ──
	if _fails == 0:
		print("ALL ASSERT_PLANK_FLOOR CHECKS PASSED")
		quit(0)
	else:
		print("ASSERT_PLANK_FLOOR: %d check(s) failed" % _fails)
		quit(1)
