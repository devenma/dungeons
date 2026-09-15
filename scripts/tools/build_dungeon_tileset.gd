extends SceneTree

## One-off authoring tool for the prebuilt dungeon TileSet resource.
##
## Constructs res://tilesets/dungeons_v2.tres headlessly and reproducibly:
##   Source 0 — Background_min_all_v2_FIXED.png (320x320, 10x10 @32px grid):
##     - Wall ring tiles (corners + one straight tile per side) get a
##       full-tile physics polygon (layer 0, collision_layer = 1).
##     - Floor strip variants (4,4)/(4,5) — no collision — with modulate
##       alternatives (author order):
##       alt 1 START green tint, alt 2 REWARD gold, alt 3 EXIT red,
##       alt 4 DOOR_CLOSED dark tint (open door = plain base tile, alt 0).
## Keep this script in the repo — it documents how the .tres was produced
## and stays compatible with later edits.
## Run: godot --headless -s scripts/tools/build_dungeon_tileset.gd

const SHEET_PATH := "res://assets/Examples/Background_min_all_v2_FIXED.png"

# Wall ring tiles (full-tile collision). Corners + one straight per side.
const WALL_RING_TILES: Array[Vector2i] = [
	Vector2i(4, 0), Vector2i(5, 0), Vector2i(6, 0),   # TL / top / TR
	Vector2i(4, 1), Vector2i(6, 1),                   # left / right
	Vector2i(4, 2), Vector2i(5, 2), Vector2i(6, 2),   # BL / bottom / BR
]

# Floor strip variants (no collision, alternative tints).
const FLOOR_TILES: Array[Vector2i] = [
	Vector2i(4, 4), Vector2i(4, 5),
]

# Full-tile collision polygon, tile-space (32px tile centered on origin).
# PackedVector2Array(...) is not a const expression in Godot 4.7, so a static var.
static var FULL_TILE_POLYGON: PackedVector2Array = PackedVector2Array([
	Vector2(-16, -16), Vector2(16, -16),
	Vector2(16, 16), Vector2(-16, 16),
])


func _init() -> void:
	quit(_build())


func _build() -> int:
	var dir_err: Error = _ensure_dir()
	if dir_err != OK:
		push_error("FAILED: cannot create tilesets/ directory (err=%d)" % dir_err)
		return 1

	var ts: TileSet = TileSet.new()
	ts.tile_size = Vector2i(DungeonGeometry.TILE_SIZE, DungeonGeometry.TILE_SIZE)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1)

	# ── Source 0: unified dungeon sheet (walls + floor) ──
	var src: TileSetAtlasSource = TileSetAtlasSource.new()
	var texture: Texture2D = load(SHEET_PATH)
	if texture == null:
		push_error("FAILED: cannot load dungeon sheet " + SHEET_PATH)
		return 1
	src.texture = texture
	src.texture_region_size = Vector2i(DungeonGeometry.TILE_SIZE, DungeonGeometry.TILE_SIZE)
	# The source MUST be added to the TileSet BEFORE TileData is touched,
	# so each tile sees the TileSet's physics layers (layer-insertion sync).
	ts.add_source(src, DungeonGeometry.DUNGEON_SOURCE_ID)

	for coords in WALL_RING_TILES:
		src.create_tile(coords)
		var td: TileData = src.get_tile_data(coords, 0)
		td.set_collision_polygons_count(0, 1)
		td.set_collision_polygon_points(0, 0, FULL_TILE_POLYGON)

	for coords in FLOOR_TILES:
		var tile_err: int = _author_floor_tile(src, coords)
		if tile_err != 0:
			return tile_err

	# ── Save ──
	var save_err: Error = ResourceSaver.save(ts, DungeonGeometry.DUNGEON_TILESET_PATH)
	if save_err != OK:
		push_error("FAILED: ResourceSaver.save err=%d for %s" % [save_err, DungeonGeometry.DUNGEON_TILESET_PATH])
		return 1

	print("OK: authored %s (%d sources, tile_size=%s, %d wall tiles, %d floor tiles)"
			% [DungeonGeometry.DUNGEON_TILESET_PATH, ts.get_source_count(),
			str(ts.tile_size), WALL_RING_TILES.size(), FLOOR_TILES.size()])
	return 0


## Creates a plain-floor tile plus its four tinted alternatives, verifying
## that the returned alternative ids match the DungeonGeometry contract.
func _author_floor_tile(src: TileSetAtlasSource, coords: Vector2i) -> int:
	src.create_tile(coords)

	# Author order maps 1:1 to the DungeonGeometry alternative constants.
	var alt_start: int = src.create_alternative_tile(coords)
	var alt_reward: int = src.create_alternative_tile(coords)
	var alt_exit: int = src.create_alternative_tile(coords)
	var alt_door: int = src.create_alternative_tile(coords)
	if alt_start != DungeonGeometry.FLOOR_ALT_START \
			or alt_reward != DungeonGeometry.FLOOR_ALT_REWARD \
			or alt_exit != DungeonGeometry.FLOOR_ALT_EXIT \
			or alt_door != DungeonGeometry.DOOR_CLOSED_ALT:
		push_error("FAILED: alternative ids drifted from DungeonGeometry contract at floor tile %s" % str(coords))
		return 1

	src.get_tile_data(coords, alt_start).modulate = DungeonGeometry.FLOOR_TINT_START
	src.get_tile_data(coords, alt_reward).modulate = DungeonGeometry.FLOOR_TINT_REWARD
	src.get_tile_data(coords, alt_exit).modulate = DungeonGeometry.FLOOR_TINT_EXIT
	var door_td: TileData = src.get_tile_data(coords, alt_door)
	door_td.modulate = DungeonGeometry.DOOR_TINT_CLOSED
	# Alternative tiles do NOT inherit the base tile's physics — the closed
	# door must carry its own blocking polygon explicitly.
	door_td.set_collision_polygons_count(0, 1)
	door_td.set_collision_polygon_points(0, 0, FULL_TILE_POLYGON)

	# Base variant (alt 0) must stay untinted: it doubles as the plain floor
	# AND the open-door look.
	var base_td: TileData = src.get_tile_data(coords, DungeonGeometry.DOOR_OPEN_ALT)
	if base_td.modulate != Color(1, 1, 1):
		push_error("FAILED: floor base tile modulate is not plain white at %s" % str(coords))
		return 1
	return 0


## Makes sure res://tilesets/ exists so the first run does not fail on save.
func _ensure_dir() -> int:
	var da: DirAccess = DirAccess.open("res://")
	if da == null:
		return FAILED
	if not da.dir_exists("tilesets") and da.make_dir("tilesets") != OK:
		return FAILED
	return OK
