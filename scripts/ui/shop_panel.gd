extends Control

## Tienda de la reducidora (D2): compra lo de la mochila por su ItemData.value y vende lo de ShopData, todo
## en oro bancado. Pausa el juego mientras está abierta y guarda el perfil después de cada trato.
## `interact` o `pause` la cierran. Corre con PROCESS_MODE_ALWAYS (en la escena) para recibir input en pausa.
## Fence shop (D2): buys backpack items for their ItemData.value and sells the ShopData item, all in banked
## gold. Pauses the game while open and saves the profile after every deal. `interact` or `pause` close it.
## Runs with PROCESS_MODE_ALWAYS (set in the scene) to get input while paused.

const UiText: GDScript = preload("res://scripts/ui/ui_text.gd")

## Qué vende y a qué precio / What it sells and for how much
@export var shop_data: ShopData

var _run_manager: RunManager
var _profile: ProfileState

@onready var _title: Label = %Title
@onready var _line: Label = %Line
@onready var _gold: Label = %Gold
@onready var _buy_button: Button = %BuyButton
@onready var _sell_title: Label = %SellTitle
@onready var _sell_list: VBoxContainer = %SellList


func _ready() -> void:
	hide()
	_buy_button.pressed.connect(buy)


func _input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("interact") or event.is_action_pressed("pause")):
		close()
		get_viewport().set_input_as_handled()


func open(run_manager: RunManager, profile: ProfileState) -> void:
	_run_manager = run_manager
	_profile = profile
	_title.text = UiText.tr_or("ui.shop.merchant_title", "The Magpie's")
	_sell_title.text = UiText.tr_or("ui.shop.sell", "Sell")
	_say("npc.merchant.shop.open", "Look, don't touch. Touch it and you pay.")
	get_tree().paused = true
	show()
	_refresh()
	_buy_button.grab_focus()


func close() -> void:
	hide()
	get_tree().paused = false


func sell(item: ItemData) -> bool:
	if not _profile.sell(_run_manager.backpack, item):
		return false
	_profile.save_profile()
	_say("npc.merchant.shop.sell", "Here's what I'll give. It isn't fair, but neither is the world.")
	_refresh()
	return true


func buy() -> bool:
	if _profile.banked_gold < shop_data.price:
		_say("npc.merchant.shop.no_money", "No gold, no deal. Go back down.")
		return false
	if not _profile.buy(_run_manager.backpack, shop_data.item, shop_data.price):
		_say("npc.merchant.shop.full", "Your pack is full. Sell before you buy; I'm not your mule.")
		return false
	_profile.save_profile()
	_say("npc.merchant.shop.buy", "Done. No returns; not of things, not of people.")
	_refresh()
	return true


func _say(key: String, fallback: String) -> void:
	_line.text = UiText.tr_or(key, fallback)


func _price(gold: int) -> String:
	return UiText.tr_or("ui.shop.price", "%d gold") % gold


func _refresh() -> void:
	_gold.text = UiText.tr_or("ui.storage.gold_banked", "Banked gold: %d") % _profile.banked_gold
	_buy_button.text = "%s %s  -%s" % [UiText.tr_or("ui.shop.buy", "Buy"), shop_data.item.display_name(),
			_price(shop_data.price)]
	# remove_child antes de liberar: el botón que se apretó sigue en su señal / remove_child before freeing: the pressed button is still in its signal
	for child: Node in _sell_list.get_children():
		_sell_list.remove_child(child)
		child.queue_free()
	for slot: Dictionary in _run_manager.backpack.slots:
		var item: ItemData = slot["item"]
		var count: int = slot["count"]
		var button: Button = Button.new()
		button.text = "%s x%d  +%s" % [item.display_name(), count, _price(item.value)]
		button.flat = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(sell.bind(item))
		_sell_list.add_child(button)
	if get_viewport().gui_get_focus_owner() == null:
		_buy_button.grab_focus()
