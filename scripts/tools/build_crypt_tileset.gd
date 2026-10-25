extends SceneTree

## Genera tilesets/crypt_dark.tres con el atlas de assets/art/environment/crypt/crypt_tiles.png.
## Builds tilesets/crypt_dark.tres from the atlas assets/art/environment/crypt/crypt_tiles.png.
## Las paredes (DungeonGeometry.is_solid_atlas) bloquean su tile completo: la cara norte frena los
## pies en el borde del piso y los topes laterales y sur ocupan su tile.
## Walls (DungeonGeometry.is_solid_atlas) block their full tile: the north face stops the feet at the
## floor edge and the side and south tops fill their tile.
## Re-ejecutar si cambia el layout del atlas; no editar el .tres a mano.
## Rerun when the atlas layout changes; do not hand-edit the .tres.
##   "$GODOT" --headless --path . -s scripts/tools/build_crypt_tileset.gd

const Geometry: GDScript = preload("res://scripts/dungeon/dungeon_geometry.gd")
const ATLAS_PATH: String = "res://assets/art/environment/crypt/crypt_tiles.png"
# Capa de colisión de las paredes; igual a CollisionLayers.WORLD / Wall collision layer; equals CollisionLayers.WORLD
const WORLD_LAYER: int = 1


func _initialize() -> void:
	var tile_set: TileSet = TileSet.new()
	tile_set.tile_size = Vector2i(Geometry.TILE_SIZE, Geometry.TILE_SIZE)
	tile_set.add_physics_layer()
	tile_set.set_physics_layer_collision_layer(0, WORLD_LAYER)
	var half: float = Geometry.TILE_SIZE / 2.0
	var full_rect: PackedVector2Array = PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)])
	var source: TileSetAtlasSource = TileSetAtlasSource.new()
	source.texture = load(ATLAS_PATH)
	source.texture_region_size = tile_set.tile_size
	tile_set.add_source(source, Geometry.DUNGEON_SOURCE_ID)
	var grid: Vector2i = source.get_atlas_grid_size()
	var image: Image = source.texture.get_image()
	var tiles: int = 0
	for y: int in grid.y:
		for x: int in grid.x:
			var coords: Vector2i = Vector2i(x, y)
			if image.get_region(Rect2i(coords * Geometry.TILE_SIZE, tile_set.tile_size)).is_invisible():
				continue
			source.create_tile(coords)
			tiles += 1
			if Geometry.is_solid_atlas(coords):
				var tile_data: TileData = source.get_tile_data(coords, 0)
				tile_data.add_collision_polygon(0)
				tile_data.set_collision_polygon_points(0, 0, full_rect)
	var err: Error = ResourceSaver.save(tile_set, Geometry.DUNGEON_TILESET_PATH)
	print("saved %s (%d tiles): %s" % [Geometry.DUNGEON_TILESET_PATH, tiles, error_string(err)])
	quit(0 if err == OK else 1)
