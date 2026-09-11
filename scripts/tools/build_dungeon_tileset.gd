extends SceneTree

## One-off authoring tool for the prebuilt dungeon TileSet resource.
##
## Constructs res://tilesets/dungeon.tres headlessly and reproducibly from
## the source sheets, baking collision and TileData.modulate alternatives:
##   Source 0 — Wall_Floor_min_v2.png (4x4 @32px): outer 12 wall tiles get a
##     full-tile physics polygon (layer 0, collision_layer = 1); inner 2x2
##     floor-edge trim tiles have no collision.
##   Source 1 — Plank_Floor_min.png (v1, 2x2 @32px): plain floor fill, no
##     collision, no baseboard. Alternatives (author order):
##     alt 1 START green tint, alt 2 REWARD gold, alt 3 EXIT red,
##     alt 4 DOOR_CLOSED dark tint (open door = plain base tile, alt 0).
## Keep this script in the repo — it documents how the .tres was produced
## and stays compatible with later edits.
## Run: godot --headless -s scripts/tools/build_dungeon_tileset.gd

const WALL_SHEET_PATH := "res://assets/Examples/Wall_Floor_min_v2.png"
const FILL_SHEET_PATH := "res://assets/Examples/Plank_Floor_min.png"

const WALL_GRID := Vector2i(4, 4)
const FILL_GRID := Vector2i(2, 2)

# Wall-sheet tiles WITHOUT collision (floor-edge trim w/ baseboard).
const WALL_INTERIOR := [
	Vector2i(1, 1), Vector2i(2, 1),
	Vector2i(1, 2), Vector2i(2, 2),
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

	# ── Source 0: wall sheet (walls + floor-edge trim) ──
	var wall_src: TileSetAtlasSource = TileSetAtlasSource.new()
	var wall_texture: Texture2D = load(WALL_SHEET_PATH)
	if wall_texture == null:
		push_error("FAILED: cannot load wall sheet " + WALL_SHEET_PATH)
		return 1
	wall_src.texture = wall_texture
	wall_src.texture_region_size = Vector2i(DungeonGeometry.TILE_SIZE, DungeonGeometry.TILE_SIZE)
	# The source MUST be added to the TileSet BEFORE TileData is touched,
	# so each tile sees the TileSet's physics layers (layer-insertion sync).
	ts.add_source(wall_src, DungeonGeometry.WALL_SOURCE_ID)
	for gy in range(0, WALL_GRID.y):
		for gx in range(0, WALL_GRID.x):
			var coords: Vector2i = Vector2i(gx, gy)
			wall_src.create_tile(coords)
			if WALL_INTERIOR.has(coords):
				continue
			var td: TileData = wall_src.get_tile_data(coords, 0)
			td.set_collision_polygons_count(0, 1)
			td.set_collision_polygon_points(0, 0, FULL_TILE_POLYGON)

	# ── Source 1: plain plank fill (v1) + modulate alternatives ──
	var fill_src: TileSetAtlasSource = TileSetAtlasSource.new()
	var fill_texture: Texture2D = load(FILL_SHEET_PATH)
	if fill_texture == null:
		push_error("FAILED: cannot load fill sheet " + FILL_SHEET_PATH)
		return 1
	fill_src.texture = fill_texture
	fill_src.texture_region_size = Vector2i(DungeonGeometry.TILE_SIZE, DungeonGeometry.TILE_SIZE)
	ts.add_source(fill_src, DungeonGeometry.FLOOR_SOURCE_ID)
	for gy in range(0, FILL_GRID.y):
		for gx in range(0, FILL_GRID.x):
			var tile_err: int = _author_fill_tile(fill_src, Vector2i(gx, gy))
			if tile_err != 0:
				return tile_err

	# ── Save ──
	var save_err: Error = ResourceSaver.save(ts, DungeonGeometry.DUNGEON_TILESET_PATH)
	if save_err != OK:
		push_error("FAILED: ResourceSaver.save err=%d for %s" % [save_err, DungeonGeometry.DUNGEON_TILESET_PATH])
		return 1

	print("OK: authored %s (%d sources, tile_size=%s)"
			% [DungeonGeometry.DUNGEON_TILESET_PATH, ts.get_source_count(), str(ts.tile_size)])
	return 0


## Creates the plain-fill tile plus its four tinted alternatives, verifying
## that the returned alternative ids match the DungeonGeometry contract.
func _author_fill_tile(fill_src: TileSetAtlasSource, coords: Vector2i) -> int:
	fill_src.create_tile(coords)

	# Author order maps 1:1 to the DungeonGeometry alternative constants.
	var alt_start: int = fill_src.create_alternative_tile(coords)
	var alt_reward: int = fill_src.create_alternative_tile(coords)
	var alt_exit: int = fill_src.create_alternative_tile(coords)
	var alt_door: int = fill_src.create_alternative_tile(coords)
	if alt_start != DungeonGeometry.FLOOR_ALT_START \
			or alt_reward != DungeonGeometry.FLOOR_ALT_REWARD \
			or alt_exit != DungeonGeometry.FLOOR_ALT_EXIT \
			or alt_door != DungeonGeometry.DOOR_CLOSED_ALT:
		push_error("FAILED: alternative ids drifted from DungeonGeometry contract at fill tile %s" % str(coords))
		return 1

	fill_src.get_tile_data(coords, alt_start).modulate = DungeonGeometry.FLOOR_TINT_START
	fill_src.get_tile_data(coords, alt_reward).modulate = DungeonGeometry.FLOOR_TINT_REWARD
	fill_src.get_tile_data(coords, alt_exit).modulate = DungeonGeometry.FLOOR_TINT_EXIT
	fill_src.get_tile_data(coords, alt_door).modulate = DungeonGeometry.DOOR_TINT_CLOSED

	# Base variant (alt 0) must stay untinted: it doubles as the plain floor
	# AND the open-door look.
	var base_td: TileData = fill_src.get_tile_data(coords, DungeonGeometry.DOOR_OPEN_ALT)
	if base_td.modulate != Color(1, 1, 1):
		push_error("FAILED: fill base tile modulate is not plain white at %s" % str(coords))
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
