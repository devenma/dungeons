class_name StaminaComponent
extends Node

## Owns an entity's stamina pool: spending, change notification and
## regeneration. Emits `stamina_changed(current, maximum)` on every change.
## Regeneration accumulates fractional progress and transfers to the pool
## only at whole-tick boundaries so the bar ticks crisply (ST-component,
## ST-regen).

signal stamina_changed(current: int, maximum: int)

## Stamina máxima (puntos) / Max stamina (points)
@export var max_stamina: int = 100
## Regeneración (puntos/s) / Regeneration (points/s)
@export var stamina_regen_per_second: float = 20.0

var current_stamina: int = 100
var _regen_accumulator: float = 0.0
# Segundos que le quedan sin regenerar (la Nana de la Madre, D21) / Seconds left without regeneration (the Mother's Lullaby, D21)
var _suppressed_left: float = 0.0


func _ready() -> void:
	current_stamina = max_stamina


## Unconditional spend: clamps at 0 and notifies. Use for costs the caller
## has already validated via try_spend.
func spend(amount: int) -> void:
	current_stamina = maxi(current_stamina - amount, 0)
	stamina_changed.emit(current_stamina, max_stamina)


## Conditional spend: silent refusal (false) when the pool is below the
## cost; the pool stays untouched (ST-component / ST-weapon-gating).
func try_spend(amount: int) -> bool:
	if current_stamina < amount:
		return false
	spend(amount)
	return true


## Refill to maximum and clear any pending fractional regen.
func reset_full() -> void:
	current_stamina = max_stamina
	_regen_accumulator = 0.0
	stamina_changed.emit(current_stamina, max_stamina)


## Cambia el máximo en runtime (mejoras); la stamina actual nunca lo pasa / Changes the max at runtime (upgrades); current stamina never exceeds it
func set_max_stamina(value: int) -> void:
	max_stamina = maxi(value, 1)
	current_stamina = mini(current_stamina, max_stamina)
	stamina_changed.emit(current_stamina, max_stamina)


## Corta la regeneración durante `seconds` (no acumula: gana la más larga) / Stops regeneration for `seconds` (does not stack: the longest wins)
func suppress_regen(seconds: float) -> void:
	_suppressed_left = maxf(_suppressed_left, seconds)


func _process(delta: float) -> void:
	if _suppressed_left > 0.0:
		_suppressed_left = maxf(_suppressed_left - delta, 0.0)
		_regen_accumulator = 0.0
		return
	_regen_accumulator += stamina_regen_per_second * delta
	while _regen_accumulator >= 1.0 and current_stamina < max_stamina:
		current_stamina += 1
		_regen_accumulator -= 1.0
		stamina_changed.emit(current_stamina, max_stamina)
	if current_stamina >= max_stamina:
		_regen_accumulator = 0.0
