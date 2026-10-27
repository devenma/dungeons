extends "res://scripts/combat/hitbox.gd"

## Golpe de área de una habilidad (tajo giratorio, explosión de la bola de fuego): un círculo de `radius`
## que pega una vez a cada enemigo durante `active_seconds`, empujando desde el centro, con un anillo que
## se abre y se apaga. Quien lo crea le pasa `damage`, `knockback` (fuerza) y `radius`.
## Ability area hit (spinning slash, fireball explosion): a `radius` circle that hits each enemy once
## during `active_seconds`, pushing away from the centre, with a ring that opens and fades. Whoever
## creates it hands it `damage`, `knockback` (strength) and `radius`.

## Radio del área, en px / Area radius, in px
@export var radius: float = 40.0
## Tiempo que pega, en s / Time it hits, in s
@export var active_seconds: float = 0.15
## Duración del anillo, en s / Ring duration, in s
@export var ring_seconds: float = 0.25
## Color del anillo / Ring colour
@export var color: Color = Color(1.0, 0.95, 0.85)

var _ring: float = 0.0
# Tiempo de física que le queda pegando y pasos ya dados: con al menos 2 pasos el solape siempre se detecta
# Physics time left hitting and steps taken: with at least 2 steps the overlap is always detected
var _active_left: float = 0.0
var _steps: int = 0


func _ready() -> void:
	radial_knockback = true
	var shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	add_child(shape)
	super()
	z_index = 2
	begin_swing()
	var tween: Tween = create_tween()
	tween.tween_method(_set_ring, 0.3, 1.0, ring_seconds)
	tween.parallel().tween_property(self, "modulate:a", 0.0, ring_seconds)
	_active_left = active_seconds
	tween.finished.connect(_free_when_done)


func _physics_process(delta: float) -> void:
	_active_left -= delta
	_steps += 1
	if _active_left <= 0.0 and _steps >= 2:
		end_swing()
		set_physics_process(false)
		_free_when_done()


# Se va cuando terminaron el anillo y el golpe / Leaves once both the ring and the hit are over
func _free_when_done() -> void:
	if not is_physics_processing() and modulate.a <= 0.0:
		queue_free()


func _set_ring(progress: float) -> void:
	_ring = progress
	queue_redraw()


func _draw() -> void:
	draw_arc(Vector2.ZERO, roundf(radius * _ring), 0.0, TAU, 32, color, 2.0)
