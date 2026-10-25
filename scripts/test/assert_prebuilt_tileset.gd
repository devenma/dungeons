extends SceneTree

## Runtime assertions for the prebuilt dungeon TileSet resource (tilesets/crypt_dark.tres):
##   1. Loads, is a TileSet, tile_size 32x32, exactly 1 atlas source (crypt_tiles.png, 12x18 tiles).
##   2. Every tile role DungeonGeometry names exists in the atlas (each periodic slot too).
##   3. Collision follows DungeonGeometry.is_solid_atlas: walls carry one full-tile polygon on the
##      WORLD physics layer; the stairs carry only their frame (top and sides, south open); floor,
##      door gaps, passages and the locked-arch overlay carry none.
## Run: godot --headless -s scripts/test/assert_prebuilt_tileset.gd
## Exit 0 on pass; nonzero + push_error on failure.

const FULL_TILE: PackedVector2Array = [Vector2(-16, -16), Vector2(16, -16), Vector2(16, 16), Vector2(-16, 16)]

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


## Every atlas coordinate a role constant can produce, slots included.
func _role_tiles() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for mask in 16:
		for j in 3:
			for i in 3:
				tiles.append(DungeonGeometry.floor_atlas_for(i, j, mask))
	for slot in 3:
		for family: Vector2i in [DungeonGeometry.WALL_TOP, DungeonGeometry.FACE_HI, DungeonGeometry.FACE_LO,
				DungeonGeometry.WALL_LEFT, DungeonGeometry.WALL_RIGHT, DungeonGeometry.WALL_BOTTOM,
				DungeonGeometry.WALL_BOTTOM_INNER, DungeonGeometry.WALL_LEFT_BELOW_DOOR,
				DungeonGeometry.WALL_RIGHT_BELOW_DOOR]:
			tiles.append(family + Vector2i(slot, 0))
		for j in 3:
			tiles.append(DungeonGeometry.PASSAGE_N + Vector2i(slot, j))
	for j in DungeonGeometry.STAIRS_DOWN_SIZE.y:
		for i in DungeonGeometry.STAIRS_DOWN_SIZE.x:
			tiles.append(DungeonGeometry.STAIRS_DOWN + Vector2i(i, j))
	tiles.append_array([DungeonGeometry.WALL_CORNER_TL, DungeonGeometry.WALL_CORNER_TR,
			DungeonGeometry.WALL_CORNER_BL, DungeonGeometry.WALL_CORNER_BR,
			DungeonGeometry.WALL_CORNER_BL_INNER, DungeonGeometry.WALL_CORNER_BR_INNER,
			DungeonGeometry.DOOR_N_HI, DungeonGeometry.DOOR_N_LO, DungeonGeometry.DOOR_E,
			DungeonGeometry.DOOR_W, DungeonGeometry.DOOR_N_HI_LOCKED, DungeonGeometry.DOOR_N_LO_LOCKED])
	return tiles


func _run_checks() -> void:
	var ts: TileSet = load(DungeonGeometry.DUNGEON_TILESET_PATH)
	if ts == null:
		push_error("FATAL: cannot load " + DungeonGeometry.DUNGEON_TILESET_PATH)
		_fails += 1
		return
	_check(ts.tile_size == Vector2i(DungeonGeometry.TILE_SIZE, DungeonGeometry.TILE_SIZE),
			"tile_size is 32x32")
	_check(ts.get_source_count() == 1, "tileset has exactly 1 source")
	_check(ts.get_physics_layers_count() == 1
			and ts.get_physics_layer_collision_layer(0) == CollisionLayers.WORLD,
			"one physics layer, on the WORLD collision bit")
	var atlas_src: TileSetAtlasSource = ts.get_source(DungeonGeometry.DUNGEON_SOURCE_ID) as TileSetAtlasSource
	if atlas_src == null:
		push_error("FATAL: source %d is not an atlas source" % DungeonGeometry.DUNGEON_SOURCE_ID)
		_fails += 1
		return
	_check(atlas_src.texture != null and atlas_src.texture.get_size() == Vector2(384, 576),
			"source uses the 384x576 crypt atlas (12x18 tiles)")

	var missing: Array[Vector2i] = []
	for coords in _role_tiles():
		if not atlas_src.has_tile(coords):
			missing.append(coords)
	_check(missing.is_empty(), "every DungeonGeometry role tile exists (missing: %s)" % [missing])

	var wrong: Array[Vector2i] = []
	var solid: int = 0
	for i in atlas_src.get_tiles_count():
		var coords: Vector2i = atlas_src.get_tile_id(i)
		var td: TileData = atlas_src.get_tile_data(coords, 0)
		if DungeonGeometry.is_solid_atlas(coords):
			solid += 1
			if td.get_collision_polygons_count(0) != 1 \
					or td.get_collision_polygon_points(0, 0) != FULL_TILE:
				wrong.append(coords)
		elif td.get_collision_polygons_count(0) != DungeonGeometry.stairs_frame_rects(coords).size():
			wrong.append(coords)
	_check(wrong.is_empty(),
			"walls block their full tile, the stairs their frame, everything else is walkable (wrong: %s)" % [wrong])
	# Marco de la escalera: arriba y lados bloqueados, sur abierto / Stairs frame: top and sides blocked, south open
	var frame: Array[String] = []
	var half: Vector2 = Vector2.ONE * DungeonGeometry.TILE_SIZE / 2.0
	for j in DungeonGeometry.STAIRS_DOWN_SIZE.y:
		for i in DungeonGeometry.STAIRS_DOWN_SIZE.x:
			var coords: Vector2i = DungeonGeometry.STAIRS_DOWN + Vector2i(i, j)
			if not atlas_src.has_tile(coords):
				continue
			var td: TileData = atlas_src.get_tile_data(coords, 0)
			var covered: Rect2 = Rect2()
			for polygon in td.get_collision_polygons_count(0):
				var points: PackedVector2Array = td.get_collision_polygon_points(0, polygon)
				var box: Rect2 = Rect2(points[0] + half, Vector2.ZERO)
				for point: Vector2 in points:
					box = box.expand(point + half)
				covered = box if polygon == 0 else covered.merge(box)
			var tile: float = DungeonGeometry.TILE_SIZE
			if j == 0 and covered.position.y > 0.0:
				frame.append("%s top open" % coords)
			if i == 0 and covered.position.x > 0.0:
				frame.append("%s west open" % coords)
			if i == DungeonGeometry.STAIRS_DOWN_SIZE.x - 1 and covered.end.x < tile:
				frame.append("%s east open" % coords)
			if j == DungeonGeometry.STAIRS_DOWN_SIZE.y - 1 and covered.end.y >= tile 					and covered.size.x >= tile:
				frame.append("%s south blocked" % coords)
	_check(frame.is_empty(), "stairs block their top and sides and leave the south open (%s)" % [frame])
	_check(solid == 33, "33 wall tiles carry collision (got %d)" % solid)
