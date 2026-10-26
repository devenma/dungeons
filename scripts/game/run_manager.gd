class_name RunManager
extends Node

## Run state owner (§6.2): everything that must survive a floor transition
## and reset on death lives here, including the backpack and its gold.
## Inventory state (RI-1) is authoritative for weapon equip; mutations
## always precede emissions (§44.16).

signal inventory_changed(weapons: Array[WeaponData])
signal weapon_equipped(data: WeaponData)
signal weapon_granted(data: WeaponData)
## Cambió el contenido o el oro de la mochila / Backpack items or gold changed
signal backpack_changed
## Botín recién agregado, para el toast / Freshly added loot, for the toast
signal loot_added(items: Array[ItemData], gold: int)
## Cambió algo que toca las estadísticas del jugador (ofrendas de carne) / Something affecting the player's stats changed (flesh offerings)
signal stats_changed

## Fallback weapon used when the scene graph does not inject one (headless
## tests instantiate run_manager.gd without main.tscn).
const DEFAULT_WEAPON_PATH: String = "res://resources/weapons/sword_basic.tres"
## Slots de la mochila / Backpack slots
const BACKPACK_SLOTS: int = 20
## Consumible que, al morir, te devuelve al gremio con el botín (D1) / Consumable that returns you to the guild with your loot on death (D1)
const BLUE_STONE: ItemData = preload("res://resources/items/blue_stone.tres")

## Arma inicial si no llegan armas base; null = DEFAULT_WEAPON_PATH / Starting weapon when no base weapons arrive; null = DEFAULT_WEAPON_PATH
@export var default_weapon: WeaponData

## Seed de la expedición; cada piso deriva la suya (§37) / Expedition seed; each floor derives its own (§37)
var run_seed: int = 0
## 0 = en el gremio, 1+ = piso actual / 0 = in the guild, 1+ = current floor
var current_floor: int = 0
## Armas de esta expedición: las del perfil + las recogidas / This expedition's weapons: the profile's + the picked-up ones
var owned_weapons: Array[WeaponData] = []
var equipped_index: int = 0
## Botín de la expedición: se pierde al morir sin piedra azul / Expedition loot: lost on death without a blue stone
var backpack: Inventory = Inventory.new(BACKPACK_SLOTS)
## Oro sin bancar que se lleva encima / Unbanked gold carried on the expedition
var backpack_gold: int = 0
## Ofrendas de carne en el altar: cada una quita el 20 % de la vida máxima hasta volver al gremio (D23)
## Flesh offerings at the altar: each takes 20% of max health until back in the guild (D23)
var flesh_offerings: int = 0


func _init() -> void:
	backpack.changed.connect(backpack_changed.emit)


## La mochila no se toca: sobrevive a la piedra azul y a volver al gremio sin depositar.
## The backpack is left alone: it survives a blue stone and returning to the guild undeposited.
func start_new_run(base_weapons: Array[WeaponData] = []) -> void:
	run_seed = randi()
	current_floor = 0
	flesh_offerings = 0
	reset_inventory(base_weapons)
	weapon_equipped.emit(get_equipped())
	stats_changed.emit()


func offer_flesh() -> void:
	flesh_offerings += 1
	stats_changed.emit()


## shortcut: lo que no entra en la mochila llena se pierde; avisar en el toast cuando haya más loot.
## shortcut: loot that does not fit a full backpack is lost; surface it in the toast once loot grows.
func add_loot(items: Array[ItemData], gold: int) -> void:
	for item in items:
		backpack.add(item)
	backpack_gold += maxi(gold, 0)
	backpack_changed.emit()
	loot_added.emit(items, gold)


func consume_blue_stone() -> bool:
	return backpack.remove(BLUE_STONE, 1)


func lose_backpack() -> void:
	backpack_gold = 0
	backpack.clear()


func take_backpack_gold() -> int:
	var gold: int = backpack_gold
	backpack_gold = 0
	backpack_changed.emit()
	return gold


## Un arma que ya está no se duplica: devuelve su índice / A weapon already owned is not duplicated: returns its index
func add_weapon(data: WeaponData) -> int:
	if data == null:
		return -1
	if owned_weapons.has(data):
		return owned_weapons.find(data)
	owned_weapons.append(data)
	inventory_changed.emit(owned_weapons)
	weapon_granted.emit(data)
	return owned_weapons.size() - 1


func equip_weapon(index: int) -> bool:
	if index < 0 or index >= owned_weapons.size():
		return false
	equipped_index = index
	weapon_equipped.emit(get_equipped())
	return true


func swap_next_weapon() -> bool:
	var next_index: int = (equipped_index + 1) % owned_weapons.size()
	return equip_weapon(next_index)


func get_equipped() -> WeaponData:
	if equipped_index < 0 or equipped_index >= owned_weapons.size():
		return null
	return owned_weapons[equipped_index]


## Sin base_weapons (perfil ausente) se arranca con el arma por defecto / Without base_weapons (no profile) start with the default weapon
func reset_inventory(base_weapons: Array[WeaponData] = []) -> void:
	var base: Array[WeaponData] = base_weapons.duplicate()
	if base.is_empty():
		var weapon_data: WeaponData = _default_data()
		if weapon_data != null:
			base.append(weapon_data)
	owned_weapons = base
	equipped_index = 0
	inventory_changed.emit(owned_weapons)


func _default_data() -> WeaponData:
	if default_weapon != null:
		return default_weapon
	return load(DEFAULT_WEAPON_PATH) as WeaponData
