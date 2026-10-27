extends "res://scripts/combat/hitbox.gd"

## Charco que daña al pisarlo (bilis del escupebilis): vuelve a pegar cada `tick_seconds` a quien siga
## adentro, se seca en `lifetime_seconds` y se desvanece al final. Se dibuja como una mancha ovalada en el
## piso con el color de peligro (D5).
## Puddle that hurts when stepped on (spitter bile): strikes again every `tick_seconds` whoever is still
## inside, dries up after `lifetime_seconds` and fades at the end. Drawn as an oval floor stain in the hazard
## colour (D5).

# Segundos finales en que se desvanece / Final seconds over which it fades
const FADE_SECONDS: float = 0.6

## Cada cuánto vuelve a pegar, en s / How often it strikes again, in s
@export var tick_seconds: float = 0.5
## Cuánto dura, en s / How long it lasts, in s
@export var lifetime_seconds: float = 4.0
## Radio de la mancha, en px (la colisión va en la escena) / Stain radius, in px (the collider lives in the scene)
@export var radius: float = 14.0
## Color de la mancha / Stain colour
@export var color: Color = Color(0.72, 0.78, 0.16, 0.6)

var _tick_left: float = 0.0
var _life_left: float = 0.0


func _ready() -> void:
	super()
	_life_left = lifetime_seconds
	_tick_left = tick_seconds
	begin_swing()


func _physics_process(delta: float) -> void:
	_life_left -= delta
	if _life_left <= 0.0:
		queue_free()
		return
	modulate.a = clampf(_life_left / FADE_SECONDS, 0.0, 1.0)
	_tick_left -= delta
	if _tick_left <= 0.0:
		_tick_left += tick_seconds
		begin_swing()


func _draw() -> void:
	var points: PackedVector2Array = []
	for i in 16:
		var angle: float = TAU * i / 16.0
		points.append((Vector2(cos(angle) * radius, sin(angle) * radius * 0.55)).round())
	draw_colored_polygon(points, color)
	draw_polyline(points + PackedVector2Array([points[0]]), color.darkened(0.45), 1.0)
