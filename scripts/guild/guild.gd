extends Node2D

## Gremio (hub, D2): primera escena del juego. El cofre del depósito abre el panel de mochila y
## almacén; el portón pide una expedición, que arma DungeonManager. La reducidora abre la tienda,
## el resto de los NPC saluda y el tablón muestra una línea.
## Guild (hub, D2): the game's first scene. The storage chest opens the backpack and storage
## panel; the gate requests an expedition, which DungeonManager builds. The fence opens the
## shop, the other NPCs greet and the notice board shows a line.

signal expedition_requested

const UiText: GDScript = preload("res://scripts/ui/ui_text.gd")

@export var run_manager_path: NodePath = NodePath("../../RunManager")
@export var profile_state_path: NodePath = NodePath("../../ProfileState")
@export var backpack_panel_path: NodePath = NodePath("../../UI/BackpackPanel")
## Límites de cámara del gremio, en px locales / Guild camera limits, in local px
@export var camera_bounds: Rect2i = Rect2i(0, 0, 480, 270)

@onready var _spawn_point: Marker2D = $SpawnPoint
@onready var _ui: CanvasLayer = $GuildUI
@onready var _dialogue: Node = $GuildUI/DialogueBox
@onready var _shop: Node = $GuildUI/ShopPanel
@onready var _fence: Area2D = $Things/Fence

# Cómo volvió el jugador (death, return_stone, victory) y a quién ya se lo comentaron; vacío = nada que comentar
# How the player came back (death, return_stone, victory) and who already remarked on it; empty = nothing to say
var _mood: String = ""
var _told: Array[Node] = []


func _ready() -> void:
	$StorageChest.interacted.connect(open_storage)
	$ExpeditionDoor.interacted.connect(expedition_requested.emit)
	$NoticeBoard.interacted.connect(func() -> void: _dialogue.say(UiText.tr_or("npc.questgiver.quest.none",
			"No bounties today. That's either very good or very bad news.")))
	_fence.interacted.connect(open_shop)
	_set_hint($Things/Fence, "ui.prompt.talk", "Shop")
	_set_hint($StorageChest, "ui.prompt.open", "Storage")
	_set_hint($ExpeditionDoor, "ui.prompt.descend", "Dungeon")
	_set_hint($NoticeBoard, "ui.prompt.interact", "Board")
	for npc: Node in $Things.get_children():
		if npc != _fence and npc.has_method("greeting"):
			npc.interacted.connect(_greet.bind(npc))


func set_mood(mood: String) -> void:
	_mood = mood
	_told.clear()


func _greet(npc: Node) -> void:
	_dialogue.say(npc.call("greeting", "" if _told.has(npc) else _mood))
	_told.append(npc)


# Texto del cartel de un punto de interacción, traducido / Translated hint text of an interact spot
func _set_hint(spot: Node, key: String, fallback: String) -> void:
	var hint := spot.get_node_or_null("Hint") as Label
	if hint != null:
		hint.text = UiText.tr_or(key, "%s " + fallback) % "[F]"


func open_storage() -> void:
	var panel: Control = get_node_or_null(backpack_panel_path) as Control
	if panel != null:
		panel.call("set_open", true)


func open_shop() -> void:
	var run_manager := get_node_or_null(run_manager_path) as RunManager
	var profile := get_node_or_null(profile_state_path) as ProfileState
	if run_manager == null or profile == null:
		return
	_shop.open(run_manager, profile)


## Apagado también saca sus colisiones de la física (disable_mode REMOVE) y esconde su UI.
## Disabled also removes its collisions from physics (disable_mode REMOVE) and hides its UI.
func set_active(active: bool) -> void:
	visible = active
	process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	# process_mode no saca de la física las colisiones de un TileMapLayer, y el gremio comparte el
	# origen con la mazmorra / process_mode does not remove a TileMapLayer's collisions, and the
	# guild shares the origin with the dungeon
	$Room/Tiles.collision_enabled = active
	_ui.visible = active
	_dialogue.hide()
	$Ambience.playing = active


func spawn_position() -> Vector2:
	return _spawn_point.global_position


func camera_rect() -> Rect2i:
	return Rect2i(Vector2i(global_position) + camera_bounds.position, camera_bounds.size)
