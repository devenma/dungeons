class_name HealthComponent
extends Node

## Owns an entity's health: damage intake, change notification and death.
## Emits `health_changed(current, maximum)` on every change and `died`
## exactly once when health reaches 0 (HC-1..HC-4).

signal health_changed(current: int, maximum: int)
signal died

@export var max_health: int = 100

var current_health: int = 100
var _dead: bool = false


func _ready() -> void:
	current_health = max_health


func take_damage(info: DamageInfo) -> void:
	if _dead:
		return
	current_health = maxi(current_health - info.amount, 0)
	health_changed.emit(current_health, max_health)
	if current_health == 0:
		_dead = true
		died.emit()


func reset_health() -> void:
	_dead = false
	current_health = max_health
	health_changed.emit(current_health, max_health)
