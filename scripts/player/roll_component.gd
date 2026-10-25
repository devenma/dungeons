class_name RollComponent
extends Node

## Voltereta de esquive del jugador (reemplaza al dash previsto): cuesta stamina, recorre una distancia fija
## en una dirección y no se cancela. Da invulnerabilidad casi todo el tramo por HealthComponent, sin el
## parpadeo de los i-frames. No se ataca rodando: el último ataque pedido queda guardado y sale al terminar.
## player.gd la dispara y lee su velocidad; los números se tocan acá desde el Inspector.
## Player dodge roll (replaces the planned dash): costs stamina, covers a fixed distance in one direction and
## cannot be cancelled. Grants invulnerability for most of it through HealthComponent, without the i-frame
## blink. No attacking mid-roll: the last requested attack is buffered and fires when it ends.
## player.gd triggers it and reads its velocity; the numbers are tuned here in the Inspector.

@export var health_node_path: NodePath = NodePath("../Health")
@export var stamina_node_path: NodePath = NodePath("../Stamina")
@export var weapons_node_path: NodePath = NodePath("../Weapons")
@export var sound_node_path: NodePath = NodePath("../RollSound")
## Duración de la voltereta (s) / Roll duration (s)
@export var roll_seconds: float = 0.4
## Distancia que recorre (px) / Distance covered (px)
@export var roll_distance: float = 64.0
## Invulnerabilidad desde el inicio (s); el final queda expuesto / Invulnerability from the start (s); the tail is exposed
@export var invulnerable_seconds: float = 0.3
## Stamina por voltereta (puntos) / Stamina per roll (points)
@export var stamina_cost: int = 25

# Segundos que le quedan a la voltereta / Seconds left in the roll
var _left: float = 0.0
var _direction: Vector2 = Vector2.DOWN
# Ataque pedido durante la voltereta y su apuntado / Attack requested mid-roll and its aim
var _attack_buffered: bool = false
var _buffered_aim: Vector2 = Vector2.ZERO

@onready var _health: HealthComponent = get_node_or_null(health_node_path) as HealthComponent
@onready var _stamina: StaminaComponent = get_node_or_null(stamina_node_path) as StaminaComponent
@onready var _weapons: Node = get_node_or_null(weapons_node_path)
@onready var _sound: AudioStreamPlayer2D = get_node_or_null(sound_node_path) as AudioStreamPlayer2D


func try_roll(direction: Vector2) -> bool:
	if is_rolling() or direction == Vector2.ZERO:
		return false
	if _stamina != null and not _stamina.try_spend(stamina_cost):
		return false
	_direction = direction.normalized()
	_left = roll_seconds
	_attack_buffered = false
	if _health != null:
		_health.grant_invulnerability(invulnerable_seconds)
	if _sound != null:
		_sound.play()
	return true


func is_rolling() -> bool:
	return _left > 0.0


## Velocidad de la voltereta (px/s); cero si no rueda / Roll velocity (px/s); zero when not rolling
func roll_velocity() -> Vector2:
	if not is_rolling():
		return Vector2.ZERO
	return _direction * roll_distance / maxf(roll_seconds, 0.001)


## Rodando, guarda el ataque para el final y devuelve true / While rolling, buffers the attack for the end and returns true
func buffer_attack(aim: Vector2) -> bool:
	if not is_rolling():
		return false
	_attack_buffered = true
	_buffered_aim = aim
	return true


func _physics_process(delta: float) -> void:
	if not is_rolling():
		return
	_left -= delta
	if _left > 0.0:
		return
	_left = 0.0
	if _attack_buffered and _weapons != null:
		_attack_buffered = false
		for weapon: Node in _weapons.get_children():
			if weapon.has_method("try_attack"):
				weapon.call("try_attack", _buffered_aim)
