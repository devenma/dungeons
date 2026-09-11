extends SceneTree

## Runtime assertions for the prebuilt dungeon TileSet resource:
##   1. dungeon.tres loads, is a TileSet, tile_size 32x32, exactly 2 sources.
##   2. Wall source (id 0): wall sheet texture, all 16 role tiles present at
##      the DungeonGeometry frozen coords; the 12 wall tiles carry one
##      full-tile collision polygon on physics layer 0; the 4 interior
##      floor-edge trim tiles have none.
##   3. Floor source (id 1): v1 plank fill 64x64, 4 plain tiles without
##      collision; tint alternatives START green / REWARD gold / EXIT red;
##      DOOR_CLOSED dark alternative; base (alt 0 = DOOR_OPEN) stays white.
## Run: godot --headless -s scripts/test/assert_prebuilt_tileset.gd
## Exit 0 on pass; nonzero + push_error on failure.

var _fails: int = 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		_fails += 1
		print("VERIFY_FAIL: " + msg)


func _init() -> void:
	_run_checks()
	if _fails == 0:
		print("ALL ASSERT_PREBUILT_TILESET CHECKS PASSED")
		quit(0)
	else:
		push_error("ASSERT_PREBUILT_TILESET: %d check(s) failed" % _fails)
		quit(1)


func _run_checks() -> void:
	# ── Check 1: resource loads with the expected shape ──
	var ts: TileSet = load(DungeonGeometry.DUNGEON_TILESET_PATH)
	if ts == null:
		push_error("FATAL: cannot load " + DungeonGeometry.DUNGEON_TILESET_PATH)
		_fails += 1
		return
	_check(ts.tile_size == Vector2i(DungeonGeometry.TILE_SIZE, DungeonGeometry.TILE_SIZE),
			"tile_size is 32x32")
	_check(ts.get_source_count() == 2, "tileset has exactly 2 sources")

	var wall_src: TileSetAtlasSource = ts.get_source(DungeonGeometry.WALL_SOURCE_ID)
	var fill_src: TileSetAtlasSource = ts.get_source(DungeonGeometry.FLOOR_SOURCE_ID)
	_check(wall_src != null and fill_src != null, "sources 0 and 1 exist as atlas sources")

	# ── Check 2: wall sheet source (walls + floor-edge trim) ──
	var wall_texture: Texture2D = wall_src.texture
	_check(wall_texture != null and wall_texture.get_width() == 128
			and wall_texture.get_height() == 128,
			"wall source uses the 128x128 v2 wall sheet")
	var wall_roles: Array[Vector2i] = [
		DungeonGeometry.WALL_CORNER_TL, DungeonGeometry.WALL_CORNER_TR,
		DungeonGeometry.WALL_CORNER_BL, DungeonGeometry.WALL_CORNER_BR,
		DungeonGeometry.WALL_TOP_A, DungeonGeometry.WALL_TOP_B,
		DungeonGeometry.WALL_LEFT_A, DungeonGeometry.WALL_LEFT_B,
		DungeonGeometry.WALL_RIGHT_A, DungeonGeometry.WALL_RIGHT_B,
		DungeonGeometry.WALL_BOTTOM_A, DungeonGeometry.WALL_BOTTOM_B,
	]
	_check(_all_tiles_present(wall_src, wall_roles),
			"all 12 frozen wall-role tiles exist at their coords")
	var wall_coll_ok := true
	for coords in wall_roles:
		var td: TileData = wall_src.get_tile_data(coords, 0)
		if td == null or td.get_collision_polygons_count(0) != 1 \
				or td.get_collision_polygon_points(0, 0).size() != 4:
			wall_coll_ok = false
	_check(wall_coll_ok, "all 12 wall tiles have one full-tile collision polygon")

	var edge_roles: Array[Vector2i] = [
		DungeonGeometry.FLOOR_EDGE_TL, DungeonGeometry.FLOOR_EDGE_TR,
		DungeonGeometry.FLOOR_EDGE_BL, DungeonGeometry.FLOOR_EDGE_BR,
	]
	_check(_all_tiles_present(wall_src, edge_roles),
			"all 4 frozen floor-edge trim tiles exist")
	var edge_coll_ok := true
	for coords in edge_roles:
		var td: TileData = wall_src.get_tile_data(coords, 0)
		if td == null or td.get_collision_polygons_count(0) != 0:
			edge_coll_ok = false
	_check(edge_coll_ok, "floor-edge trim tiles have no collision")

	# ── Check 3: plain plank fill source + alternatives ──
	var fill_texture: Texture2D = fill_src.texture
	_check(fill_texture != null and fill_texture.get_width() == 64
			and fill_texture.get_height() == 64,
			"floor source uses the 64x64 v1 plank fill")
	var fill_tiles: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1),
	]
	_check(_all_tiles_present(fill_src, fill_tiles),
			"all 4 fill tiles exist (2x2 @32px)")
	var fill_coll_ok := true
	for coords in fill_tiles:
		var td: TileData = fill_src.get_tile_data(coords, 0)
		if td == null or td.get_collision_polygons_count(0) != 0:
			fill_coll_ok = false
	_check(fill_coll_ok, "fill tiles have no collision")

	var alts_ok := true
	var mods_ok := true
	for coords in fill_tiles:
		if not fill_src.has_alternative_tile(coords, DungeonGeometry.FLOOR_ALT_START) \
				or not fill_src.has_alternative_tile(coords, DungeonGeometry.FLOOR_ALT_REWARD) \
				or not fill_src.has_alternative_tile(coords, DungeonGeometry.FLOOR_ALT_EXIT) \
				or not fill_src.has_alternative_tile(coords, DungeonGeometry.DOOR_CLOSED_ALT):
			alts_ok = false
		else:
			if fill_src.get_tile_data(coords, DungeonGeometry.FLOOR_ALT_START).modulate \
					!= DungeonGeometry.FLOOR_TINT_START:
				mods_ok = false
			if fill_src.get_tile_data(coords, DungeonGeometry.FLOOR_ALT_REWARD).modulate \
					!= DungeonGeometry.FLOOR_TINT_REWARD:
				mods_ok = false
			if fill_src.get_tile_data(coords, DungeonGeometry.FLOOR_ALT_EXIT).modulate \
					!= DungeonGeometry.FLOOR_TINT_EXIT:
				mods_ok = false
			if fill_src.get_tile_data(coords, DungeonGeometry.DOOR_CLOSED_ALT).modulate \
					!= DungeonGeometry.DOOR_TINT_CLOSED:
				mods_ok = false
	_check(alts_ok, "alt 1/2/3/4 (START/REWARD/EXIT/DOOR_CLOSED) exist on every fill tile")
	_check(mods_ok, "alternative tints round-trip and match DungeonGeometry constants")

	# ── Check 4: closed-door variant carries its own blocking collision ──
	# Alternative tiles do not inherit the base tile's physics; the lock-on-
	# entry door model relies on the dark alternative blocking the player.
	var door_coll_ok := true
	for coords in fill_tiles:
		var td: TileData = fill_src.get_tile_data(coords, DungeonGeometry.DOOR_CLOSED_ALT)
		if td == null or td.get_collision_polygons_count(0) != 1 \
				or td.get_collision_polygon_points(0, 0).size() != 4:
			door_coll_ok = false
	_check(door_coll_ok, "DOOR_CLOSED alternative has one full-tile collision polygon")

	var open_td: TileData = fill_src.get_tile_data(DungeonGeometry.DOOR_FILL_ATLAS,
			DungeonGeometry.DOOR_OPEN_ALT)
	_check(open_td != null and open_td.modulate == Color(1, 1, 1),
			"door-open variant is the plain (white) fill tile")


func _all_tiles_present(src: TileSetAtlasSource, coords_list: Array[Vector2i]) -> bool:
	var present := true
	for coords in coords_list:
		if not src.has_tile(coords):
			present = false
	return present
