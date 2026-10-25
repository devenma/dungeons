extends SceneTree

## Genera tilesets/art_preview_crypt.tres con los PNG de assets/art/preview/crypt/ (un atlas por tile).
## Builds tilesets/art_preview_crypt.tres from the PNGs in assets/art/preview/crypt/ (one atlas per tile).
## Solo escribe su propio .tres; no toca el tileset del juego. / Writes only its own .tres; does not touch the game tileset.
## Reemplazar PNG con los mismos nombres no requiere re-ejecutarlo; sí agregar o renombrar tiles.
## Replacing PNGs with the same names needs no rerun; adding or renaming tiles does.
##   "$GODOT" --headless --path . -s scripts/tools/build_art_preview_tileset.gd

const Room: GDScript = preload("res://scripts/preview/art_preview_room.gd")
const OUT_PATH: String = "res://tilesets/art_preview_crypt.tres"
# Capa de colisión de las paredes; igual a CollisionLayers.WORLD / Wall collision layer; equals CollisionLayers.WORLD
const WORLD_LAYER: int = 1


func _initialize() -> void:
	var tile_set: TileSet = TileSet.new()
	tile_set.tile_size = Vector2i(32, 32)
	tile_set.add_physics_layer()
	tile_set.set_physics_layer_collision_layer(0, WORLD_LAYER)
	# Colisión rectangular de tile completo / Full-tile rectangle collision
	var full_rect: PackedVector2Array = PackedVector2Array([
		Vector2(-16, -16), Vector2(16, -16), Vector2(16, 16), Vector2(-16, 16)])
	var tile_names: PackedStringArray = Room.TILE_NAMES
	for source_id: int in tile_names.size():
		var tile_name: String = tile_names[source_id]
		var source: TileSetAtlasSource = TileSetAtlasSource.new()
		source.texture = load(Room.ART_DIR + tile_name + ".png")
		source.texture_region_size = Vector2i(32, 32)
		source.create_tile(Vector2i.ZERO)
		tile_set.add_source(source, source_id)
		if Room.is_solid(tile_name):
			var tile_data: TileData = source.get_tile_data(Vector2i.ZERO, 0)
			tile_data.add_collision_polygon(0)
			tile_data.set_collision_polygon_points(0, 0, full_rect)
	var err: Error = ResourceSaver.save(tile_set, OUT_PATH)
	print("saved %s (%d tiles): %s" % [OUT_PATH, tile_names.size(), error_string(err)])
	quit(0 if err == OK else 1)
