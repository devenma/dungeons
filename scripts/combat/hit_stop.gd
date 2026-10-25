class_name HitStop
extends RefCounted

## Hit-stop (D4): a brief near-freeze of the whole game on a confirmed hit.
## Drops Engine.time_scale so movement, knockback decay, i-frames, Timers,
## tweens and stamina regen all pause together in game time (no window is
## eaten by the freeze), while input keeps arriving (combo buffering still
## works) and the pause menu stays independent. Hits during an active stop
## never add up: the stop only extends to the latest requested end.

## Escala de tiempo durante la congelación (no 0: evita delta 0 en física) / Time scale while frozen (not 0: avoids zero physics delta)
const FROZEN_TIME_SCALE: float = 0.05

static var _active: bool = false
# Fin (ms reales) de la congelación en curso / Real-time end (ms) of the running stop
static var _until_msec: int = 0
# Identifica el último timer; solo ese restaura / Identifies the latest timer; only it restores
static var _token: int = 0
static var _restore_scale: float = 1.0


static func apply(tree: SceneTree, seconds: float) -> void:
	if tree == null or seconds <= 0.0:
		return
	var until: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	if _active and until <= _until_msec:
		return
	if not _active:
		_restore_scale = Engine.time_scale
		_active = true
	_until_msec = until
	_token += 1
	var token: int = _token
	Engine.time_scale = FROZEN_TIME_SCALE
	# Real-time timer that also runs while the tree is paused.
	tree.create_timer(seconds, true, false, true).timeout.connect(
			func() -> void: _finish(token))


static func is_active() -> bool:
	return _active


static func _finish(token: int) -> void:
	if token != _token:
		return
	_active = false
	Engine.time_scale = _restore_scale
