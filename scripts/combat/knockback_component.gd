class_name KnockbackComponent
extends Node

## Turns the knockback of accepted hits into a short push. Listens to the
## sibling Health's `damage_received`; the owner's movement calls
## `consume(delta)` every physics frame and, while it returns non-zero,
## moves with that velocity instead of its own (brief stagger).
## DamageInfo.knockback is the push's initial speed in px/s; it decays
## linearly to zero over `decay_seconds`.

@export var health_node_path: NodePath = NodePath("../Health")
@export var decay_seconds: float = 0.2

var _velocity: Vector2 = Vector2.ZERO
var _decel: float = 0.0


func _ready() -> void:
	var health := get_node_or_null(health_node_path) as HealthComponent
	if health != null:
		health.damage_received.connect(_on_damage_received)


func apply(impulse: Vector2) -> void:
	if impulse == Vector2.ZERO:
		return
	_velocity = impulse
	_decel = impulse.length() / maxf(decay_seconds, 0.001)


func consume(delta: float) -> Vector2:
	var current: Vector2 = _velocity
	_velocity = _velocity.move_toward(Vector2.ZERO, _decel * delta)
	return current


func _on_damage_received(info: DamageInfo) -> void:
	apply(info.knockback)
