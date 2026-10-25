@tool
extends Node2D

## Arte del gremio: tiles de tablones, pasadas de escena, calcos y objetos de pared; los objetos de piso van
## al nodo Things del gremio, ordenados por Y junto al jugador y los NPC. Todo con light_mask 0: la luz de la
## chimenea solo toca personajes. Port de tileG() y de las tablas de guild() en 02_guild/room/guild.px.js;
## ART_DIR sale de tools/art/export_room.py --fn guild --only <TILE_NAMES + nombres de las tablas>.
## Guild art: plank tiles, scene passes, decals and wall props; floor props go to the guild's Things node,
## Y-sorted with the player and the NPCs. Everything has light_mask 0: the fireplace light only touches
## characters. Port of tileG() and the guild() tables of guild.px.js; ART_DIR comes from export_room.py
## --fn guild --only <TILE_NAMES + the table names>.
## @tool para ver la sala en el editor / @tool so the room shows in the editor.

# Tiles, objetos, pasadas y pivotes exportados / Exported tiles, props, passes and pivots
const ART_DIR: String = "res://assets/art/guild/"
# Id de fuente del TileSet = índice en esta lista / TileSet source id = index in this list
const TILE_NAMES: PackedStringArray = [
	"wall_tl", "wall_top_0", "wall_top_1", "wall_top_2", "wall_tr", "door_e", "corridor_e", "wall_right_below_door",
	"face_hi_0", "face_hi_1", "face_hi_2", "face_lo_0", "face_lo_1", "face_lo_2", "wall_bl", "wall_br",
	"plank_00", "plank_10", "plank_20", "plank_01", "plank_11", "plank_21", "plank_02", "plank_12",
	"plank_22", "wall_left_0", "wall_left_1", "wall_left_2", "wall_right_0", "wall_right_1", "wall_right_2",
	"wall_bottom_0", "wall_bottom_1", "wall_bottom_2",
]
# Sala en tiles; el corredor este ocupa la columna ROOM_W / Room in tiles; the east corridor is column ROOM_W
const ROOM_W: int = 13
const ROOM_H: int = 9

# Objetos de piso: [nombre, x, y del suelo] en px de pantalla (su sombra está en pass_contact)
# Floor props: [name, x, ground y] in screen px (their shadow is baked in pass_contact)
const FLOOR_PROPS: Array = [
	["chest", 82, 148], ["chest", 82, 176], ["chest", 82, 204], ["barrel", 406, 108], ["counter", 300, 140],
	["cot", 128, 230], ["cot", 178, 230], ["cot_dead", 228, 230], ["anvil", 352, 228], ["forge", 396, 232],
	["barrel_broken", 316, 230],
]
# Calcos del piso, debajo de todo lo que está parado: [nombre, x, y] / Floor decals under everything standing
const DECALS: Array = [
	["planks", 200, 150], ["blood_pool", 230, 236], ["blood_drops", 214, 200], ["blood_drops", 262, 182],
	["bone_s", 120, 162],
]
# Objetos de pared: [nombre, x, y, espejado] / Wall props: [name, x, y, mirrored]
const WALL_PROPS: Array = [
	["cobweb", 64, 17, false], ["cobweb", 406, 17, true], ["fireplace", 98, 80, false],
	["notice_board", 166, 62, false], ["window_boarded", 246, 66, false], ["gate", 326, 80, false],
	["window_eyes", 392, 66, false], ["banner_torn", 206, 13, false], ["torch_out", 276, 59, false],
]

# Objetos de piso, ordenados por Y con los personajes / Floor props, Y-sorted with the characters
@export var things_path: NodePath = NodePath("../Things")

# Pivote [x, y] en px por objeto; sin entrada = esquina superior izquierda / Pivot per prop; missing = top-left
var _pivots: Dictionary = {}

@onready var tiles: TileMapLayer = $Tiles
@onready var overlays: Node2D = $Overlays
@onready var decals: Node2D = $Decals
@onready var wall_props: Node2D = $WallProps


func _ready() -> void:
	_pivots = JSON.parse_string(FileAccess.get_file_as_string(ART_DIR + "props.json"))
	paint_tiles()
	var passes: Array = JSON.parse_string(FileAccess.get_file_as_string(ART_DIR + "passes.json"))
	for entry: Dictionary in passes:
		overlays.add_child(_make_sprite("pass_" + entry["name"], Vector2(entry["x"], entry["y"])))
	for entry: Array in DECALS:
		decals.add_child(_make_sprite(entry[0], Vector2(entry[1], entry[2])))
	for entry: Array in WALL_PROPS:
		var sprite: Sprite2D = _make_sprite(entry[0], Vector2(entry[1], entry[2]))
		sprite.flip_h = entry[3]
		wall_props.add_child(sprite)
	var things: Node2D = get_node(things_path) as Node2D
	for entry: Array in FLOOR_PROPS:
		things.add_child(_make_sprite(entry[0], Vector2(entry[1], entry[2])))


static func is_solid(tile_name: String) -> bool:
	return not (tile_name.begins_with("plank_") or tile_name == "corridor_e")


## Port de tileG(cl, r) del .px.js: la sala de la cripta con piso de tablones y la cara norte sin puerta.
## Port of the .px.js tileG(cl, r): the crypt room with a plank floor and a doorless north face.
static func tile_at(col: int, row: int) -> String:
	var i: int = col % 3
	var left: bool = col == 0
	var right: bool = col == ROOM_W - 1
	if col == ROOM_W:
		return "corridor_e" if row == 5 else ""
	if row == 0:
		return "wall_tl" if left else ("wall_tr" if right else "wall_top_%d" % i)
	if row == ROOM_H - 1:
		return "wall_bl" if left else ("wall_br" if right else "wall_bottom_%d" % i)
	if left:
		return "wall_left_%d" % (row % 3)
	if right:
		if row == 5:
			return "door_e"
		return "wall_right_below_door" if row == 6 else "wall_right_%d" % (row % 3)
	if row == 1:
		return "face_hi_%d" % i
	if row == 2:
		return "face_lo_%d" % i
	# Variante periódica 3x3 / 3x3 periodic variant
	return "plank_%d%d" % [i, row % 3]


func paint_tiles() -> void:
	tiles.clear()
	for row: int in ROOM_H:
		for col: int in ROOM_W + 1:
			var tile_name: String = tile_at(col, row)
			if tile_name != "":
				tiles.set_cell(Vector2i(col, row), TILE_NAMES.find(tile_name), Vector2i.ZERO)


func _make_sprite(sprite_name: String, ground: Vector2) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.name = sprite_name
	sprite.texture = load(ART_DIR + sprite_name + ".png")
	sprite.centered = false
	sprite.light_mask = 0
	var pivot: Array = _pivots.get(sprite_name, [0, 0])
	sprite.offset = -Vector2(pivot[0], pivot[1])
	sprite.position = ground
	return sprite
