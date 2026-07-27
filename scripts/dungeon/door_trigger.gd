extends Area2D

signal room_entered(player: Node2D)

@export var target_room_path: NodePath
@export var exit_direction: String = "east"  # "east", "west", "north", "south"

func _ready() -> void:
	body_entered.connect(_on_body_entered_or_exited)
	body_exited.connect(_on_body_entered_or_exited)

func _on_body_entered_or_exited(body: Node2D) -> void:
	if body is CharacterBody2D:
		if exit_direction == "east" and body.velocity.x <= 0:
			return
		if exit_direction == "west" and body.velocity.x >= 0:
			return
		if exit_direction == "north" and body.velocity.y <= 0:
			return
		if exit_direction == "south" and body.velocity.y >= 0:
			return
		room_entered.emit(body)