class_name RunManager
extends Node

## Run state owner (§6.2): everything that must survive a floor transition
## and reset on death lives here. Inventory state (RI-1) is authoritative for
## weapon equip; mutations always precede emissions (§44.16).

signal inventory_changed(weapons: Array[WeaponData])
signal weapon_equipped(data: WeaponData)
signal weapon_granted(data: WeaponData)
signal gold_changed(total: int)

## Fallback weapon used when the scene graph does not inject one (headless
## tests instantiate run_manager.gd without main.tscn).
const DEFAULT_WEAPON_PATH: String = "res://resources/weapons/sword_basic.tres"

@export var default_weapon: WeaponData
## Path to the persistent profile. Empty in standalone headless rigs: the run
## then falls back to the default weapon (see `load_profile_equipment`).
## Path al perfil persistente. Vacío en rigs headless sueltos: la run cae al
## arma por defecto (ver `load_profile_equipment`).
@export var profile_node_path: NodePath = NodePath("")

var run_seed: int = 0
var current_floor: int = 0
var owned_weapons: Array[WeaponData] = []
var equipped_index: int = 0

var _gold_relay_connected: bool = false


func start_new_run() -> void:
	run_seed = randi()
	current_floor = 0
	load_profile_equipment()
	weapon_equipped.emit(get_equipped())


## Run inventory starts from the persistent profile (S3): permanent weapons and
## the profile's equipped choice. Chest weapons stay run-only.
## El inventario de la run arranca desde el perfil (S3): armas permanentes y la
## elección del perfil. Las armas de cofre son solo de la run.
func load_profile_equipment() -> void:
	var profile: ProfileState = _get_profile()
	if profile == null:
		reset_inventory()
		return
	_ensure_gold_relay(profile)
	owned_weapons = profile.get_owned_weapons()
	if owned_weapons.is_empty():
		var fallback: WeaponData = _default_data()
		if fallback != null:
			owned_weapons.append(fallback)
	equipped_index = clampi(profile.get_equipped_index(), 0,
			maxi(0, owned_weapons.size() - 1))
	inventory_changed.emit(owned_weapons)


func _get_profile() -> ProfileState:
	if profile_node_path.is_empty():
		return null
	return get_node_or_null(profile_node_path) as ProfileState


## Single banking seam (S2). Today gold banks immediately in the profile. To make
## gold part of the run loot later, accumulate it in this class instead, add it in
## `get_display_gold()` and drop it in `_return_to_town()`. The HUD only reads
## `get_display_gold()` / `gold_changed`, so it stays untouched.
## Único seam de banca (S2). Hoy el oro se banca al instante en el perfil. Para
## que pase a ser loot de la run, acumularlo acá, sumarlo en
## `get_display_gold()` y descartarlo en `_return_to_town()`. El HUD solo lee
## `get_display_gold()` / `gold_changed`, así que no se toca.
func add_gold(amount: int) -> bool:
	var profile: ProfileState = _get_profile()
	if profile == null:
		return false
	_ensure_gold_relay(profile)
	return profile.bank_gold(amount)


## Gold the HUD should display. / Oro que debe mostrar el HUD.
func get_display_gold() -> int:
	var profile: ProfileState = _get_profile()
	if profile == null:
		return 0
	return profile.get_gold()


func _ensure_gold_relay(profile: ProfileState) -> void:
	if _gold_relay_connected:
		return
	_gold_relay_connected = true
	profile.gold_changed.connect(_on_profile_gold_changed)


func _on_profile_gold_changed(total: int) -> void:
	gold_changed.emit(total)


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
