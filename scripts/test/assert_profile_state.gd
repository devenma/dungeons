extends SceneTree

## ProfileState persistence contract: defaults, save/load roundtrip, corrupt
## file and unsupported version must never break boot.
## Contrato de persistencia de ProfileState: defaults, roundtrip save/load,
## archivo corrupto y versión no soportada nunca rompen el arranque.
## Run: godot --headless -s scripts/test/assert_profile_state.gd

const TEST_PATH := "user://test_profile_state.json"
const CORRUPT_PATH := "user://test_profile_state_corrupt.json"
const VERSION_PATH := "user://test_profile_state_version.json"
const BOW_PATH := "res://resources/weapons/bow_basic.tres"
const SWORD_PATH := "res://resources/weapons/sword_basic.tres"

var _failures: int = 0


func _initialize() -> void:
	_cleanup()
	_test_defaults()
	_test_gold_roundtrip()
	_test_equipment_roundtrip()
	_test_corrupt_file()
	_test_unsupported_version()
	_cleanup()

	if _failures == 0:
		print("PASS: ProfileState defaults, roundtrip, corrupt and version guards")
	quit(0 if _failures == 0 else 1)


## Builds a profile bound to `path` without entering the tree (`_ready` would
## load the production path). / Crea un perfil atado a `path` sin entrar al árbol.
func _new_profile(path: String) -> ProfileState:
	var profile := ProfileState.new()
	profile.profile_path = path
	profile.load_profile()
	return profile


func _test_defaults() -> void:
	var profile := _new_profile(TEST_PATH)
	_check(profile.get_gold() == 0, "default profile starts with 0 gold")
	_check(profile.get_owned_weapons().size() == 1, "default profile owns exactly one weapon")
	_check(profile.get_equipped() != null, "default profile has an equipped weapon")
	_check(profile.get_owned_weapons()[0].resource_path == SWORD_PATH,
			"default weapon is sword_basic")
	_check(not FileAccess.file_exists(TEST_PATH),
			"loading defaults does not write the profile file")
	profile.free()


func _test_gold_roundtrip() -> void:
	var profile := _new_profile(TEST_PATH)
	var emitted: Array[int] = []
	profile.gold_changed.connect(func(total: int) -> void: emitted.append(total))

	profile.bank_gold(30)
	_check(profile.get_gold() == 30, "bank_gold adds to the profile gold")
	_check(emitted == [30], "bank_gold emits gold_changed with the new total")
	_check(FileAccess.file_exists(TEST_PATH), "bank_gold persists the profile file")
	_check(not profile.bank_gold(-5), "bank_gold rejects negative amounts")
	_check(profile.get_gold() == 30, "rejected amount leaves gold untouched")
	profile.free()

	var reloaded := _new_profile(TEST_PATH)
	_check(reloaded.get_gold() == 30, "gold survives a reload")
	reloaded.free()


func _test_equipment_roundtrip() -> void:
	var profile := _new_profile(TEST_PATH)
	var bow: WeaponData = load(BOW_PATH) as WeaponData
	_check(bow != null, "bow resource loads")
	profile.add_permanent_weapon(bow)
	_check(profile.get_owned_weapons().size() == 2, "permanent weapon is added")
	_check(profile.set_equipped(1), "equip index 1 is valid")
	_check(profile.get_equipped().resource_path == BOW_PATH, "equipped weapon is the bow")
	profile.free()

	var reloaded := _new_profile(TEST_PATH)
	_check(reloaded.get_owned_weapons().size() == 2, "owned weapons survive a reload")
	_check(reloaded.get_equipped().resource_path == BOW_PATH, "equipped weapon survives a reload")
	_check(not reloaded.set_equipped(9), "out-of-range equip index is rejected")
	reloaded.free()


func _test_corrupt_file() -> void:
	var file := FileAccess.open(CORRUPT_PATH, FileAccess.WRITE)
	file.store_string("this is not json {{{")
	file.close()

	var profile := _new_profile(CORRUPT_PATH)
	_check(profile.get_gold() == 0, "corrupt file falls back to default gold")
	_check(profile.get_owned_weapons().size() == 1, "corrupt file falls back to the default weapon")
	profile.free()


func _test_unsupported_version() -> void:
	var file := FileAccess.open(VERSION_PATH, FileAccess.WRITE)
	file.store_string('{"version": 999, "gold": 99, "owned_weapon_paths": [], "equipped_index": 0}')
	file.close()

	var profile := _new_profile(VERSION_PATH)
	_check(profile.get_gold() == 0, "unsupported version falls back to default gold")
	_check(profile.get_owned_weapons().size() == 1, "unsupported version falls back to the default weapon")
	profile.free()


func _cleanup() -> void:
	for path: String in [TEST_PATH, CORRUPT_PATH, VERSION_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(cond: bool, msg: String) -> void:
	if cond:
		return
	_failures += 1
	print("FAIL: " + msg)
