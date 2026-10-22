class_name HealthComponent
extends Node

## Owns an entity's health: damage intake, change notification and death.
## Emits `health_changed(current, maximum)` on every change and `died`
## exactly once when health reaches 0 (HC-1..HC-4).
## Accepted hits also emit `damage_received(info)`, which feedback
## components (KnockbackComponent, HitFlash) listen to. With
## `invulnerability_seconds` > 0, hits inside that window after an accepted
## hit are ignored entirely (i-frames).

signal health_changed(current: int, maximum: int)
signal damage_received(info: DamageInfo)
signal died

@export var max_health: int = 100
## I-frames after an accepted hit; 0 = none (enemies).
@export var invulnerability_seconds: float = 0.0

var current_health: int = 100
var _dead: bool = false
var _invulnerable_left: float = 0.0


func _ready() -> void:
	current_health = max_health


func _process(delta: float) -> void:
	if _invulnerable_left > 0.0:
		_invulnerable_left = maxf(_invulnerable_left - delta, 0.0)


func is_invulnerable() -> bool:
	return _invulnerable_left > 0.0


func take_damage(info: DamageInfo) -> void:
	if _dead or is_invulnerable():
		return
	current_health = maxi(current_health - info.amount, 0)
	_invulnerable_left = invulnerability_seconds
	health_changed.emit(current_health, max_health)
	damage_received.emit(info)
	if current_health == 0:
		_dead = true
		died.emit()


func reset_health() -> void:
	_dead = false
	_invulnerable_left = 0.0
	current_health = max_health
	health_changed.emit(current_health, max_health)
