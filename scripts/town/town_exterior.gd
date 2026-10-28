extends "res://scripts/town/town_area.gd"

## Exterior de Hondoval en bloqueo (D25): arma el suelo, los sólidos, las puertas y sus marcadores desde MAP,
## con colores provisorios a escala definitiva. El plan de arte cambia los ColorRect por tiles.
## Hondoval's blocked-out exterior (D25): builds the ground, solids, doors and their markers from MAP with
## provisional colors at final scale. The art plan swaps the ColorRects for tiles.

const DungeonGeometryScript: GDScript = preload("res://scripts/dungeon/dungeon_geometry.gd")
const CollisionLayers: GDScript = preload("res://scripts/combat/collision_layers.gd")
const TownDoorScene: PackedScene = preload("res://scenes/town/town_door.tscn")
const TownSpotScene: PackedScene = preload("res://scenes/town/town_spot.tscn")

## Mapa en tiles: # empalizada, H fachada, C catedral, ~ agua negra, + tumba y o pozo son sólidos; . suelo;
## S A T G son las puertas de herrería, botica, tienda y gremio; E es la entrada a la cripta
## Map in tiles: # palisade, H façade, C cathedral, ~ black water, + grave and o well are solid; . ground;
## S A T G are the smithy, apothecary, shop and guild doors; E is the crypt entrance
const MAP: PackedStringArray = [
	"############################################################",
	"#.HHHHHHHH..HHHHHHH..............HHHHHHHHHH.#...CCCCCCCCC..#",
	"#.HHHHHHHH..HHHHHHH..............HHHHHHHHHH.#...CCCCCCCCC..#",
	"#.HHHHHHHH..HHHHHHH..............HHHHHHHHHH.#...CCCCCCCCC..#",
	"#.HHHHHHHH..HHHHHHH..............HHHHHHHHHH.#...CCCCCCCCC..#",
	"#.HHHSHHHH..HHHAHHH..............HHHHHHHHHH.#...CCCCCCCCC..#",
	"#................................HHHHGHHHHH.#...CCCCECCCC..#",
	"#...........................................#..............#",
	"#..........................................................#",
	"#........................oo................................#",
	"#.HHHHHHHH...............oo.................#..+..+...+....#",
	"#.HHHHHHHH..~~~~~~~.........................#..............#",
	"#.HHHHHHHH..~~~~~~~.........................#.....+...+..+.#",
	"#.HHHHHHHH..~~~~~~~.........................#..+...........#",
	"#.HHHHTHHH..................................#......+..+....#",
	"#...........................................#..............#",
	"#...........................................#..............#",
	"############################################################",
]
const SOLIDS: String = "#HC~+o"
## Color provisorio por carácter; "door" para las puertas / Provisional color per character; "door" for doors
const COLORS: Dictionary = {
	".": Color(0.2, 0.17, 0.14),
	"#": Color(0.3, 0.24, 0.18),
	"H": Color(0.36, 0.3, 0.26),
	"C": Color(0.32, 0.32, 0.34),
	"~": Color(0.08, 0.1, 0.12),
	"+": Color(0.42, 0.42, 0.4),
	"o": Color(0.28, 0.28, 0.3),
	"door": Color(0.16, 0.11, 0.09),
}
## Puerta por letra: nombre del nodo, área de destino y si cierra de noche / Door per letter: node name, target area and whether it closes at night
const DOORS: Dictionary = {
	"S": ["SmithyDoor", &"smithy", true],
	"A": ["ApothecaryDoor", &"apothecary", true],
	"T": ["ShopDoor", &"shop", true],
	"G": ["GuildDoor", &"guild", false],
}


func _ready() -> void:
	var tile: int = DungeonGeometryScript.TILE_SIZE
	camera_bounds = Rect2i(Vector2i.ZERO, Vector2i(MAP[0].length(), MAP.size()) * tile)
	_add_rect(Vector2.ZERO, Vector2(camera_bounds.size), COLORS["."])
	var solids: StaticBody2D = StaticBody2D.new()
	solids.name = "Solids"
	solids.collision_layer = CollisionLayers.WORLD
	solids.collision_mask = 0
	add_child(solids)
	var markers: Node2D = Node2D.new()
	markers.name = "Markers"
	add_child(markers)
	for y in range(MAP.size()):
		var row: String = MAP[y]
		var x: int = 0
		while x < row.length():
			var ch: String = row[x]
			var run: int = 1
			while SOLIDS.contains(ch) and x + run < row.length() and row[x + run] == ch:
				run += 1
			var cell: Vector2 = Vector2(x, y) * tile
			if SOLIDS.contains(ch):
				_add_solid(solids, cell, Vector2(run * tile, tile), COLORS[ch])
			elif ch == "E" or DOORS.has(ch):
				_add_rect(cell, Vector2(tile, tile), COLORS["door"])
				_add_door(ch, cell + Vector2(tile, tile) / 2.0, markers, tile)
			x += run


func _add_rect(at: Vector2, size_px: Vector2, color: Color) -> void:
	var rect: ColorRect = ColorRect.new()
	rect.position = at
	rect.size = size_px
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)


func _add_solid(solids: StaticBody2D, at: Vector2, size_px: Vector2, color: Color) -> void:
	_add_rect(at, size_px, color)
	var rect_shape: RectangleShape2D = RectangleShape2D.new()
	rect_shape.size = size_px
	var shape: CollisionShape2D = CollisionShape2D.new()
	shape.shape = rect_shape
	shape.position = at + size_px / 2.0
	solids.add_child(shape)


# La puerta va sobre su celda y el marcador de llegada en la celda de abajo / The door sits on its cell and the arrival marker on the cell below
func _add_door(letter: String, center: Vector2, markers: Node2D, tile: int) -> void:
	var marker: Marker2D = Marker2D.new()
	marker.position = center + Vector2(0, tile)
	var spot: Area2D
	if letter == "E":
		spot = TownSpotScene.instantiate() as Area2D
		spot.name = "CryptEntrance"
		marker.name = "crypt"
	else:
		var door_info: Array = DOORS[letter]
		spot = TownDoorScene.instantiate() as Area2D
		spot.name = door_info[0]
		spot.set("target_area", door_info[1])
		spot.set("target_marker", &"from_street")
		spot.set("closes_at_night", door_info[2])
		marker.name = "%s_door" % door_info[1]
	spot.position = center
	add_child(spot)
	markers.add_child(marker)
