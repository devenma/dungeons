extends Area2D

## Puerta de la bóveda (D3): con el jugador al lado, `interact` pide abrirla. DungeonManager decide: si hay
## llave en la mochila la gasta y la abre; si no, suena la traba. Como ExitArea, no toca la expedición.
## Vault door (D3): with the player next to it, `interact` asks to open it. DungeonManager decides: with a
## key in the backpack it spends it and opens the door; otherwise the lock rattles. Like ExitArea, it never
## touches the run.

signal unlock_requested(door_id: int)

## Puerta trabada que cubre / Locked door it covers
var door_id: int = -1

var _player_inside: bool = false


func _ready() -> void:
	collision_layer = 0
	collision_mask = CollisionLayers.PLAYER_BODY
	body_entered.connect(func(body: Node2D) -> void: _player_inside = _player_inside or body.is_in_group("player"))
	body_exited.connect(func(body: Node2D) -> void: _player_inside = _player_inside and not body.is_in_group("player"))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and _player_inside:
		get_viewport().set_input_as_handled()
		unlock_requested.emit(door_id)
