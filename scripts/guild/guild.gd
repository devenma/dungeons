extends "res://scripts/town/town_area.gd"

## Gremio: un área de Hondoval (D25), donde arranca el juego y adonde se vuelve. El cofre del depósito abre el
## panel de mochila y almacén, la reducidora abre la tienda, el resto de los NPC saluda y el tablón muestra una
## línea. Su portón sale a la calle; la expedición se pide desde la entrada a la cripta (Hondoval).
## Guild: a Hondoval area (D25), where the game starts and where you come back. The storage chest opens the
## backpack and storage panel, the fence opens the shop, the other NPCs greet and the notice board shows a
## line. Its gate leads to the street; the expedition is requested from the crypt entrance (Hondoval).

const UiText: GDScript = preload("res://scripts/ui/ui_text.gd")

@export var run_manager_path: NodePath = NodePath("../../../RunManager")
@export var profile_state_path: NodePath = NodePath("../../../ProfileState")
@export var backpack_panel_path: NodePath = NodePath("../../../UI/BackpackPanel")

@onready var _dialogue: Node = $GuildUI/DialogueBox
@onready var _shop: Node = $GuildUI/ShopPanel
@onready var _fence: Area2D = $Things/Fence

# Cómo volvió el jugador (death, return_stone, victory) y a quién ya se lo comentaron; vacío = nada que comentar
# How the player came back (death, return_stone, victory) and who already remarked on it; empty = nothing to say
var _mood: String = ""
var _told: Array[Node] = []


func _ready() -> void:
	$StorageChest.interacted.connect(open_storage)
	$NoticeBoard.interacted.connect(func() -> void: _dialogue.say(UiText.tr_or("npc.questgiver.quest.none",
			"No bounties today. That's either very good or very bad news.")))
	_fence.interacted.connect(open_shop)
	_set_hint($Things/Fence, "ui.prompt.talk", "Shop")
	_set_hint($StorageChest, "ui.prompt.open", "Storage")
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


## Apagado también saca sus colisiones de la física y esconde su UI (town_area); además corta el diálogo.
## Off it also takes its collisions out of physics and hides its UI (town_area); it also cuts the dialogue.
func set_active(active: bool) -> void:
	super(active)
	_dialogue.hide()
