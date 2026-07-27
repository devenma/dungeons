extends Node2D

enum RoomType { START, COMBAT, REWARD, EVENT, EXIT }

@export var room_width: int = 1600
@export var room_height: int = 1200
@export var room_type: RoomType = RoomType.START
@export var door_east: bool = false
@export var door_west: bool = false
@export var door_north: bool = false
@export var door_south: bool = false


func _ready() -> void:
	add_to_group("room")