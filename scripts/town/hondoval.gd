extends Node2D

## Hondoval (D25): el pueblo y el hub con el que habla DungeonManager. Pide la expedición desde la entrada a la
## cripta, se apaga mientras dura y al volver te deja en el gremio. Prende un área por vez (el exterior o un
## interior) y las puertas llevan de una a otra con un fundido a negro.
## Hondoval (D25): the town and the hub DungeonManager talks to. It requests the expedition from the crypt
## entrance, is switched off while it lasts and on return leaves you in the guild. It turns on one area at a
## time (the exterior or an interior) and doors lead between them with a fade from black.

signal expedition_requested

const UiText: GDScript = preload("res://scripts/ui/ui_text.gd")

@export var camera_manager_path: NodePath = NodePath("../CameraLimitManager")
## Duración del fundido al cruzar una puerta, en s / Fade duration when crossing a door, in s
@export var fade_seconds: float = 0.25

var _current: Node2D

@onready var _guild: Node2D = $Guild
@onready var _ui: CanvasLayer = $TownUI
@onready var _fade: ColorRect = $TownUI/Fade


func _ready() -> void:
	for door: Node in find_children("*", "Area2D", true, false):
		if door.is_in_group("town_door"):
			door.interacted.connect(_use_door.bind(door))
			var leaving: bool = door.get("target_area") == &"exterior"
			_set_hint(door, "ui.prompt.leave" if leaving else "ui.prompt.enter", "Leave" if leaving else "Enter")
	var crypt: Node = $Exterior/CryptEntrance
	crypt.interacted.connect(expedition_requested.emit)
	_set_hint(crypt, "ui.prompt.descend", "Go down")
	_current = _guild


## Prendido deja activa solo el área del gremio, porque siempre se vuelve ahí; apagado apaga todo.
## On it leaves only the guild area active, because you always come back there; off it turns everything off.
func set_active(active: bool) -> void:
	visible = active
	process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	_ui.visible = active
	for area: Node in _areas():
		area.call("set_active", active and area == _guild)
	_current = _guild


func spawn_position() -> Vector2:
	return _guild.call("marker_position", &"spawn") as Vector2


func camera_rect() -> Rect2i:
	return _current.call("camera_rect") as Rect2i


func current_area() -> StringName:
	return _current.get("area_id") as StringName


func set_mood(mood: String) -> void:
	_guild.call("set_mood", mood)


func go_to(area_id: StringName, marker: StringName) -> void:
	var target: Node2D = _area(area_id)
	if target == null:
		push_warning("Hondoval: no area '%s'" % area_id)
		return
	_current.call("set_active", false)
	target.call("set_active", true)
	_current = target
	var player: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	if player != null:
		player.global_position = target.call("marker_position", marker) as Vector2
		var cam_manager: Node = get_node_or_null(camera_manager_path)
		if cam_manager != null:
			cam_manager.call("frame_rect", player, camera_rect())
	_fade.modulate.a = 1.0
	create_tween().tween_property(_fade, "modulate:a", 0.0, fade_seconds)


func _use_door(door: Node) -> void:
	go_to(door.get("target_area") as StringName, door.get("target_marker") as StringName)


func _areas() -> Array[Node]:
	var areas: Array[Node] = []
	for child: Node in get_children():
		if child.has_method("marker_position"):
			areas.append(child)
	return areas


func _area(area_id: StringName) -> Node2D:
	for area: Node in _areas():
		if area.get("area_id") == area_id:
			return area as Node2D
	return null


# Texto del cartel de un punto de interacción, traducido / Translated hint text of an interact spot
func _set_hint(spot: Node, key: String, fallback: String) -> void:
	var hint: Label = spot.get_node_or_null("Hint") as Label
	if hint != null:
		hint.text = UiText.tr_or(key, "%s " + fallback) % "[F]"
