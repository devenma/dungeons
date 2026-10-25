@tool
extends Node2D

## Sala de prueba del estilo "cripta oscura": tiles + pasadas de escena + objetos + VFX de antorcha.
## Dark-crypt style test room: tiles + scene passes + props + torch VFX.
## Port de tileAt() y de las tablas de dungeon_v2.px.js. El arte de ART_DIR sale de
## tools/art/export_room.py; cambiar de sala = volver a exportar a esa carpeta.
## Port of tileAt() and the tables of dungeon_v2.px.js. ART_DIR comes from tools/art/export_room.py.
## @tool para ver la sala en el editor / @tool so the room shows in the editor.

# Tiles, objetos, pasadas y pivotes exportados / Exported tiles, props, passes and pivots
const ART_DIR: String = "res://assets/art/preview/crypt/"
const VFX_DIR: String = "res://assets/art/preview/vfx/"
const ShadowShader: Shader = preload("res://scripts/preview/tone_step_shadow.gdshader")
# Id de fuente del TileSet = índice en esta lista / TileSet source id = index in this list
const TILE_NAMES: PackedStringArray = [
	"wall_tl", "wall_top_0", "wall_top_1", "wall_top_2", "wall_tr", "door_n_hi", "door_n_lo", "door_e",
	"face_hi_0", "face_hi_1", "face_hi_2", "face_lo_0", "face_lo_1", "face_lo_2", "wall_right_below_door", "wall_bl",
	"floor_00", "floor_10", "floor_20", "floor_01", "floor_11", "floor_21", "floor_02", "floor_12",
	"floor_22", "wall_left_0", "wall_left_1", "wall_left_2", "wall_right_0", "wall_right_1", "wall_right_2", "wall_br",
	"wall_bottom_0", "wall_bottom_1", "wall_bottom_2", "corridor_e",
]
# Sala en tiles; el corredor este ocupa la columna ROOM_W / Room in tiles; the east corridor is column ROOM_W
const ROOM_W: int = 13
const ROOM_H: int = 9

# Objetos en el piso, ordenados por Y: [nombre, x, y del suelo] en px de pantalla (su sombra está en pass_contact)
# Floor props, Y-sorted: [name, x, ground y] in screen px (their shadow is baked in pass_contact)
const FLOOR_PROPS: Array = [
	["shelf_broken", 91, 88], ["barrel", 122, 90], ["barrel_broken", 150, 100], ["chest", 398, 98],
	["corpse", 178, 101], ["pillar", 92, 222], ["rubble", 118, 226], ["bones", 312, 176], ["bones", 124, 158],
]
# Calcos del piso, debajo de todo lo que está parado: [nombre, x, y] / Floor decals under everything standing
const DECALS: Array = [
	["planks", 108, 108], ["ribs", 272, 148], ["bone_s", 98, 140], ["bone_s", 352, 228], ["bone_s", 214, 228],
	["blood_pool", 362, 99], ["blood_drops", 372, 104], ["blood_drops", 356, 92],
	["pebble_a", 300, 120], ["pebble_b", 306, 123], ["pebble_c", 140, 226], ["pebble_b", 133, 214],
	["pebble_a", 230, 150], ["pebble_b", 360, 130], ["pebble_c", 84, 120], ["pebble_b", 260, 228],
	["pebble_a", 410, 176], ["grate", 318, 118],
]
# Objetos de pared: [nombre, x, y, espejado]; las dos antorchas usan el soporte apagado y el VFX pone la llama
# Wall props: [name, x, y, mirrored]; both torches use the burnt holder and the VFX adds the flame
const WALL_PROPS: Array = [
	["cobweb", 64, 17, false], ["cobweb", 406, 17, true], ["banner_torn", 280, 13, false],
	["chains", 200, 18, false], ["meathook", 362, 16, false], ["torch_out", 144, 59, false], ["torch_out", 336, 59, false],
]
# VFX en loop: [hoja, ancho y alto de celda en px, fps, pivote en px de celda, posición en pantalla]
# Looping VFX: [sheet, cell size in px, fps, pivot in cell px, screen position]
const WALL_VFX: Array = [
	["torch_flame", Vector2i(16, 24), 8.0, Vector2(8, 21), Vector2(144, 45)],
	["torch_smoulder", Vector2i(16, 16), 5.0, Vector2(8, 12), Vector2(336, 45)],
]
# Radios de la sombra de contacto de un personaje, en px (como contact/contact_core del .px.js)
# Character contact shadow radii, in px (as contact/contact_core in the .px.js)
const SHADOW_RADII: Vector2 = Vector2(10, 3)
const SHADOW_CORE_RADII: Vector2 = Vector2(7, 1.6)

# Pivote [x, y] en px por objeto; sin entrada = esquina superior izquierda / Pivot per prop; missing = top-left
var _pivots: Dictionary = {}
# Pares [personaje, sombra] que se mueven juntos / [character, shadow] pairs moved together
var _character_shadows: Array = []

@onready var tiles: TileMapLayer = $Tiles
@onready var overlays: Node2D = $Overlays
@onready var decals: Node2D = $Decals
@onready var shadows: Node2D = $CharacterShadows
@onready var wall_props: Node2D = $WallProps
@onready var things: Node2D = $Things


func _ready() -> void:
	_pivots = JSON.parse_string(FileAccess.get_file_as_string(ART_DIR + "props.json"))
	paint_tiles()
	var passes: Array = JSON.parse_string(FileAccess.get_file_as_string(ART_DIR + "passes.json"))
	for entry: Dictionary in passes:
		var overlay: Sprite2D = _make_sprite("pass_" + entry["name"], Vector2(entry["x"], entry["y"]))
		overlays.add_child(overlay)
	_add_character_shadows()
	for entry: Array in DECALS:
		decals.add_child(_make_sprite(entry[0], Vector2(entry[1], entry[2])))
	for entry: Array in WALL_PROPS:
		var sprite: Sprite2D = _make_sprite(entry[0], Vector2(entry[1], entry[2]))
		sprite.flip_h = entry[3]
		wall_props.add_child(sprite)
	for entry: Array in WALL_VFX:
		wall_props.add_child(_make_loop(entry[0], entry[1], entry[2], entry[3], entry[4]))
	for entry: Array in FLOOR_PROPS:
		things.add_child(_make_sprite(entry[0], Vector2(entry[1], entry[2])))


func _process(_delta: float) -> void:
	for pair: Array in _character_shadows:
		(pair[1] as Node2D).position = (pair[0] as Node2D).position + Vector2(0, -1)


static func is_solid(tile_name: String) -> bool:
	return not (tile_name.begins_with("floor_") or tile_name == "corridor_e")


## Port de tileAt(cl, r) del .px.js / Port of the .px.js tileAt(cl, r).
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
		return "door_n_hi" if col == 6 else "face_hi_%d" % i
	if row == 2:
		return "door_n_lo" if col == 6 else "face_lo_%d" % i
	# Variante periódica 3x3 / 3x3 periodic variant
	return "floor_%d%d" % [i, row % 3]


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
	var pivot: Array = _pivots.get(sprite_name, [0, 0])
	sprite.offset = -Vector2(pivot[0], pivot[1])
	sprite.position = ground
	return sprite


func _make_loop(sheet_name: String, cell: Vector2i, fps: float, pivot: Vector2, at: Vector2) -> AnimatedSprite2D:
	var sheet: Texture2D = load(VFX_DIR + sheet_name + ".png")
	var frames: SpriteFrames = SpriteFrames.new()
	frames.set_animation_speed("default", fps)
	for i: int in sheet.get_width() / cell.x:
		var frame: AtlasTexture = AtlasTexture.new()
		frame.atlas = sheet
		frame.region = Rect2(Vector2(i * cell.x, 0), Vector2(cell))
		frames.add_frame("default", frame)
	var sprite: AnimatedSprite2D = AnimatedSprite2D.new()
	sprite.name = sheet_name
	sprite.sprite_frames = frames
	sprite.centered = false
	sprite.offset = -pivot
	sprite.position = at
	sprite.play()
	return sprite


## Una sombra por personaje de la escena, dibujada antes de todo lo que está parado para que lea solo el piso.
## One shadow per scene character, drawn before everything standing so it reads only the floor.
func _add_character_shadows() -> void:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = ShadowShader
	material.set_shader_parameter("shade_lut", load(ART_DIR + "shade_lut.png"))
	material.set_shader_parameter("core_radii", SHADOW_CORE_RADII)
	var points: PackedVector2Array = PackedVector2Array()
	for k: int in 16:
		var angle: float = TAU * k / 16.0
		points.append(Vector2(cos(angle) * SHADOW_RADII.x, sin(angle) * SHADOW_RADII.y))
	for character: Node2D in things.get_children():
		var shadow: Polygon2D = Polygon2D.new()
		shadow.name = character.name + "Shadow"
		shadow.polygon = points
		shadow.material = material
		shadows.add_child(shadow)
		_character_shadows.append([character, shadow])
	_process(0.0)
