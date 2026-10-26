extends Node2D

## Ambiente procedural del piso, sembrado por la seed (BIBLIA_ARTE §3.6): antorchas en las paredes
## norte (una encendida por zona, otras apagadas), objetos colgados, telarañas y calcos de piso.
## Procedural floor ambience, seeded: north-wall torches (one lit per zone, others burnt out),
## hanging props, cobwebs and floor decals. Decoration only: no collision, no gameplay.
## DungeonManager la agrega justo después del TileMap, así queda debajo de todo lo que se spawnea.
## DungeonManager adds it right after the TileMap, so it draws under everything spawned later.

const TorchScene: PackedScene = preload("res://scenes/dungeon/wall_torch.tscn")
const ART_DIR: String = "res://assets/art/environment/crypt/"
# Sal de la seed del ambiente, distinta de las del Spawner / Ambience seed salt, unlike the Spawner's
const DRESSING_SALT: int = 0x5EED_D3C0
# Calcos de piso; los repetidos salen más seguido / Floor decals; repeated names come up more often
const FLOOR_DECALS: PackedStringArray = [
	"bone_s", "bone_s", "pebble_a", "pebble_b", "pebble_c", "pebble_b", "bones", "ribs", "planks",
	"blood_pool", "blood_drops", "blood_drops", "grate",
]
# Objetos colgados de la cara norte / Props hanging on the north face
const WALL_HANGINGS: PackedStringArray = ["chains", "banner_torn", "meathook"]
# Tiles de piso por calco (más = piso más limpio) / Floor tiles per decal (more = cleaner floor)
const TILES_PER_DECAL: int = 40
# Ancho de zona en tiles desde el que hay una segunda antorcha encendida / Zone width in tiles that earns a second lit torch
const SECOND_TORCH_WIDTH: int = 24
# Separación mínima entre objetos de la pared norte, en tiles / Min gap between north-wall props, in tiles
const WALL_PROP_SPACING: int = 4
# Altura donde cuelgan los objetos, en px bajo el borde de la zona (justo bajo el labio del tope)
# Hanging height, in px below the zone's top edge (right under the wall-top lip)
const HANGING_Y: int = 33
# Telaraña: lado en px y altura bajo el borde de la zona / Cobweb: side in px and height below the zone top
const COBWEB_SIZE: int = 10
const COBWEB_Y: int = 35
# Margen de un calco dentro de su tile, en px / Decal margin inside its tile, in px
const DECAL_MARGIN: int = 6

# Pivote [x, y] en px por sprite; sin entrada = esquina superior izquierda / Pivot per sprite; missing = top-left
var _pivots: Dictionary = {}


func dress(layout: DungeonGenerator.FloorLayout) -> void:
	_pivots = JSON.parse_string(FileAccess.get_file_as_string(ART_DIR + "props.json"))
	for z: Zone in layout.zones:
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = layout.floor_seed ^ z.id ^ DRESSING_SALT
		_dress_north_wall(z, layout.doors, rng)
		_scatter_decals(z, layout, rng)


## Antorchas y objetos colgados en columnas libres de la cara norte (sin arcos de puerta ni esquinas).
## Torches and hanging props on free north-face columns (no door arches, no corners).
func _dress_north_wall(z: Zone, doors: Array, rng: RandomNumberGenerator) -> void:
	var top: int = z.tile_rect.position.y
	var free: Array[int] = []
	for tx in range(z.tile_rect.position.x + 2, z.tile_rect.end.x - 2):
		free.append(tx)
	for d in doors:
		var door: Zone.Door = d
		if door.edge_axis == "h" and door.edge_line == top:
			for tx in range(door.pos_along - 1, door.pos_along + 2):
				free.erase(tx)
	var lit: int = 2 if z.tile_rect.size.x >= SECOND_TORCH_WIDTH else 1
	# Las encendidas primero; la última, con 50%, queda apagada (solo el soporte)
	# Lit ones first; the last one, at 50%, is burnt out (holder only)
	var torches: int = lit + (1 if rng.randf() < 0.5 else 0)
	for i in torches:
		var column: int = _take_column(free, rng)
		if column < 0:
			break
		var torch: Node2D = TorchScene.instantiate()
		torch.position = Vector2(column * DungeonGeometry.TILE_SIZE + DungeonGeometry.TILE_SIZE / 2.0,
				top * DungeonGeometry.TILE_SIZE)
		if i < lit:
			torch.get_node("Light").set("flicker_seed", rng.randi())
		else:
			torch.get_node("Flame").free()
			torch.get_node("Light").free()
		add_child(torch)
	if rng.randf() < 0.6:
		var column: int = _take_column(free, rng)
		if column >= 0:
			var hanging: String = WALL_HANGINGS[rng.randi_range(0, WALL_HANGINGS.size() - 1)]
			add_child(_make_sprite(hanging, Vector2(
					column * DungeonGeometry.TILE_SIZE + DungeonGeometry.TILE_SIZE / 2.0,
					top * DungeonGeometry.TILE_SIZE + HANGING_Y)))
	var web_y: float = top * DungeonGeometry.TILE_SIZE + COBWEB_Y
	if rng.randf() < 0.5:
		add_child(_make_sprite("cobweb", Vector2((z.tile_rect.position.x + 1) * DungeonGeometry.TILE_SIZE, web_y)))
	if rng.randf() < 0.5:
		var web: Sprite2D = _make_sprite("cobweb",
				Vector2((z.tile_rect.end.x - 1) * DungeonGeometry.TILE_SIZE - COBWEB_SIZE, web_y))
		web.flip_h = true
		add_child(web)


## Saca una columna al azar y las vecinas a menos de WALL_PROP_SPACING; -1 si no quedan.
## Takes a random column and drops the ones closer than WALL_PROP_SPACING; -1 when none are left.
func _take_column(free: Array[int], rng: RandomNumberGenerator) -> int:
	if free.is_empty():
		return -1
	var column: int = free[rng.randi_range(0, free.size() - 1)]
	for tx in range(column - WALL_PROP_SPACING + 1, column + WALL_PROP_SPACING):
		free.erase(tx)
	return column


## Calcos de piso sueltos sobre el piso interior (bajo la cara norte, fuera de la escalera y su entrada).
## Sparse floor decals on the interior floor (below the north face, off the stairs and their entry).
func _scatter_decals(z: Zone, layout: DungeonGenerator.FloorLayout, rng: RandomNumberGenerator) -> void:
	var first: Vector2i = z.tile_rect.position + Vector2i(1, 1 + DungeonGeometry.NORTH_FACE_ROWS)
	var last: Vector2i = z.tile_rect.end - Vector2i(2, 2)
	var area: Vector2i = last - first + Vector2i.ONE
	var stairs: Rect2i = Rect2i()
	if z.id == layout.exit_zone_id:
		stairs = DungeonGeometry.stairs_keep_clear(layout.exit_stairs)
	for i in area.x * area.y / TILES_PER_DECAL:
		var tile: Vector2i = Vector2i(rng.randi_range(first.x, last.x), rng.randi_range(first.y, last.y))
		var decal: String = FLOOR_DECALS[rng.randi_range(0, FLOOR_DECALS.size() - 1)]
		var inside: Vector2i = Vector2i(
				rng.randi_range(DECAL_MARGIN, DungeonGeometry.TILE_SIZE - DECAL_MARGIN),
				rng.randi_range(DECAL_MARGIN, DungeonGeometry.TILE_SIZE - DECAL_MARGIN))
		if stairs.has_point(tile) or layout.blocked_tiles.has(tile):
			continue
		add_child(_make_sprite(decal, Vector2(tile * DungeonGeometry.TILE_SIZE + inside)))


func _make_sprite(sprite_name: String, ground: Vector2) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = load(ART_DIR + sprite_name + ".png")
	sprite.centered = false
	var pivot: Array = _pivots.get(sprite_name, [0, 0])
	sprite.offset = -Vector2(pivot[0], pivot[1])
	sprite.position = ground
	# La luz de antorcha solo toca personajes / Torch light only touches characters
	sprite.light_mask = 0
	return sprite
