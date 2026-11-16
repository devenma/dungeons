extends StaticBody2D

## Banco de la muestra del gremio: `interact` sienta al jugador en `Seat` mirando hacia `facing` y otro `interact`
## lo levanta en `StandPoint`. Cada pulsación la atiende un solo banco.
## Guild preview bench: `interact` sits the player on `Seat` facing `facing` and another `interact` stands it up on
## `StandPoint`. Each press is handled by a single bench.

const PreviewPlayerScript: GDScript = preload("res://scripts/preview/preview_player.gd")

# Hacia dónde mira quien se sienta: S, E, N o W / Facing of whoever sits: S, E, N or W
@export var facing: String = "S"

@onready var seat: Marker2D = $Seat


func _ready() -> void:
	$Interact.interacted.connect(_on_interacted)


# Sentado, la colisión del jugador está apagada y el área no lo ve: el banco atiende `interact` directo
# Seated, the player's collision is off and the area cannot see it: the bench takes `interact` directly
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	var player: PreviewPlayerScript = _player()
	if player != null and player.seated_bench == self:
		_on_interacted()


func _on_interacted() -> void:
	var player: PreviewPlayerScript = _player()
	if player.seated_bench == self:
		player.stand()
	elif player.seated_bench == null:
		player.sit(self, seat.global_position, facing)
	else:
		return
	get_viewport().set_input_as_handled()


func _player() -> PreviewPlayerScript:
	return get_tree().get_first_node_in_group("player") as PreviewPlayerScript
