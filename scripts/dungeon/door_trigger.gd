extends Area2D

signal room_entered(player: Node2D)

@export var target_room_path: NodePath

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if body is CharacterBody2D:
		room_entered.emit(body)