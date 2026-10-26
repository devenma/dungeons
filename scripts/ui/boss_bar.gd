extends Control

## Barra de vida del jefe (D21): oculta hasta que un jefe despierta y llama a `track` por el grupo
## "boss_bar"; se oculta cuando muere o se va con el piso. Marco y rellenos estirados en 9 partes con el
## arte de la barra de vida, así el ancho no deforma el pixel art.
## Boss health bar (D21): hidden until a boss wakes and calls `track` through the "boss_bar" group;
## hides when it dies or leaves with the floor. Frame and fills are 9-slice stretched from the health
## bar art, so the width does not distort the pixel art.

const UiText: GDScript = preload("res://scripts/ui/ui_text.gd")

## Espera antes de que el rastro alcance al relleno (s) / Delay before the trail catches up (s)
@export var trail_delay_seconds: float = 0.3
## Duración del vaciado del rastro (s) / Trail drain duration (s)
@export var trail_drain_seconds: float = 0.25

var _health: HealthComponent
var _trail_tween: Tween

@onready var _name: Label = $Name
@onready var _fill: TextureProgressBar = $Frame/Fill
@onready var _trail: TextureProgressBar = $Frame/Trail


func _ready() -> void:
	add_to_group("boss_bar")
	hide()


func track(health: HealthComponent, name_key: String) -> void:
	_health = health
	_name.text = UiText.tr_or(name_key, name_key)
	health.health_changed.connect(set_value)
	health.died.connect(hide)
	health.tree_exiting.connect(hide)
	_fill.max_value = health.max_health
	_trail.max_value = health.max_health
	_fill.value = health.current_health
	_trail.value = health.current_health
	show()


func set_value(current: int, _maximum: int) -> void:
	_fill.value = current
	if _trail_tween != null:
		_trail_tween.kill()
	_trail_tween = create_tween()
	_trail_tween.tween_interval(trail_delay_seconds)
	_trail_tween.tween_property(_trail, "value", float(current), trail_drain_seconds)
