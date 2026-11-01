extends Node2D

## Sala de la muestra del gremio (maqueta A+): pone cada objeto de piso en `Things`, ordenado por Y, con una
## colisión en su huella; a todo mueble le suma un oclusor para las sombras del piso. El fondo, la alfombra y los
## bancos están en la escena. Arte de tools/art/guild_preview_export.py.
## Guild preview room (mockup A+): places each floor prop in `Things`, Y-sorted, with a footprint collision;
## every piece of furniture gets an occluder for floor shadows. Background, rug and benches live in the scene.

const ART_DIR: String = "res://assets/art/guild_preview/"
# Objetos de piso de la maqueta: [nombre, x del centro, y del suelo, alto de la huella en px]
# Mockup floor props: [name, centre x, ground y, footprint height in px]
const FLOOR_PROPS: Array = [
	["firewood", 118, 100, 10], ["armor_stand", 186, 104, 8], ["quest_board", 272, 102, 8], ["books", 318, 108, 10],
	["counter", 404, 128, 18], ["barrel", 458, 116, 12], ["chair_n", 112, 128, 10], ["bucket_mop", 336, 150, 10],
	["barrel", 452, 150, 12], ["stool", 372, 152, 8], ["stool", 424, 152, 8], ["chest", 40, 182, 12],
	["table_long_m", 240, 192, 20], ["crates", 452, 196, 14], ["sacks", 424, 204, 12], ["table_round", 392, 244, 14],
	["chair_s", 112, 236, 10], ["floor_candles", 30, 258, 6], ["mugs_plates", 300, 262, 8],
]
# Objetos sobre una mesa: [nombre, x del centro, y del suelo, mesa]; sin colisión, se dibujan con su mesa
# Props on a table: [name, centre x, ground y, table]; no collision, drawn with their table
const TABLE_PROPS: Array = [
	["map_table_items", 222, 176, "table_long_m"], ["candelabra", 262, 170, "table_long_m"],
	["table_items", 392, 214, "table_round"],
]
# La huella es 2 px más angosta que el dibujo de cada lado / The footprint is 2 px narrower than the drawing per side
const FOOTPRINT_INSET: float = 2.0

@onready var things: Node2D = $Things


func _ready() -> void:
	for entry: Array in FLOOR_PROPS:
		things.add_child(_make_prop(entry[0], Vector2(entry[1], entry[2]), entry[3]), true)
	for entry: Array in TABLE_PROPS:
		var table: Node2D = things.get_node(entry[3] as String)
		var sprite: Sprite2D = _make_sprite(entry[0])
		sprite.position = Vector2(entry[1], entry[2]) - table.position
		table.add_child(sprite)
	for child: Node in things.get_children():
		if child is StaticBody2D:
			_add_occluder(child)


func _make_sprite(prop_name: String) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.name = prop_name
	sprite.texture = load(ART_DIR + prop_name + ".png")
	sprite.centered = false
	# Abajo al centro sobre el punto del suelo, como la maqueta / Bottom-centred on the ground point, like the mockup
	sprite.offset = sprite.texture.get_size() * Vector2(-0.5, -1.0)
	var flames_path: String = ART_DIR + prop_name + "_llamas.png"
	if ResourceLoader.exists(flames_path):
		# Las llamas no se oscurecen con la sala / Flames are not darkened with the room
		var flames: Sprite2D = Sprite2D.new()
		flames.texture = load(flames_path)
		flames.centered = false
		flames.offset = sprite.offset
		flames.material = CanvasItemMaterial.new()
		(flames.material as CanvasItemMaterial).light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		sprite.add_child(flames)
	return sprite


func _make_prop(prop_name: String, ground: Vector2, footprint_height: float) -> StaticBody2D:
	var body: StaticBody2D = StaticBody2D.new()
	body.name = prop_name
	body.collision_mask = 0
	var sprite: Sprite2D = _make_sprite(prop_name)
	body.add_child(sprite)
	var drawn: Rect2 = Rect2(sprite.texture.get_image().get_used_rect())
	# Se ordena por el pie del dibujo, no por el borde del lienzo / Sorts by the drawing's foot, not the canvas edge
	var air_below: float = sprite.texture.get_height() - drawn.end.y
	body.position = ground - Vector2(0.0, air_below)
	sprite.position.y = air_below
	# Huella: las últimas filas opacas del dibujo / Footprint: the drawing's bottom opaque rows
	drawn.position += sprite.position + sprite.offset
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2(drawn.size.x - 2.0 * FOOTPRINT_INSET, footprint_height)
	var collision: CollisionShape2D = CollisionShape2D.new()
	collision.name = "CollisionShape2D"
	collision.shape = shape
	collision.position = Vector2(drawn.get_center().x, drawn.end.y - footprint_height / 2.0)
	body.add_child(collision)
	return body


# Oclusor con la forma de la huella: solo las luces de piso con sombra lo ven
# Footprint-shaped occluder: only the shadow-casting floor lights see it
func _add_occluder(body: StaticBody2D) -> void:
	var collision: CollisionShape2D = body.get_node("CollisionShape2D")
	var footprint: Rect2 = (collision.shape as RectangleShape2D).get_rect()
	footprint.position += collision.position
	var polygon: OccluderPolygon2D = OccluderPolygon2D.new()
	polygon.polygon = PackedVector2Array([footprint.position, Vector2(footprint.end.x, footprint.position.y),
			footprint.end, Vector2(footprint.position.x, footprint.end.y)])
	var occluder: LightOccluder2D = LightOccluder2D.new()
	occluder.name = "LightOccluder2D"
	occluder.occluder = polygon
	# Capa 2, la del piso: la sombra cae solo sobre el piso / Layer 2, the floor's: the shadow only falls on the floor
	occluder.occluder_light_mask = 2
	body.add_child(occluder)
