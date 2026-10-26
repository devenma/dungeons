extends Control

## Panel del Altar del Voto (D23): tres ofrendas en tarjetas (carne, diezmo, piedra azul), cada una con su
## coste concreto y la vista previa de la vida; las que no se pueden usar quedan grises con el motivo. Una
## ofrenda cura toda la vida, la stamina y el maná y apaga el altar. Pausa el juego mientras está abierto.
## `move_left` / `move_right` eligen, `attack` o `interact` confirman y `pause` cancela.
## Altar of the Vow panel (D23): three offering cards (flesh, tithe, blue stone), each with its concrete
## cost and a health preview; unusable ones are greyed out with the reason. An offering restores all health
## and stamina and puts the altar out. Pauses the game while open.
## `move_left` / `move_right` pick, `attack` or `interact` confirm and `pause` cancels.

const UiText: GDScript = preload("res://scripts/ui/ui_text.gd")
# Ofrendas de carne posibles por expedición (D23) / Flesh offerings allowed per expedition (D23)
const MAX_FLESH: int = 3

enum Offering { FLESH, TITHE, STONE }

@export var run_manager_node_path: NodePath = NodePath("../../RunManager")
@export var player_node_path: NodePath = NodePath("../../World/Player")

var _altar: Node
var _run_manager: RunManager
var _health: HealthComponent
var _stamina: StaminaComponent
var _mana: StaminaComponent
# Lo que se llevaría el diezmo ahora / What the tithe would take right now
var _tithe_items: Array[ItemData] = []

@onready var _line: Label = %Line
@onready var _cards: Array[Button] = [%FleshCard, %TitheCard, %StoneCard]


func _ready() -> void:
	add_to_group("altar_panel")
	hide()
	for i in _cards.size():
		_cards[i].pressed.connect(offer.bind(i))


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause"):
		close()
	elif event.is_action_pressed("move_left") or event.is_action_pressed("move_right"):
		_step_focus(-1 if event.is_action_pressed("move_left") else 1)
	elif event.is_action_pressed("attack") or event.is_action_pressed("interact"):
		var focused: Button = get_viewport().gui_get_focus_owner() as Button
		if focused != null and _cards.has(focused) and not focused.disabled:
			offer(_cards.find(focused))
	else:
		return
	get_viewport().set_input_as_handled()


func open(altar: Node) -> void:
	_altar = altar
	_run_manager = get_node_or_null(run_manager_node_path) as RunManager
	var player: Node = get_node_or_null(player_node_path)
	_health = player.get_node_or_null("Health") as HealthComponent
	_stamina = player.get_node_or_null("Stamina") as StaminaComponent
	_mana = player.get_node_or_null("Mana") as StaminaComponent
	%Title.text = UiText.tr_or("ui.altar.title", "Altar of the Vow")
	_refresh()
	get_tree().paused = true
	show()
	for card in _cards:
		if not card.disabled:
			card.grab_focus()
			break


func close() -> void:
	hide()
	get_tree().paused = false


## Cobra la ofrenda, cura todo y apaga el altar; false si no se podía / Charges the offering, heals everything and puts the altar out; false if it was not allowed
func offer(index: int) -> bool:
	if _cards[index].disabled:
		return false
	match index:
		Offering.FLESH:
			_run_manager.offer_flesh()
		Offering.TITHE:
			for item in _tithe_items:
				_run_manager.backpack.remove(item, 1)
		Offering.STONE:
			_run_manager.consume_blue_stone()
	_health.heal_full()
	for pool: StaminaComponent in [_stamina, _mana]:
		if pool != null:
			pool.reset_full()
	_altar.call("consume")
	close()
	return true


func _refresh() -> void:
	var backpack: Inventory = _run_manager.backpack
	var tithe: int = int(_altar.call("tithe", _run_manager.current_floor))
	_tithe_items = backpack.units_by_value(tithe)
	var tithe_value: int = 0
	var tithe_names: PackedStringArray = []
	for item in _tithe_items:
		tithe_value += item.value
		tithe_names.append(item.display_name())
	var stones: int = backpack.count_of(RunManager.BLUE_STONE)
	var flesh_max: int = roundi(_health.max_health * (1.0 - 1.0 / (5.0 - _run_manager.flesh_offerings)))
	var hurt: bool = _health.current_health < _health.max_health \
			or (_stamina != null and _stamina.current_stamina < _stamina.max_stamina)
	var heal_preview: String = "%d/%d -> %d/%d" % [_health.current_health, _health.max_health,
			_health.max_health, _health.max_health]

	_set_card(Offering.FLESH, "ui.altar.flesh", "Flesh",
			UiText.tr_or("ui.altar.flesh.cost", "-20% max health until the guild") \
			+ "\n%d/%d -> %d/%d" % [_health.current_health, _health.max_health, flesh_max, flesh_max],
			"" if _run_manager.flesh_offerings < MAX_FLESH else UiText.tr_or("ui.altar.flesh.none", "Nothing left to give"))
	var tithe_cost: String = ", ".join(tithe_names)
	if tithe_value < tithe:
		tithe_cost += "\n" + UiText.tr_or("ui.altar.tithe.all", "It takes the whole pack")
	_set_card(Offering.TITHE, "ui.altar.tithe", "Tithe", tithe_cost + "\n" + heal_preview,
			"" if not _tithe_items.is_empty() else UiText.tr_or("ui.altar.tithe.empty", "The pack is empty"))
	_set_card(Offering.STONE, "ui.altar.stone", "Blue stone",
			UiText.tr_or("ui.altar.stone.cost", "Stones: %d") % stones + "\n" + heal_preview,
			"" if stones > 0 else UiText.tr_or("ui.altar.stone.none", "You have no blue stone"))

	if not hurt:
		for card in _cards:
			card.disabled = true
		_line.text = UiText.tr_or("ui.altar.not_hurt", "You need no healing.")
	elif _cards.all(func(card: Button) -> bool: return card.disabled):
		_line.text = UiText.tr_or("ui.altar.nothing", "The altar accepts nothing more.")
	else:
		_line.text = UiText.tr_or("ui.altar.line", "It heals everything. It takes something.")


## Tarjeta: nombre, coste y vista previa, o el motivo en gris / Card: name, cost and preview, or the reason greyed out
func _set_card(index: int, key: String, fallback: String, cost: String, blocked_reason: String) -> void:
	var card: Button = _cards[index]
	card.disabled = not blocked_reason.is_empty()
	card.text = UiText.tr_or(key, fallback) + "\n" + (cost if blocked_reason.is_empty() else blocked_reason)


func _step_focus(step: int) -> void:
	var focused: int = _cards.find(get_viewport().gui_get_focus_owner() as Button)
	for i in range(1, _cards.size() + 1):
		var next: Button = _cards[posmod(focused + step * i, _cards.size())]
		if not next.disabled:
			next.grab_focus()
			return
