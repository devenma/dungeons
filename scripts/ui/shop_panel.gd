extends Control

## Tienda de un local del pueblo (D2, D25): vende lo de su ShopData (un objeto y mejoras) en oro bancado y, si
## ShopData.buys_loot (la Urraca), compra lo de la mochila por su ItemData.value. El título y las líneas de
## quien atiende salen de ShopData. Pausa el juego mientras está abierta y guarda el perfil después de cada
## trato. `interact` o `pause` la cierran. Corre con PROCESS_MODE_ALWAYS (en la escena) para recibir input
## en pausa.
## Shop of a town venue (D2, D25): sells its ShopData (an item and upgrades) in banked gold and, when
## ShopData.buys_loot (the Magpie), buys backpack items for their ItemData.value. The title and the keeper's
## lines come from ShopData. Pauses the game while open and saves the profile after every deal. `interact`
## or `pause` close it. Runs with PROCESS_MODE_ALWAYS (set in the scene) to get input while paused.

const UiText: GDScript = preload("res://scripts/ui/ui_text.gd")
## Texto de respaldo por línea mientras falte la clave / Fallback text per line while the key is missing
const LINE_FALLBACKS: Dictionary = {
	"open": "Look, don't touch. Touch it and you pay.",
	"sell": "Here's what I'll give. It isn't fair, but neither is the world.",
	"buy": "Done. No returns; not of things, not of people.",
	"no_money": "No gold, no deal. Go back down.",
	"full": "Your pack is full. Sell before you buy; I'm not your mule.",
	"upgrade": "It'll hold. Better than your skin does.",
	"capped": "That's all you can carry.",
}

## Qué vende y a qué precio; open() puede cambiarlo / What it sells and for how much; open() can change it
@export var shop_data: ShopData

var _run_manager: RunManager
var _profile: ProfileState

@onready var _title: Label = %Title
@onready var _line: Label = %Line
@onready var _gold: Label = %Gold
@onready var _buy_button: Button = %BuyButton
@onready var _upgrade_list: VBoxContainer = %UpgradeList
@onready var _sell_title: Label = %SellTitle
@onready var _sell_list: VBoxContainer = %SellList


func _ready() -> void:
	hide()
	_buy_button.pressed.connect(buy)


func _input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("interact") or event.is_action_pressed("pause")):
		close()
		get_viewport().set_input_as_handled()


func open(run_manager: RunManager, profile: ProfileState, data: ShopData = null) -> void:
	_run_manager = run_manager
	_profile = profile
	if data != null:
		shop_data = data
	_title.text = UiText.tr_or(shop_data.title_key, "The Magpie's")
	_sell_title.text = UiText.tr_or("ui.shop.sell", "Sell")
	_sell_title.visible = shop_data.buys_loot
	_sell_list.visible = shop_data.buys_loot
	_buy_button.visible = shop_data.item != null
	_say("open")
	get_tree().paused = true
	show()
	_refresh()
	if _buy_button.visible:
		_buy_button.grab_focus()
	elif _upgrade_list.get_child_count() > 0:
		(_upgrade_list.get_child(0) as Button).grab_focus()


func close() -> void:
	hide()
	get_tree().paused = false


func sell(item: ItemData) -> bool:
	if not _profile.sell(_run_manager.backpack, item):
		return false
	_profile.save_profile()
	_say("sell")
	_refresh()
	return true


func buy() -> bool:
	var item: ItemData = shop_data.item
	if item.max_carried > 0 and _run_manager.backpack.count_of(item) >= item.max_carried:
		_say("capped")
		return false
	if _profile.banked_gold < shop_data.price:
		_say("no_money")
		return false
	if not _profile.buy(_run_manager.backpack, item, shop_data.price):
		_say("full")
		return false
	_profile.save_profile()
	_say("buy")
	_refresh()
	return true


## Mejora permanente (D11): una vez, con oro bancado / Permanent upgrade (D11): once, with banked gold
func buy_upgrade(upgrade: UpgradeData) -> bool:
	if not _profile.buy_upgrade(upgrade):
		_say("no_money")
		return false
	_profile.save_profile()
	_say("upgrade")
	_refresh()
	return true


# Línea de quien atiende: <lines_prefix>.<line> / Keeper's line: <lines_prefix>.<line>
func _say(line: String) -> void:
	_line.text = UiText.tr_or("%s.%s" % [shop_data.lines_prefix, line], LINE_FALLBACKS[line])


func _price(gold: int) -> String:
	return UiText.tr_or("ui.shop.price", "%d gold") % gold


func _refresh() -> void:
	_gold.text = UiText.tr_or("ui.storage.gold_banked", "Banked gold: %d") % _profile.banked_gold
	if shop_data.item != null:
		_buy_button.text = "%s %s  -%s" % [UiText.tr_or("ui.shop.buy", "Buy"), shop_data.item.display_name(),
				_price(shop_data.price)]
	# remove_child antes de liberar: el botón que se apretó sigue en su señal / remove_child before freeing: the pressed button is still in its signal
	for child: Node in _sell_list.get_children() + _upgrade_list.get_children():
		child.get_parent().remove_child(child)
		child.queue_free()
	for upgrade: UpgradeData in shop_data.upgrades:
		if not _profile.can_offer(upgrade):
			continue
		var stat_key: String = "ui.shop.stat.health" if upgrade.stat == UpgradeData.Stat.MAX_HEALTH \
				else "ui.shop.stat.stamina"
		var upgrade_button: Button = Button.new()
		upgrade_button.text = "%s %s +%d %s  -%s" % [UiText.tr_or("ui.shop.buy", "Buy"), upgrade.display_name(),
				upgrade.amount, UiText.tr_or(stat_key, "max"), _price(upgrade.price)]
		upgrade_button.tooltip_text = tr(upgrade.desc_key)
		upgrade_button.flat = true
		upgrade_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		upgrade_button.pressed.connect(buy_upgrade.bind(upgrade))
		_upgrade_list.add_child(upgrade_button)
	if shop_data.buys_loot:
		for slot: Dictionary in _run_manager.backpack.slots:
			var item: ItemData = slot["item"]
			var count: int = slot["count"]
			var button: Button = Button.new()
			button.text = "%s x%d  +%s" % [item.display_name(), count, _price(item.value)]
			button.flat = true
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.pressed.connect(sell.bind(item))
			_sell_list.add_child(button)
	if get_viewport().gui_get_focus_owner() == null and _buy_button.visible:
		_buy_button.grab_focus()
