extends Node2D

## Hondoval (D25): el pueblo y el hub con el que habla DungeonManager. Pide la expedición desde la entrada a la
## cripta, se apaga mientras dura y al volver te deja en el gremio. Prende un área por vez (el exterior o un
## interior) y las puertas llevan de una a otra con un fundido a negro. Atiende lo que se toca en el pueblo:
## el almacén y el tablón del gremio, la tienda de cada local y el saludo de los NPCs, que la primera vez
## comentan cómo volviste.
## Hondoval (D25): the town and the hub DungeonManager talks to. It requests the expedition from the crypt
## entrance, is switched off while it lasts and on return leaves you in the guild. It turns on one area at a
## time (the exterior or an interior) and doors lead between them with a fade from black. It handles what is
## touched in town: the guild's storage and notice board, each venue's shop and the NPCs' greetings, which
## remark on how you came back the first time.

signal expedition_requested

const UiText: GDScript = preload("res://scripts/ui/ui_text.gd")

@export var camera_manager_path: NodePath = NodePath("../CameraLimitManager")
@export var run_manager_path: NodePath = NodePath("../../RunManager")
@export var profile_state_path: NodePath = NodePath("../../ProfileState")
@export var backpack_panel_path: NodePath = NodePath("../../UI/BackpackPanel")
## Duración del fundido al cruzar una puerta, en s / Fade duration when crossing a door, in s
@export var fade_seconds: float = 0.25

var _current: Node2D
# Cómo volvió el jugador (death, return_stone, victory) y a quién ya se lo comentaron; vacío = nada que comentar
# How the player came back (death, return_stone, victory) and who already remarked on it; empty = nothing to say
var _mood: String = ""
var _told: Array[Node] = []

@onready var _guild: Node2D = $Guild
@onready var _ui: CanvasLayer = $TownUI
@onready var _fade: ColorRect = $TownUI/Fade
@onready var _dialogue: Node = $TownUI/DialogueBox
@onready var _shop: Node = $TownUI/ShopPanel
@onready var _clock: Node = $WorldClock


func _ready() -> void:
	for door: Node in find_children("*", "Area2D", true, false):
		if door.is_in_group("town_door"):
			door.interacted.connect(_use_door.bind(door))
			var leaving: bool = door.get("target_area") == &"exterior"
			_set_hint(door, "ui.prompt.leave" if leaving else "ui.prompt.enter", "Leave" if leaving else "Enter")
	var crypt: Node = $Exterior/CryptEntrance
	crypt.interacted.connect(expedition_requested.emit)
	_set_hint(crypt, "ui.prompt.descend", "Go down")
	$Guild/StorageChest.interacted.connect(open_storage)
	_set_hint($Guild/StorageChest, "ui.prompt.open", "Storage")
	$Guild/NoticeBoard.interacted.connect(func() -> void: say(UiText.tr_or("npc.questgiver.quest.none",
			"No bounties today. That's either very good or very bad news.")))
	_set_hint($Guild/NoticeBoard, "ui.prompt.interact", "Board")
	var keepers: Array[Node] = []
	for area: Node in _areas():
		if area.get("shop_data") != null:
			var keeper: Node = area.get_node(area.get("shopkeeper_path") as NodePath)
			keeper.interacted.connect(open_shop.bind(area))
			_set_hint(keeper, "ui.prompt.talk", "Shop")
			keepers.append(keeper)
	for npc: Node in find_children("*", "Area2D", true, false):
		if npc.has_method("greeting") and not keepers.has(npc):
			npc.interacted.connect(_greet.bind(npc))
	$Guild/Bed.interacted.connect(_sleep)
	_set_hint($Guild/Bed, "ui.prompt.sleep", "Sleep")
	_clock.connect("phase_changed", _on_phase_changed)
	_on_phase_changed(_clock.call("is_night") as bool)
	_current = _guild


## Prendido deja activa solo el área del gremio, porque siempre se vuelve ahí; apagado apaga todo.
## On it leaves only the guild area active, because you always come back there; off it turns everything off.
func set_active(active: bool) -> void:
	visible = active
	process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	_ui.visible = active
	_dialogue.hide()
	for area: Node in _areas():
		area.call("set_active", active and area == _guild)
	_current = _guild
	if active:
		_clock.call("refresh")


func spawn_position() -> Vector2:
	return _guild.call("marker_position", &"spawn") as Vector2


func camera_rect() -> Rect2i:
	return _current.call("camera_rect") as Rect2i


func current_area() -> StringName:
	return _current.get("area_id") as StringName


func set_mood(mood: String) -> void:
	_mood = mood
	_told.clear()


func say(text: String) -> void:
	_dialogue.say(text)


func go_to(area_id: StringName, marker: StringName) -> void:
	var target: Node2D = _area(area_id)
	if target == null:
		push_warning("Hondoval: no area '%s'" % area_id)
		return
	_current.call("set_active", false)
	target.call("set_active", true)
	_current = target
	_dialogue.hide()
	var player: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	if player != null:
		player.global_position = target.call("marker_position", marker) as Vector2
		var cam_manager: Node = get_node_or_null(camera_manager_path)
		if cam_manager != null:
			cam_manager.call("frame_rect", player, camera_rect())
	_fade.modulate.a = 1.0
	create_tween().tween_property(_fade, "modulate:a", 0.0, fade_seconds)


func open_storage() -> void:
	var panel: Control = get_node_or_null(backpack_panel_path) as Control
	if panel != null:
		panel.call("set_open", true)


## Abre la tienda del local con su ShopData / Opens the venue's shop with its ShopData
func open_shop(area: Node) -> void:
	var run_manager: RunManager = get_node_or_null(run_manager_path) as RunManager
	var profile: ProfileState = get_node_or_null(profile_state_path) as ProfileState
	if run_manager == null or profile == null:
		return
	_shop.call("open", run_manager, profile, area.get("shop_data"))


func _greet(npc: Node) -> void:
	say(npc.call("greeting", "" if _told.has(npc) else _mood))
	_told.append(npc)


func _use_door(door: Node) -> void:
	if door.get("closes_at_night") and _clock.call("is_night"):
		say(UiText.tr_or("ui.town.closed", "Closed. Come back by day."))
		return
	go_to(door.get("target_area") as StringName, door.get("target_marker") as StringName)


func _sleep() -> void:
	if not _clock.call("sleep"):
		say(UiText.tr_or("ui.town.not_sleepy", "You are not tired yet. It is still day outside."))


# De noche las puertas de los locales dicen que están cerradas / At night the shops' doors say they are closed
func _on_phase_changed(night: bool) -> void:
	for door: Node in find_children("*", "Area2D", true, false):
		if door.is_in_group("town_door") and door.get("closes_at_night"):
			_set_hint(door, "ui.prompt.closed" if night else "ui.prompt.enter", "Closed" if night else "Enter")


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
