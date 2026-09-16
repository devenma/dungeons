class_name RunManager
extends Node

## Run state owner (§6.2): everything that must survive a floor transition
## and reset on death lives here. Inventory state (RI-1) is authoritative for
## weapon equip; mutations always precede emissions (§44.16).

signal inventory_changed(weapons: Array[WeaponData])
signal weapon_equipped(data: WeaponData)
signal weapon_granted(data: WeaponData)

## Fallback weapon used when the scene graph does not inject one (headless
## tests instantiate run_manager.gd without main.tscn).
const DEFAULT_WEAPON_PATH: String = "res://resources/weapons/sword_basic.tres"

@export var default_weapon: WeaponData

var run_seed: int = 0
var current_floor: int = 0
var owned_weapons: Array[WeaponData] = []
var equipped_index: int = 0


func start_new_run() -> void:
	run_seed = randi()
	current_floor = 0
	reset_inventory()
	weapon_equipped.emit(get_equipped())


func add_weapon(data: WeaponData) -> int:
	if data == null:
		return -1
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


func reset_inventory() -> void:
	var weapon_data: WeaponData = _default_data()
	var base: Array[WeaponData] = []
	if weapon_data != null:
		base.append(weapon_data)
	owned_weapons = base
	equipped_index = 0
	inventory_changed.emit(owned_weapons)


func _default_data() -> WeaponData:
	if default_weapon != null:
		return default_weapon
	return load(DEFAULT_WEAPON_PATH) as WeaponData
