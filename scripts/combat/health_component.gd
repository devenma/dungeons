class_name HealthComponent
extends Node

## Owns an entity's health: damage intake, change notification and death.
## Emits `health_changed(current, maximum)` on every change and `died`
## exactly once when health reaches 0 (HC-1..HC-4).
## Accepted hits also emit `damage_received(info)`, which feedback
## components (KnockbackComponent, HitFlash) listen to. With
## `invulnerability_seconds` > 0, hits inside that window after an accepted
## hit are ignored entirely (i-frames). `grant_invulnerability` adds a
## separate window (the roll) that also ignores hits but does not blink.

signal health_changed(current: int, maximum: int)
## Golpe aceptado (no ignorado por i-frames) / Accepted hit (not swallowed by i-frames)
signal damage_received(info: DamageInfo)
signal died

## Vida máxima (puntos) / Max health (points)
@export var max_health: int = 100
## Segundos de invulnerabilidad tras un golpe; 0 = sin i-frames / I-frame seconds after a hit; 0 = none
@export var invulnerability_seconds: float = 0.0

var current_health: int = 100
var _dead: bool = false
# Segundos de i-frames restantes / Remaining i-frame seconds
var _invulnerable_left: float = 0.0
# Segundos de invulnerabilidad otorgada (voltereta), sin parpadeo / Granted invulnerability seconds left (roll), no blink
var _granted_left: float = 0.0


func _ready() -> void:
	current_health = max_health


func _process(delta: float) -> void:
	if _invulnerable_left > 0.0:
		_invulnerable_left = maxf(_invulnerable_left - delta, 0.0)
	if _granted_left > 0.0:
		_granted_left = maxf(_granted_left - delta, 0.0)


func is_invulnerable() -> bool:
	return _invulnerable_left > 0.0


func is_dead() -> bool:
	return _dead


## Ignora los golpes durante `seconds` sin el parpadeo de los i-frames / Ignores hits for `seconds` without the i-frame blink
func grant_invulnerability(seconds: float) -> void:
	_granted_left = maxf(_granted_left, seconds)


## Devuelve true si el golpe se aceptó (no muerto ni en i-frames) / Returns true when the hit was accepted (not dead, not in i-frames)
func take_damage(info: DamageInfo) -> bool:
	if _dead or is_invulnerable() or _granted_left > 0.0:
		return false
	current_health = maxi(current_health - info.amount, 0)
	_invulnerable_left = invulnerability_seconds
	health_changed.emit(current_health, max_health)
	damage_received.emit(info)
	if current_health == 0:
		_dead = true
		died.emit()
	return true


func reset_health() -> void:
	_dead = false
	_invulnerable_left = 0.0
	_granted_left = 0.0
	current_health = max_health
	health_changed.emit(current_health, max_health)


## Cambia el máximo en runtime (mejoras, ofrenda de carne); la vida actual nunca lo pasa
## Changes the max at runtime (upgrades, flesh offering); current health never exceeds it
func set_max_health(value: int) -> void:
	max_health = maxi(value, 1)
	current_health = mini(current_health, max_health)
	health_changed.emit(current_health, max_health)


## Llena la vida sin tocar la muerte ni los i-frames (altar) / Fills health without touching death or i-frames (altar)
func heal_full() -> void:
	current_health = max_health
	health_changed.emit(current_health, max_health)


## Cura hasta el máximo y devuelve lo curado; muerto no cura (vial, D25) / Heals up to the max and returns the amount healed; dead it does not heal (vial, D25)
func heal(amount: int) -> int:
	if _dead:
		return 0
	var healed: int = clampi(amount, 0, max_health - current_health)
	current_health += healed
	health_changed.emit(current_health, max_health)
	return healed
