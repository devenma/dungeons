extends Node2D

## Zona de pruebas: distintos "kits" de entorno (árboles, arbustos y su pasto) uno al lado del otro, de izquierda a
## derecha, para que el mismo personaje camine de uno a otro y se compare cuál encaja con su estilo. Cada kit ocupa
## una franja de una pantalla de ancho con su nombre arriba; su piso se arma con su tileset Wang de 4 esquinas
## (PNG + JSON de esquinas -> celda del atlas) y un camino de tierra que cruza todas las franjas.
## Test zone: environment "kits" (trees, bushes and their grass) side by side, left to right, so the same character
## walks from one to the next to compare which fits its style. Each kit fills a one-screen-wide strip with its name on
## top; its floor is built from its 4-corner Wang tileset (PNG + corners -> atlas cell JSON) with a dirt path crossing
## every strip.

# Tamaño de la franja de cada kit en tiles (15 = una pantalla de ancho) / each kit's strip size in tiles
const STRIP_TILES: Vector2i = Vector2i(15, 20)
# Alto (px) de cada banda de matas: cuanto más chica, más exacto el orden con la figura y más nodos
# Height (px) of each tuft band: smaller sorts more exactly against the figure but makes more nodes
const TUFT_BAND_PX: int = 8
# Elige la celda del atlas: fila = INSTANCE_CUSTOM.r, cuadro del viento según TIME + la fase propia (custom.g)
# Picks the atlas cell: row = INSTANCE_CUSTOM.r, wind frame from TIME + the tuft's own phase (custom.g)
const TUFT_SHADER: String = """
shader_type canvas_item;
uniform sampler2D atlas : filter_nearest;
uniform vec2 grid;
uniform vec4 durations;
varying flat vec2 tuft;
void vertex() { tuft = INSTANCE_CUSTOM.rg; }
void fragment() {
	float total = durations.x + durations.y + durations.z + durations.w;
	float t = mod(TIME + tuft.y * total, total);
	float frame = t < durations.x ? 0.0 : (t < durations.x + durations.y ? 1.0 : (t < total - durations.w ? 2.0 : 3.0));
	COLOR = texture(atlas, (vec2(frame, tuft.x) + UV) / grid);
}
"""

# Nombre, nodo con sus plantas y prefijo del piso (<prefijo>.png + .json) de cada kit, en el mismo orden
# Each kit's name, node holding its plants and floor prefix (<prefix>.png + .json), in the same order
@export var kit_names: PackedStringArray = []
@export var kit_nodes: Array[NodePath] = []
@export var kit_floors: PackedStringArray = []
# JSON de matas sueltas (flora.py matas) que se reparten sobre el pasto del kit; vacío = sin matas
# Loose tufts JSON (flora.py matas) scattered over the kit's grass; empty = no tufts
@export var kit_tufts: PackedStringArray = []


func _ready() -> void:
	var tile_px: int = 32
	var strip_width: float = STRIP_TILES.x * tile_px
	for i: int in kit_names.size():
		var offset: Vector2 = Vector2(i * strip_width, 0.0)
		var floor_layer: TileMapLayer = _build_floor(kit_floors[i], i)
		floor_layer.position = offset
		$Floors.add_child(floor_layer)
		var kit: Node2D = get_node(kit_nodes[i])
		kit.position = offset
		if i < kit_tufts.size() and kit_tufts[i] != "":
			_scatter_tufts(kit, kit_tufts[i], floor_layer, kit_floors[i], i)
		var label: Label = Label.new()
		label.text = kit_names[i]
		label.add_theme_font_size_override("font_size", 8)
		label.position = offset + Vector2(-strip_width / 2.0 + 8.0, -STRIP_TILES.y * tile_px / 2.0 + 4.0)
		$Floors.add_child(label)


func _build_floor(prefix: String, strip: int) -> TileMapLayer:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(prefix + ".json"))
	var tiles: Dictionary = meta["tiles"]
	var tile_px: int = int(meta["tile"])
	var source: TileSetAtlasSource = TileSetAtlasSource.new()
	source.texture = load(prefix + ".png")
	source.texture_region_size = Vector2i(tile_px, tile_px)
	var cells: Array = tiles.values()
	for options: Array in meta.get("variantes", {}).values():
		cells.append_array(options)
	# "cuadros": cada tile ocupa n celdas seguidas (viento horneado), animadas por el TileSet sin nodos extra
	# "cuadros": each tile takes n cells in a row (baked wind), animated by the TileSet with no extra nodes
	var frame_count: int = int(meta.get("cuadros", 1))
	for coords: Array in cells:
		var cell: Vector2i = Vector2i(int(coords[0]), int(coords[1]))
		if source.has_tile(cell): continue
		source.create_tile(cell)
		if frame_count > 1:
			source.set_tile_animation_columns(cell, frame_count)
			source.set_tile_animation_frames_count(cell, frame_count)
			for f: int in frame_count:
				source.set_tile_animation_frame_duration(cell, f, float(meta["duraciones_ms"][f]) / 1000.0)
	var tile_set: TileSet = TileSet.new()
	tile_set.tile_size = Vector2i(tile_px, tile_px)
	tile_set.add_source(source, 0)
	var layer: TileMapLayer = TileMapLayer.new()
	layer.tile_set = tile_set
	var half: Vector2i = STRIP_TILES / 2
	for y: int in STRIP_TILES.y:
		for x: int in STRIP_TILES.x:
			# x global, así el camino sigue de una franja a la otra / global x so the path runs on across strips
			var gx: int = strip * STRIP_TILES.x + x
			# Esquinas NW NE SW SE: U = pasto, L = tierra / corners: U = grass, L = dirt
			var key: String = _corner(gx, y) + _corner(gx + 1, y) + _corner(gx, y + 1) + _corner(gx + 1, y + 1)
			var coords: Array = tiles[key]
			# "variantes": más celdas para la misma combinación, elegidas por posición / more cells per combo, by position
			var variants: Dictionary = meta.get("variantes", {})
			if variants.has(key):
				var options: Array = variants[key]
				coords = options[absi(hash(Vector2i(gx, y))) % options.size()]
			layer.set_cell(Vector2i(x, y) - half, 0, Vector2i(int(coords[0]), int(coords[1])))
	return layer


# Matas sueltas repartidas con disco de Poisson sobre los píxeles de pasto del piso (sin grilla) y dibujadas con
# MultiMesh: una banda horizontal de TUFT_BAND_PX es un MultiMeshInstance2D, hijo del kit que ordena por y, así la
# figura pasa delante o detrás con un error de media banda. Cada mata elige su fila del atlas y su fase de viento.
# Loose tufts scattered with a Poisson disc over the floor's grass pixels (no grid) and drawn with MultiMesh: each
# horizontal TUFT_BAND_PX band is one MultiMeshInstance2D under the y-sorted kit, so the figure walks in front of or
# behind them within half a band. Each tuft picks its atlas row and its wind phase.
func _scatter_tufts(kit: Node2D, path: String, floor_layer: TileMapLayer, floor_prefix: String, strip: int) -> void:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var species: Dictionary = meta["especies"]
	var rows: Array = meta["atlas"]["filas"]
	var rows_of: Dictionary = {}
	for i: int in rows.size():
		var row_species: String = rows[i]["especie"]
		if not rows_of.has(row_species): rows_of[row_species] = []
		(rows_of[row_species] as Array).append(i)
	var names: Array = rows_of.keys().filter(func(n: String) -> bool: return float(species[n]["densidad"]) > 0.0)
	names.sort_custom(func(a: String, b: String) -> bool: return float(species[a]["distancia_px"]) > float(species[b]["distancia_px"]))
	var ground_meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(floor_prefix + ".json"))
	var grass_colors: Dictionary = {}
	for hex: String in ground_meta["colores_pasto"]:
		grass_colors[Color(hex).to_html(false)] = true
	var ground: Image = (load(floor_prefix + ".png") as Texture2D).get_image()
	var tile_px: int = int(ground_meta["tile"])
	var area: Vector2 = Vector2(STRIP_TILES * tile_px)
	var top_left: Vector2 = -Vector2(STRIP_TILES / 2 * tile_px)
	var grass_tiles: float = 0.0
	for y: int in STRIP_TILES.y:
		for x: int in STRIP_TILES.x:
			var gx: int = strip * STRIP_TILES.x + x
			var corners: String = _corner(gx, y) + _corner(gx + 1, y) + _corner(gx, y + 1) + _corner(gx + 1, y + 1)
			grass_tiles += corners.count("U") / 4.0
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 11 + strip
	var cell: float = float(species[names[0]]["distancia_px"])
	var grid: Dictionary = {}
	# Cada mata: [pivote, fila del atlas, fase] / each tuft: [pivot, atlas row, phase]
	var placed: Array = []
	for name: String in names:
		var distance: float = float(species[name]["distancia_px"])
		var target: int = int(float(species[name]["densidad"]) * grass_tiles)
		var count: int = 0
		for attempt: int in target * 30:
			if count >= target: break
			var spot: Vector2 = (top_left + Vector2(rng.randf() * area.x, rng.randf() * area.y)).floor()
			if not _on_grass(spot, floor_layer, ground, grass_colors, tile_px): continue
			if not _poisson_free(grid, spot, distance, cell): continue
			var key: Vector2i = Vector2i((spot / cell).floor())
			if not grid.has(key): grid[key] = []
			(grid[key] as Array).append(Vector3(spot.x, spot.y, distance))
			var options: Array = rows_of[name]
			placed.append([spot, options[rng.randi() % options.size()], rng.randf()])
			count += 1
	_build_tuft_bands(kit, placed, meta["atlas"], path.get_base_dir())


func _on_grass(spot: Vector2, floor_layer: TileMapLayer, ground: Image, grass_colors: Dictionary, tile_px: int) -> bool:
	# Prueba el píxel real del tile, así las matas llegan hasta el borde orgánico / tests the tile's real pixel
	var tile: Vector2i = floor_layer.local_to_map(spot)
	var atlas_cell: Vector2i = floor_layer.get_cell_atlas_coords(tile)
	if atlas_cell == Vector2i(-1, -1): return false
	var pixel: Vector2i = atlas_cell * tile_px + Vector2i(spot) - tile * tile_px
	return grass_colors.has(ground.get_pixelv(pixel).to_html(false))


func _poisson_free(grid: Dictionary, spot: Vector2, distance: float, cell: float) -> bool:
	# Dos pivotes quedan al menos a la media de sus distancias / two pivots stay at least the mean of their distances
	var key: Vector2i = Vector2i((spot / cell).floor())
	for j: int in range(key.y - 1, key.y + 2):
		for i: int in range(key.x - 1, key.x + 2):
			for other: Vector3 in grid.get(Vector2i(i, j), []):
				var reach: float = (distance + other.z) / 2.0
				if spot.distance_squared_to(Vector2(other.x, other.y)) < reach * reach: return false
	return true


func _build_tuft_bands(kit: Node2D, placed: Array, atlas: Dictionary, base_dir: String) -> void:
	var size: float = float(atlas["celda"])
	var rows: Array = atlas["filas"]
	var durations: Array = atlas["duraciones_ms"]
	# Un cuadrado del tamaño de la celda, con UV de 0 a 1 / a cell-sized square with 0-1 UVs
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2.ZERO, Vector2(size, 0), Vector2(size, size), Vector2(0, size)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2.ZERO, Vector2(1, 0), Vector2.ONE, Vector2(0, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var quad: ArrayMesh = ArrayMesh.new()
	quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_2D_VERTICES)
	var shader: Shader = Shader.new()
	shader.code = TUFT_SHADER
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("atlas", load(base_dir.path_join(atlas["png"])))
	material.set_shader_parameter("grid", Vector2(float(atlas["cuadros"]), float(rows.size())))
	material.set_shader_parameter("durations", Vector4(durations[0], durations[1], durations[2], durations[3]) / 1000.0)
	var bands: Dictionary = {}
	for item: Array in placed:
		var band: int = floori((item[0] as Vector2).y / TUFT_BAND_PX)
		if not bands.has(band): bands[band] = []
		(bands[band] as Array).append(item)
	for band: int in bands:
		var items: Array = bands[band]
		# Dentro de la banda, de atrás hacia adelante / within the band, back to front
		items.sort_custom(func(a: Array, b: Array) -> bool: return (a[0] as Vector2).y < (b[0] as Vector2).y)
		var multimesh: MultiMesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_2D
		multimesh.use_custom_data = true
		multimesh.mesh = quad
		multimesh.instance_count = items.size()
		var band_node: MultiMeshInstance2D = MultiMeshInstance2D.new()
		band_node.position = Vector2(0, band * TUFT_BAND_PX + TUFT_BAND_PX / 2)
		for i: int in items.size():
			var row: int = items[i][1]
			var pivot: Vector2 = Vector2(rows[row]["pivote"][0], rows[row]["pivote"][1])
			var origin: Vector2 = items[i][0] - pivot - band_node.position
			multimesh.set_instance_transform_2d(i, Transform2D(0.0, origin))
			multimesh.set_instance_custom_data(i, Color(row, items[i][2], 0.0, 0.0))
		band_node.multimesh = multimesh
		band_node.material = material
		band_node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		kit.add_child(band_node)


# Tierra a lo largo de un camino que ondula de izquierda a derecha / dirt along a path winding left to right
func _corner(vx: int, vy: int) -> String:
	var path_y: float = STRIP_TILES.y / 2.0 + 1.0 + 2.5 * sin(vx * 0.3)
	return "L" if absf(vy - path_y) < 1.0 else "U"
