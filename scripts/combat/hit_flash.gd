class_name HitFlash
extends Node

## Damage feedback on the owner's visual: a bright flash on every accepted
## hit (sibling Health's `damage_received`) and, while the Health has
## i-frames, an alpha blink. Flash uses `modulate`, blink uses
## `self_modulate`, so the two never fight.

@export var health_node_path: NodePath = NodePath("../Health")
## Nodo que destella y parpadea / Node that flashes and blinks
@export var visual_path: NodePath
## Color del destello (valores > 1 aclaran) / Flash color (values > 1 brighten)
@export var flash_color: Color = Color(2.0, 2.0, 2.0, 1.0)
## Duración del destello (s) / Flash duration (s)
@export var flash_seconds: float = 0.12
## Intervalo del parpadeo durante i-frames (s) / Blink interval during i-frames (s)
@export var blink_interval: float = 0.08

var _health: HealthComponent = null
var _visual: CanvasItem = null
var _tween: Tween = null
# Tiempo acumulado del parpadeo / Accumulated blink time
var _blink_clock: float = 0.0


func _ready() -> void:
	_health = get_node_or_null(health_node_path) as HealthComponent
	_visual = get_node_or_null(visual_path) as CanvasItem
	if _health != null and _visual != null:
		_health.damage_received.connect(_on_damage_received)


func _process(delta: float) -> void:
	if _health == null or _visual == null:
		return
	if _health.is_invulnerable():
		_blink_clock += delta
		var visible_phase: bool = int(_blink_clock / blink_interval) % 2 == 1
		_visual.self_modulate.a = 1.0 if visible_phase else 0.35
	elif _visual.self_modulate.a != 1.0:
		_blink_clock = 0.0
		_visual.self_modulate.a = 1.0


func _on_damage_received(_info: DamageInfo) -> void:
	if _tween != null:
		_tween.kill()
	_visual.modulate = flash_color
	_tween = create_tween()
	_tween.tween_property(_visual, "modulate", Color.WHITE, flash_seconds)
