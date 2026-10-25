extends SceneTree

## Genera un TileSet con los PNG de una sala exportada (un atlas por tile). Por defecto la sala de prueba:
## tilesets/art_preview_crypt.tres desde assets/art/preview/crypt/. Con argumentos, otra sala que exponga
## TILE_NAMES, ART_DIR e is_solid() como art_preview_room.gd (el gremio: guild_room.gd -> tilesets/guild.tres).
## Builds a TileSet from an exported room's PNGs (one atlas per tile). Defaults to the preview room; with
## arguments, any room script exposing TILE_NAMES, ART_DIR and is_solid() like art_preview_room.gd.
## Solo escribe su propio .tres; no toca el tileset del juego. / Writes only its own .tres; does not touch the game tileset.
## Reemplazar PNG con los mismos nombres no requiere re-ejecutarlo; sí agregar o renombrar tiles.
## Replacing PNGs with the same names needs no rerun; adding or renaming tiles does.
##   "$GODOT" --headless --path . -s scripts/tools/build_art_preview_tileset.gd
##   "$GODOT" --headless --path . -s scripts/tools/build_art_preview_tileset.gd -- res://scripts/guild/guild_room.gd res://tilesets/guild.tres

const DEFAULT_ROOM: String = "res://scripts/preview/art_preview_room.gd"
const DEFAULT_OUT: String = "res://tilesets/art_preview_crypt.tres"
# Capa de colisión de las paredes; igual a CollisionLayers.WORLD / Wall collision layer; equals CollisionLayers.WORLD
const WORLD_LAYER: int = 1


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var room: GDScript = load(args[0] if args.size() > 0 else DEFAULT_ROOM)
	var out_path: String = args[1] if args.size() > 1 else DEFAULT_OUT
	var tile_set: TileSet = TileSet.new()
	tile_set.tile_size = Vector2i(32, 32)
	tile_set.add_physics_layer()
	tile_set.set_physics_layer_collision_layer(0, WORLD_LAYER)
	# Colisión rectangular de tile completo / Full-tile rectangle collision
	var full_rect: PackedVector2Array = PackedVector2Array([
		Vector2(-16, -16), Vector2(16, -16), Vector2(16, 16), Vector2(-16, 16)])
	var tile_names: PackedStringArray = room.TILE_NAMES
	var art_dir: String = room.ART_DIR
	for source_id: int in tile_names.size():
		var tile_name: String = tile_names[source_id]
		var source: TileSetAtlasSource = TileSetAtlasSource.new()
		source.texture = load(art_dir + tile_name + ".png")
		source.texture_region_size = Vector2i(32, 32)
		source.create_tile(Vector2i.ZERO)
		tile_set.add_source(source, source_id)
		if room.is_solid(tile_name):
			var tile_data: TileData = source.get_tile_data(Vector2i.ZERO, 0)
			tile_data.add_collision_polygon(0)
			tile_data.set_collision_polygon_points(0, 0, full_rect)
	var err: Error = ResourceSaver.save(tile_set, out_path)
	print("saved %s (%d tiles): %s" % [out_path, tile_names.size(), error_string(err)])
	quit(0 if err == OK else 1)
