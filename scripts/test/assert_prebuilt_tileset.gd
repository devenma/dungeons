extends SceneTree

## Runtime assertions for the prebuilt dungeon TileSet resource:
##   1. dungeons_v2.tres loads, is a TileSet, tile_size 32x32, exactly 1
##      atlas source (Background_min_all_v2_FIXED.png).
##   2. All 8 wall-ring role tiles exist at the DungeonGeometry frozen
##      coords and carry one full-tile collision polygon on physics layer 0.
##   3. Floor strip variants (4,4)/(4,5) — no collision — with tint
##      alternatives START green / REWARD gold / EXIT red / DOOR_CLOSED dark;
##      base (alt 0 = DOOR_OPEN) stays white.
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
	_check(ts.get_source_count() == 1, "tileset has exactly 1 source")

	var src_any: TileSetSource = ts.get_source(DungeonGeometry.DUNGEON_SOURCE_ID)
	var atlas_src := src_any as TileSetAtlasSource
	_check(src_any != null, "source 0 exists")
	if atlas_src == null:
		push_error("FATAL: source 0 is not an atlas source")
		_fails += 1
		return

	# ── Check 2: unified sheet (walls + floor) ──
	var texture: Texture2D = atlas_src.texture
	_check(texture != null and texture.get_width() == 320
			and texture.get_height() == 320,
			"source uses the 320x320 v2 dungeon sheet")

	var wall_roles: Array[Vector2i] = [
		DungeonGeometry.WALL_CORNER_TL, DungeonGeometry.WALL_TOP,
		DungeonGeometry.WALL_CORNER_TR, DungeonGeometry.WALL_LEFT,
		DungeonGeometry.WALL_RIGHT, DungeonGeometry.WALL_CORNER_BL,
		DungeonGeometry.WALL_BOTTOM, DungeonGeometry.WALL_CORNER_BR,
	]
	_check(_all_tiles_present(atlas_src, wall_roles),
			"all 8 frozen wall-role tiles exist at their coords")
	var wall_coll_ok := true
	for coords in wall_roles:
		var td: TileData = atlas_src.get_tile_data(coords, 0)
		if td == null or td.get_collision_polygons_count(0) != 1 \
				or td.get_collision_polygon_points(0, 0).size() != 4:
			wall_coll_ok = false
	_check(wall_coll_ok, "all 8 wall tiles have one full-tile collision polygon")

	# ── Check 3: floor strip variants + alternatives ──
	var floor_roles: Array[Vector2i] = [
		DungeonGeometry.FLOOR_VARIANT_A, DungeonGeometry.FLOOR_VARIANT_B,
	]
	_check(_all_tiles_present(atlas_src, floor_roles),
			"both floor strip variants exist")
	var floor_coll_ok := true
	for coords in floor_roles:
		var td2: TileData = atlas_src.get_tile_data(coords, 0)
		if td2 == null or td2.get_collision_polygons_count(0) != 0:
			floor_coll_ok = false
	_check(floor_coll_ok, "floor variants have no collision")

	var alts_ok := true
	var mods_ok := true
	for coords in floor_roles:
		if not atlas_src.has_alternative_tile(coords, DungeonGeometry.FLOOR_ALT_START) \
				or not atlas_src.has_alternative_tile(coords, DungeonGeometry.FLOOR_ALT_REWARD) \
				or not atlas_src.has_alternative_tile(coords, DungeonGeometry.FLOOR_ALT_EXIT) \
				or not atlas_src.has_alternative_tile(coords, DungeonGeometry.DOOR_CLOSED_ALT):
			alts_ok = false
		else:
			if atlas_src.get_tile_data(coords, DungeonGeometry.FLOOR_ALT_START).modulate \
					!= DungeonGeometry.FLOOR_TINT_START:
				mods_ok = false
			if atlas_src.get_tile_data(coords, DungeonGeometry.FLOOR_ALT_REWARD).modulate \
					!= DungeonGeometry.FLOOR_TINT_REWARD:
				mods_ok = false
			if atlas_src.get_tile_data(coords, DungeonGeometry.FLOOR_ALT_EXIT).modulate \
					!= DungeonGeometry.FLOOR_TINT_EXIT:
				mods_ok = false
			if atlas_src.get_tile_data(coords, DungeonGeometry.DOOR_CLOSED_ALT).modulate \
					!= DungeonGeometry.DOOR_TINT_CLOSED:
				mods_ok = false
	_check(alts_ok, "alt 1/2/3/4 (START/REWARD/EXIT/DOOR_CLOSED) exist on every floor tile")
	_check(mods_ok, "alternative tints round-trip and match DungeonGeometry constants")

	# ── Check 4: closed-door alternative carries its own blocking collision ──
	# Alternative tiles do not inherit the base tile's physics; the lock-on-
	# entry door model relies on the dark alternative blocking the player.
	var door_coll_ok := true
	for coords in floor_roles:
		var td3: TileData = atlas_src.get_tile_data(coords, DungeonGeometry.DOOR_CLOSED_ALT)
		if td3 == null or td3.get_collision_polygons_count(0) != 1 \
				or td3.get_collision_polygon_points(0, 0).size() != 4:
			door_coll_ok = false
	_check(door_coll_ok, "DOOR_CLOSED alternative has one full-tile collision polygon")

	var open_td: TileData = atlas_src.get_tile_data(DungeonGeometry.DOOR_FILL_ATLAS,
			DungeonGeometry.DOOR_OPEN_ALT)
	_check(open_td != null and open_td.modulate == Color(1, 1, 1),
			"door-open variant is the plain (white) floor tile")


func _all_tiles_present(src: TileSetAtlasSource, coords_list: Array[Vector2i]) -> bool:
	var present := true
	for coords in coords_list:
		if not src.has_tile(coords):
			present = false
	return present
