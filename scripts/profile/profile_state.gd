class_name ProfileState
extends Node

## Persistent profile (D1): gold, permanent equipment and the equipped choice.
## Lives in `user://` and survives death, scene changes and restarts.
## Perfil persistente (D1): oro, equipo permanente y elección de arma equipada.
## Vive en `user://` y sobrevive a la muerte, al cambio de escena y a reinicios.

signal gold_changed(total: int)
signal equipment_changed(weapons: Array[WeaponData], equipped_index: int)

const SAVE_VERSION: int = 1
const PROFILE_PATH: String = "user://profile.json"
const DEFAULT_WEAPON_PATH: String = "res://resources/weapons/sword_basic.tres"

@export var profile_path: String = PROFILE_PATH

var gold: int = 0
var owned_weapons: Array[WeaponData] = []
var equipped_index: int = 0


func _ready() -> void:
	load_profile()


## Reads the profile file. A missing, unreadable, corrupt or unsupported-version
## file falls back to the default profile instead of failing boot.
## Lee el archivo. Si falta, no se puede leer, está corrupto o la versión no es
## soportada, cae al perfil por defecto en vez de romper el arranque.
func load_profile() -> void:
	if not FileAccess.file_exists(profile_path):
		_apply_defaults()
		_emit_all()
		return

	var raw: String = FileAccess.get_file_as_string(profile_path)
	# JSON.new().parse() returns an error code instead of printing an engine
	# error, so a corrupt profile is a handled path, not log noise.
	# JSON.new().parse() devuelve un código de error en vez de imprimir un error
	# del engine: un perfil corrupto es un camino manejado, no ruido de log.
	var json := JSON.new()
	if json.parse(raw) != OK or typeof(json.data) != TYPE_DICTIONARY:
		push_warning("ProfileState: unreadable profile at %s — using defaults" % profile_path)
		_apply_defaults()
		_emit_all()
		return

	var data: Dictionary = json.data
	var version: int = int(data.get("version", 0))
	if version != SAVE_VERSION:
		push_warning("ProfileState: unsupported profile version %d — using defaults" % version)
		_apply_defaults()
		_emit_all()
		return

	gold = maxi(0, int(data.get("gold", 0)))
	owned_weapons = _load_weapons(data.get("owned_weapon_paths", []))
	if owned_weapons.is_empty():
		owned_weapons.append(_default_weapon())
	equipped_index = clampi(int(data.get("equipped_index", 0)), 0, owned_weapons.size() - 1)
	_emit_all()


## Persists the profile. Returns false when the file could not be written.
## Persiste el perfil. Devuelve false si no se pudo escribir el archivo.
func save() -> bool:
	var paths: Array[String] = []
	for weapon: WeaponData in owned_weapons:
		if weapon != null and not weapon.resource_path.is_empty():
			paths.append(weapon.resource_path)

	var data: Dictionary = {
		"version": SAVE_VERSION,
		"gold": gold,
		"owned_weapon_paths": paths,
		"equipped_index": equipped_index,
	}
	var file: FileAccess = FileAccess.open(profile_path, FileAccess.WRITE)
	if file == null:
		push_error("ProfileState: cannot write %s (error %d)" % [profile_path, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(data))
	file.close()
	return true


## Banks gold immediately (current policy, S2). Rejects negative amounts.
## Bansa oro al instante (política actual, S2). Rechaza montos negativos.
func bank_gold(amount: int) -> bool:
	if amount < 0:
		return false
	if amount == 0:
		return true
	gold += amount
	gold_changed.emit(gold)
	save()
	return true


func get_gold() -> int:
	return gold


## Returns a copy so callers can never mutate the profile's array by aliasing.
## Devuelve una copia para que nadie mute el array del perfil por aliasing.
func get_owned_weapons() -> Array[WeaponData]:
	var copy: Array[WeaponData] = []
	copy.assign(owned_weapons)
	return copy


func get_equipped() -> WeaponData:
	if equipped_index < 0 or equipped_index >= owned_weapons.size():
		return null
	return owned_weapons[equipped_index]


func get_equipped_index() -> int:
	return equipped_index


## Adds permanent equipment (town purchases, D11). Duplicates are ignored.
## Agrega equipo permanente (compras del pueblo, D11). Los duplicados se ignoran.
func add_permanent_weapon(data: WeaponData) -> int:
	if data == null or data.resource_path.is_empty():
		return -1
	for index: int in owned_weapons.size():
		var owned: WeaponData = owned_weapons[index]
		if owned != null and owned.resource_path == data.resource_path:
			return index
	owned_weapons.append(data)
	equipment_changed.emit(get_owned_weapons(), equipped_index)
	save()
	return owned_weapons.size() - 1


func set_equipped(index: int) -> bool:
	if index < 0 or index >= owned_weapons.size():
		return false
	equipped_index = index
	equipment_changed.emit(get_owned_weapons(), equipped_index)
	save()
	return true


## Wipes the profile back to a fresh save. Kept for tests and a future reset UI.
## Vuelve el perfil a cero. Se mantiene para tests y un futuro reset de UI.
func reset_to_default() -> void:
	_apply_defaults()
	_emit_all()
	save()


func _apply_defaults() -> void:
	gold = 0
	owned_weapons = [_default_weapon()]
	equipped_index = 0


func _default_weapon() -> WeaponData:
	var weapon: WeaponData = load(DEFAULT_WEAPON_PATH) as WeaponData
	if weapon == null:
		push_error("ProfileState: default weapon missing at %s" % DEFAULT_WEAPON_PATH)
	return weapon


func _load_weapons(raw_paths: Variant) -> Array[WeaponData]:
	var result: Array[WeaponData] = []
	if typeof(raw_paths) != TYPE_ARRAY:
		return result
	for item: Variant in raw_paths:
		var path: String = str(item)
		if path.is_empty():
			continue
		var weapon: WeaponData = load(path) as WeaponData
		if weapon == null:
			push_warning("ProfileState: skipping unloadable weapon %s" % path)
			continue
		result.append(weapon)
	return result


func _emit_all() -> void:
	gold_changed.emit(gold)
	equipment_changed.emit(get_owned_weapons(), equipped_index)
