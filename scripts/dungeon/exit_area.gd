extends Area2D

## Floor-exit trigger (EX-4, XT-1..XT-2). Mounted by DungeonManager in the
## EXIT zone; tracks the player body and relays `exit_requested` exactly
## once on `interact` while the player is inside. The scene never touches
## RunManager: DungeonManager owns the floor transition.

signal exit_requested

@export var zone_id: int = 0

var _player_inside: bool = false
var _triggered: bool = false


func _ready() -> void:
	# Detect only the player body (same layer/mask contract as the chest).
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and _player_inside and not _triggered:
		_trigger()


func _trigger() -> void:
	if _triggered:
		return
	_triggered = true
	exit_requested.emit()


func _on_body_entered(body: Node2D) -> void:
	if body is CharacterBody2D:
		_player_inside = true


func _on_body_exited(body: Node2D) -> void:
	if body is CharacterBody2D:
		_player_inside = false
