extends Node2D

## Un lugar del pueblo (D25): el exterior o un interior. Hondoval prende uno solo por vez. Apagado no se ve, no
## procesa y saca sus colisiones de la física; los TileMapLayer y los CanvasLayer se apagan a mano porque no
## siguen al process_mode ni a la visibilidad del padre.
## A town place (D25): the exterior or an interior. Hondoval turns on one at a time. Off it is hidden, does not
## process and takes its collisions out of physics; TileMapLayers and CanvasLayers are turned off by hand
## because they follow neither the parent's process_mode nor its visibility.

## Id con el que lo nombran las puertas / Id the doors use to name it
@export var area_id: StringName = &""
## Límites de cámara, en px locales / Camera limits, in local px
@export var camera_bounds: Rect2i = Rect2i(0, 0, 480, 270)
## Tienda del local; null = no vende (D25) / The venue's shop; null = sells nothing (D25)
@export var shop_data: ShopData
## Quién atiende la tienda / Who runs the shop
@export var shopkeeper_path: NodePath


func set_active(active: bool) -> void:
	visible = active
	process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	for layer: Node in find_children("*", "TileMapLayer", true, false):
		(layer as TileMapLayer).collision_enabled = active
	for child: Node in get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = active
	var ambience: AudioStreamPlayer = get_node_or_null("Ambience") as AudioStreamPlayer
	if ambience != null:
		ambience.playing = active


func camera_rect() -> Rect2i:
	return Rect2i(Vector2i(global_position) + camera_bounds.position, camera_bounds.size)


func marker_position(marker: StringName) -> Vector2:
	return (get_node("Markers/%s" % marker) as Node2D).global_position
