class_name ZoneFog
extends Node2D

## Tapa todo lo que está fuera de la zona actual, para que las salas chicas
## no dejen ver a sus vecinas. / Covers everything outside the current zone
## so small rooms do not reveal their neighbors.
## Drawn at z_index 1: above the floor TileMap and enemies (z 0), below the
## player (z 2) so the player stays visible while crossing a door.

## Color de la niebla / Fog color
@export var fog_color: Color = Color(0.0, 0.0, 0.0, 1.0)

# Rectángulo visible en píxeles de mundo (vacío = sin niebla) / Visible rect in world px (empty = no fog)
var visible_rect: Rect2 = Rect2()

# Margen que cubre la niebla alrededor de la zona / How far the fog extends around the zone
const FOG_EXTENT: float = 10000.0


func focus(rect: Rect2) -> void:
	visible_rect = rect
	queue_redraw()


func _draw() -> void:
	if visible_rect.size == Vector2.ZERO:
		return
	var r: Rect2 = visible_rect
	var outer: Rect2 = r.grow(FOG_EXTENT)
	# Arriba, abajo, izquierda y derecha de la zona / Above, below, left and right of the zone
	draw_rect(Rect2(outer.position, Vector2(outer.size.x, r.position.y - outer.position.y)), fog_color)
	draw_rect(Rect2(Vector2(outer.position.x, r.end.y), Vector2(outer.size.x, outer.end.y - r.end.y)), fog_color)
	draw_rect(Rect2(Vector2(outer.position.x, r.position.y), Vector2(r.position.x - outer.position.x, r.size.y)), fog_color)
	draw_rect(Rect2(Vector2(r.end.x, r.position.y), Vector2(outer.end.x - r.end.x, r.size.y)), fog_color)
