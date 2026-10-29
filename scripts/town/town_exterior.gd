extends "res://scripts/town/town_area.gd"

## Exterior de Hondoval (D25): los sólidos, las puertas y sus marcadores salen de MAP; el arte es un suelo horneado
## (calle, barro, agua, murallas y decals) más un sprite por edificio y por prop, ordenados por Y.
## Hondoval's exterior (D25): solids, doors and their markers come from MAP; the art is a baked ground (street,
## mud, water, walls and decals) plus one sprite per building and prop, sorted by Y.

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
const ART_DIR: String = "res://assets/art/town/"
## Edificio por letra de puerta; su huella es la tira de sólidos de esa fila / Building per door letter; its footprint is that row's solid run
const BUILDINGS: Dictionary = {"S": "smithy", "A": "apothecary", "T": "shop", "G": "guild", "E": "cathedral"}
## Px que el dibujo baja por debajo de su huella / Px the drawing hangs below its footprint
const BUILDING_OVERHANG: int = 6
## Props fuera del mapa: [sprite, pie en px, tamaño del sólido en el pie en px (ZERO = se atraviesa)]
## Props outside the map: [sprite, foot in px, solid size at the foot in px (ZERO = walk-through)]
const PROPS: Array = [
	["lamp", Vector2(368, 196), Vector2(8, 6)], ["lamp", Vector2(688, 196), Vector2(8, 6)],
	["lamp", Vector2(1008, 196), Vector2(8, 6)], ["lamp", Vector2(1392, 196), Vector2(8, 6)],
	["barrels", Vector2(328, 188), Vector2(72, 16)], ["barrels", Vector2(328, 480), Vector2(72, 16)],
	["woodpile", Vector2(648, 190), Vector2(80, 14)], ["notice_board", Vector2(864, 190), Vector2(50, 10)],
	["cart", Vector2(960, 190), Vector2(70, 14)], ["gallows", Vector2(640, 424), Vector2(80, 12)],
	["dead_tree", Vector2(1472, 416), Vector2(12, 8)], ["dead_tree", Vector2(1824, 480), Vector2(12, 8)],
	["dead_tree", Vector2(1856, 288), Vector2(12, 8)], ["graveyard_gate", Vector2(1680, 328), Vector2.ZERO],
	["fence", Vector2(1488, 324), Vector2(90, 8)], ["fence", Vector2(1552, 324), Vector2(90, 8)],
	["fence", Vector2(1776, 324), Vector2(90, 8)], ["mausoleum", Vector2(1824, 532), Vector2(60, 30)],
	["well", Vector2(832, 352), Vector2.ZERO],
]
## Lápidas que se reparten por las + del mapa / Gravestones spread over the map's +
const GRAVE_SPRITES: int = 4
## Puerta por letra: nombre del nodo, área de destino y si cierra de noche / Door per letter: node name, target area and whether it closes at night
const DOORS: Dictionary = {
	"S": ["SmithyDoor", &"smithy", true],
	"A": ["ApothecaryDoor", &"apothecary", true],
	"T": ["ShopDoor", &"shop", true],
	"G": ["GuildDoor", &"guild", false],
}


@onready var _things: Node2D = $Things


func _ready() -> void:
	var tile: int = DungeonGeometryScript.TILE_SIZE
	camera_bounds = Rect2i(Vector2i.ZERO, Vector2i(MAP[0].length(), MAP.size()) * tile)
	var ground: Sprite2D = Sprite2D.new()
	ground.name = "Ground"
	ground.texture = load(ART_DIR + "hondoval_ground.png")
	ground.centered = false
	ground.z_index = -1
	add_child(ground)
	move_child(ground, 0)
	var solids: StaticBody2D = StaticBody2D.new()
	solids.name = "Solids"
	solids.collision_layer = CollisionLayers.WORLD
	solids.collision_mask = 0
	add_child(solids)
	var markers: Node2D = Node2D.new()
	markers.name = "Markers"
	add_child(markers)
	var graves: int = 0
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
				_add_solid(solids, cell, Vector2(run * tile, tile))
			elif ch == "E" or DOORS.has(ch):
				_add_door(ch, cell + Vector2(tile, tile) / 2.0, markers, tile)
				_add_building(ch, x, y, tile)
			if ch == "+":
				_add_sprite("grave_%d" % (graves % GRAVE_SPRITES), cell + Vector2(tile / 2.0, tile - 2))
				graves += 1
			x += run
	for prop: Array in PROPS:
		var at: Vector2 = prop[1]
		var solid_size: Vector2 = prop[2]
		_add_sprite(prop[0], at)
		if solid_size != Vector2.ZERO:
			_add_solid(solids, at - Vector2(solid_size.x / 2.0, solid_size.y), solid_size)


# Sprite con el pie en `at`: el orden por Y lo toma de ahí / Sprite with its foot at `at`: Y-sorting reads it there
func _add_sprite(sprite_name: String, at: Vector2, overhang: int = 0) -> void:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.name = sprite_name.to_pascal_case()
	sprite.texture = load(ART_DIR + sprite_name + ".png")
	sprite.centered = false
	sprite.offset = Vector2(-sprite.texture.get_width() / 2.0, overhang - sprite.texture.get_height()).floor()
	sprite.position = at
	_things.add_child(sprite)


# Centrado en la tira de sólidos de la fila de su puerta, con el pie al final de la huella
# Centred on the solid run of its door's row, with its foot at the end of the footprint
func _add_building(letter: String, door_x: int, door_y: int, tile: int) -> void:
	if not BUILDINGS.has(letter):
		return
	var row: String = MAP[door_y]
	var left: int = door_x
	while left > 0 and row[left - 1] not in [".", "#"]:
		left -= 1
	var right: int = door_x
	while right < row.length() - 1 and row[right + 1] not in [".", "#"]:
		right += 1
	_add_sprite(BUILDINGS[letter], Vector2((left + right + 1) * tile / 2.0, (door_y + 1) * tile), BUILDING_OVERHANG)


func _add_solid(solids: StaticBody2D, at: Vector2, size_px: Vector2) -> void:
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
