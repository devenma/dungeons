extends TextureRect

## Barra del HUD hecha con el kit: marco (este nodo), rastro de daño (Trail) y relleno (Fill).
## El relleno baja enseguida, el rastro lo alcanza después y el marco parpadea al bajar.
## Kit HUD bar: frame (this node), damage trail (Trail) and fill (Fill). The fill drops at once,
## the trail catches up later and the frame flashes on a drop.

## Marco que se muestra durante el parpadeo / Frame shown while flashing
@export var flash_texture: Texture2D
## Espera antes de que el rastro alcance al relleno (s) / Delay before the trail catches up (s)
@export var trail_delay_seconds: float = 0.3
## Duración del vaciado del rastro (s) / Trail drain duration (s)
@export var trail_drain_seconds: float = 0.25
## Duración del parpadeo, unos 3 frames a 60 fps (s) / Flash duration, about 3 frames at 60 fps (s)
@export var flash_seconds: float = 0.05

var _frame_texture: Texture2D
var _trail_tween: Tween

@onready var _fill: TextureProgressBar = $Fill
@onready var _trail: TextureProgressBar = $Trail


func _ready() -> void:
	_frame_texture = texture


func set_value(current: int, maximum: int) -> void:
	var dropped: bool = current < int(_fill.value)
	_fill.max_value = maximum
	_trail.max_value = maximum
	_fill.value = current
	if _trail_tween != null:
		_trail_tween.kill()
	if not dropped:
		_trail.value = current
		return
	_trail_tween = create_tween()
	_trail_tween.tween_interval(trail_delay_seconds)
	_trail_tween.tween_property(_trail, "value", float(current), trail_drain_seconds)
	texture = flash_texture
	var flash_tween: Tween = create_tween()
	flash_tween.tween_interval(flash_seconds)
	flash_tween.tween_callback(func() -> void: texture = _frame_texture)
