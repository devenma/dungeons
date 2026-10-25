extends Node

## Temblor corto de la Camera2D padre, solo con su `offset` en px enteros (escala entera, §38.1): no toca los
## límites ni la transición de zona. Tiembla cuando el jugador recibe un golpe y cuando una Hitbox lo pide
## (tercer golpe del combo) por el grupo "camera_shake". Corre en tiempo real: sigue durante el hit-stop.
## Short shake of the parent Camera2D, only through its `offset` in whole px (integer scaling, §38.1): it
## never touches the limits or the zone transition. Shakes when the player takes a hit and when a Hitbox
## asks for it (3rd combo hit) through the "camera_shake" group. Runs in real time: it keeps going during hit-stop.

@export var health_node_path: NodePath = NodePath("../../Health")
## Temblor al recibir un golpe (px enteros) / Shake when taking a hit (whole px)
@export var hurt_shake_pixels: int = 2
## Duración de cada temblor (s reales) / Duration of each shake (real s)
@export var shake_seconds: float = 0.14

# Amplitud del temblor en curso (px) / Current shake amplitude (px)
var _pixels: int = 0
# Inicio y fin del temblor en ms reales / Shake start and end in real ms
var _start_msec: int = 0
var _end_msec: int = 0

@onready var _camera: Camera2D = get_parent() as Camera2D


func _ready() -> void:
	add_to_group("camera_shake")
	var health: HealthComponent = get_node_or_null(health_node_path) as HealthComponent
	if health != null:
		health.damage_received.connect(func(_info: DamageInfo) -> void: shake(hurt_shake_pixels))


## Un temblor más chico no pisa a uno más fuerte en curso / A weaker shake never overrides a stronger running one
func shake(pixels: int) -> void:
	var now: int = Time.get_ticks_msec()
	if now < _end_msec and pixels < _current_amplitude(now):
		return
	_pixels = pixels
	_start_msec = now
	_end_msec = now + int(shake_seconds * 1000.0)


func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	if now >= _end_msec:
		_camera.offset = Vector2.ZERO
		return
	var amplitude: int = _current_amplitude(now)
	_camera.offset = Vector2(randi_range(-amplitude, amplitude), randi_range(-amplitude, amplitude))


# Decae lineal hasta 0, redondeada hacia arriba / Linear decay to 0, rounded up
func _current_amplitude(now: int) -> int:
	var remaining: float = float(_end_msec - now) / maxf(float(_end_msec - _start_msec), 1.0)
	return ceili(_pixels * clampf(remaining, 0.0, 1.0))
