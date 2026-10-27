extends Area2D

## Altar del Voto (D23): en una zona EVENT, `interact` abre el panel de ofrendas (grupo "altar_panel").
## Tras una ofrenda se apagan las velas y no se puede volver a usar. No toca la expedición: el panel cobra.
## Altar of the Vow (D23): in an EVENT zone, `interact` opens the offering panel ("altar_panel" group).
## After an offering the candles go out and it cannot be used again. It never touches the run: the panel charges.

## Diezmo en valor de objetos por piso (1, 2, 3...); pasado el último usa el último
## Tithe in item value per floor (1, 2, 3...); past the last it uses the last
@export var tithe_by_floor: Array[int] = [15, 25, 40]

const VfxScript: GDScript = preload("res://scripts/visual/vfx.gd")
const FLAME_SHEET: Texture2D = preload("res://assets/art/environment/crypt/torch_flame.png")

var _player_inside: bool = false
var _used: bool = false

@onready var _candles: Node2D = $Candles


func _ready() -> void:
	var flame: SpriteFrames = VfxScript.strip_frames(FLAME_SHEET, 6, 10.0, true)
	for candle: Node in _candles.get_children():
		(candle as AnimatedSprite2D).sprite_frames = flame
		(candle as AnimatedSprite2D).play()
	body_entered.connect(func(body: Node2D) -> void: _player_inside = _player_inside or body is CharacterBody2D)
	body_exited.connect(func(body: Node2D) -> void: _player_inside = _player_inside and not body is CharacterBody2D)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and _player_inside and not _used:
		get_viewport().set_input_as_handled()
		get_tree().call_group("altar_panel", "open", self)


func is_used() -> bool:
	return _used


func tithe(floor_number: int) -> int:
	return tithe_by_floor[clampi(floor_number, 1, tithe_by_floor.size()) - 1]


func consume() -> void:
	_used = true
	_candles.hide()
