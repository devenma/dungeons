class_name StaminaComponent
extends Node

## Owns an entity's stamina pool: spending, change notification and
## regeneration. Emits `stamina_changed(current, maximum)` on every change.
## Regeneration accumulates fractional progress and transfers to the pool
## only at whole-tick boundaries so the bar ticks crisply (ST-component,
## ST-regen).

signal stamina_changed(current: int, maximum: int)

@export var max_stamina: int = 100
@export var stamina_regen_per_second: float = 20.0

var current_stamina: int = 100
var _regen_accumulator: float = 0.0


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


func _process(delta: float) -> void:
	_regen_accumulator += stamina_regen_per_second * delta
	while _regen_accumulator >= 1.0 and current_stamina < max_stamina:
		current_stamina += 1
		_regen_accumulator -= 1.0
		stamina_changed.emit(current_stamina, max_stamina)
	if current_stamina >= max_stamina:
		_regen_accumulator = 0.0
