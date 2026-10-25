class_name ProfileState
extends Node

## Perfil persistente (§6.3, D1): oro bancado, depósito del gremio, armas y desbloqueos.
## Sobrevive a la muerte y entre sesiones (JSON en user://). No conoce el piso ni la mochila.
## La tienda del gremio cobra y paga en oro bancado (D2).
## Persistent profile (§6.3, D1): banked gold, guild storage, weapons and unlocks.
## Survives death and sessions (JSON in user://). Knows nothing about the floor or the backpack.
## The guild shop charges and pays in banked gold (D2).

signal profile_changed

## Versión del formato de guardado; otra versión se ignora / Save format version; any other is ignored
const SAVE_VERSION: int = 1
## Slots del depósito del gremio / Guild storage slots
const STORAGE_SLOTS: int = 60
## Arma inicial si el perfil no tiene ninguna (tests sin main.tscn) / Starting weapon when the profile has none (tests without main.tscn)
const DEFAULT_WEAPON_PATH: String = "res://resources/weapons/sword_basic.tres"

## Archivo de guardado / Save file
@export var save_path: String = "user://profile.json"
## Arma inicial de un perfil nuevo; null = DEFAULT_WEAPON_PATH / Starting weapon of a fresh profile; null = DEFAULT_WEAPON_PATH
@export var default_weapon: WeaponData

## Oro bancado: no se pierde al morir / Banked gold: never lost on death
var banked_gold: int = 0
## Depósito del gremio / Guild storage
var storage: Inventory = Inventory.new(STORAGE_SLOTS)
## Armas aseguradas: con estas arranca cada expedición / Secured weapons: every expedition starts with these
var owned_weapons: Array[WeaponData] = []
## Ids de desbloqueos del pueblo / Town unlock ids
var unlocks: Array[String] = []


func _ready() -> void:
	load_profile()


func reset_profile() -> void:
	banked_gold = 0
	storage.clear()
	var weapon_data: WeaponData = default_weapon if default_weapon != null \
			else load(DEFAULT_WEAPON_PATH) as WeaponData
	owned_weapons.clear()
	if weapon_data != null:
		owned_weapons.append(weapon_data)
	unlocks.clear()
	profile_changed.emit()


## Archivo ausente, corrupto o de otra versión = perfil nuevo. El corrupto se aparta como .corrupt y el
## de otra versión como .unsupported, para que el próximo guardado no los pise.
## Missing, corrupt or other-version file = fresh profile. A corrupt one is set aside as .corrupt and an
## other-version one as .unsupported, so the next save does not overwrite them.
func load_profile() -> bool:
	reset_profile()
	if not FileAccess.file_exists(save_path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not parsed is Dictionary:
		push_warning("ProfileState: corrupt save, starting fresh: " + save_path)
		DirAccess.rename_absolute(save_path, save_path + ".corrupt")
		return false
	var data: Dictionary = parsed
	if _as_int(data.get("version")) != SAVE_VERSION:
		push_warning("ProfileState: unsupported save version, starting fresh: " + save_path)
		DirAccess.rename_absolute(save_path, save_path + ".unsupported")
		return false
	banked_gold = maxi(_as_int(data.get("banked_gold")), 0)
	var storage_data: Variant = data.get("storage", {})
	if storage_data is Dictionary:
		storage.load_dict(storage_data)
	var weapon_paths: Variant = data.get("owned_weapons", [])
	if weapon_paths is Array:
		var loaded: Array[WeaponData] = []
		for path in weapon_paths:
			var weapon_path: String = str(path)
			if weapon_path.begins_with("res://") and ResourceLoader.exists(weapon_path):
				var weapon_data: WeaponData = load(weapon_path) as WeaponData
				if weapon_data != null:
					loaded.append(weapon_data)
		if not loaded.is_empty():
			owned_weapons = loaded
	var unlock_ids: Variant = data.get("unlocks", [])
	if unlock_ids is Array:
		for unlock_id in unlock_ids:
			unlocks.append(str(unlock_id))
	profile_changed.emit()
	return true


## Escribe a un .tmp y renombra, para no dejar un guardado a medias / Writes a .tmp then renames, so a save is never half-written
func save_profile() -> bool:
	var weapon_paths: Array[String] = []
	for weapon_data in owned_weapons:
		weapon_paths.append(weapon_data.resource_path)
	var data: Dictionary = {
		"version": SAVE_VERSION,
		"banked_gold": banked_gold,
		"storage": storage.to_dict(),
		"owned_weapons": weapon_paths,
		"unlocks": unlocks,
	}
	var tmp_path: String = save_path + ".tmp"
	var file: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("ProfileState: cannot write " + tmp_path)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	if DirAccess.rename_absolute(tmp_path, save_path) != OK:
		push_error("ProfileState: cannot replace " + save_path)
		return false
	return true


## Pasa la mochila al depósito y banca el oro; lo que no entra queda en la mochila.
## Moves the backpack into storage and banks the gold; whatever does not fit stays in the backpack.
func deposit(backpack: Inventory, gold: int) -> void:
	banked_gold += maxi(gold, 0)
	backpack.move_all_to(storage)
	profile_changed.emit()


## Vende una unidad de la mochila por su ItemData.value y banca el oro / Sells one backpack unit for its ItemData.value and banks the gold
func sell(backpack: Inventory, item: ItemData) -> bool:
	if not backpack.remove(item, 1):
		return false
	banked_gold += maxi(item.value, 0)
	profile_changed.emit()
	return true


## Compra una unidad con oro bancado; sin oro o con la mochila llena no cobra nada.
## Buys one unit with banked gold; when broke or with a full backpack nothing is charged.
func buy(backpack: Inventory, item: ItemData, price: int) -> bool:
	if banked_gold < price or backpack.add(item, 1) > 0:
		return false
	banked_gold -= price
	profile_changed.emit()
	return true


func _as_int(value: Variant) -> int:
	return int(value) if value is int or value is float else 0
