extends SceneTree

## ProfileState persistence assertion: save/load round trip to a temp path,
## missing file = fresh profile, corrupt file = fresh profile with the bad
## file kept as .corrupt, unknown version ignored and kept as .unsupported.
## Exit 0 = pass, 1 = fail.

const ProfileScript: GDScript = preload("res://scripts/profile/profile_state.gd")
const SAVE_PATH: String = "user://test_profile_save.json"

var _failures: int = 0


func _initialize() -> void:
	_run()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		print("FAIL: " + label)


func _cleanup() -> void:
	for path in [SAVE_PATH, SAVE_PATH + ".tmp", SAVE_PATH + ".corrupt", SAVE_PATH + ".unsupported"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _write(text: String) -> void:
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _new_profile() -> ProfileState:
	var profile: ProfileState = ProfileScript.new()
	profile.save_path = SAVE_PATH
	return profile


func _run() -> void:
	_cleanup()
	var gel: ItemData = load("res://resources/items/slime_gel.tres")
	var bow: WeaponData = load("res://resources/weapons/bow_basic.tres")

	var fresh: ProfileState = _new_profile()
	_check(not fresh.load_profile(), "missing file: load reports no save")
	_check(fresh.banked_gold == 0 and fresh.storage.is_empty(), "missing file: empty profile")
	_check(fresh.owned_weapons.size() == 1 and fresh.owned_weapons[0].weapon_name == "Basic Sword",
			"missing file: starts with the sword")

	fresh.banked_gold = 42
	fresh.storage.add(gel, 7)
	fresh.owned_weapons.append(bow)
	fresh.unlocks.append("shop")
	_check(fresh.save_profile(), "save: first write")
	fresh.banked_gold = 43
	_check(fresh.save_profile(), "save: overwrite an existing file")
	_check(not FileAccess.file_exists(SAVE_PATH + ".tmp"), "save: no leftover .tmp")

	var loaded: ProfileState = _new_profile()
	_check(loaded.load_profile(), "load: save found")
	_check(loaded.banked_gold == 43, "round trip: banked gold")
	_check(loaded.storage.count_of(gel) == 7, "round trip: storage items")
	_check(loaded.owned_weapons.size() == 2 and loaded.owned_weapons[1] == bow, "round trip: weapons")
	_check(loaded.unlocks.size() == 1 and loaded.unlocks[0] == "shop", "round trip: unlocks")
	fresh.free()
	loaded.free()

	_write("{ not json")
	var corrupt: ProfileState = _new_profile()
	_check(not corrupt.load_profile(), "corrupt file: load refused")
	_check(corrupt.banked_gold == 0 and corrupt.owned_weapons.size() == 1, "corrupt file: fresh profile")
	_check(FileAccess.file_exists(SAVE_PATH + ".corrupt"), "corrupt file: kept aside as .corrupt")
	corrupt.free()

	_write(JSON.stringify({"version": 999, "banked_gold": 500}))
	var future: ProfileState = _new_profile()
	_check(not future.load_profile() and future.banked_gold == 0, "unknown version: ignored")
	_check(FileAccess.file_exists(SAVE_PATH + ".unsupported") and not FileAccess.file_exists(SAVE_PATH),
			"unknown version: kept aside, so the next save cannot overwrite it")
	future.free()

	_write(JSON.stringify({"version": 1, "banked_gold": "lots", "storage": [], "owned_weapons": "x"}))
	var odd: ProfileState = _new_profile()
	odd.load_profile()
	_check(odd.banked_gold == 0 and odd.owned_weapons.size() == 1, "wrong field types: defaults kept")
	odd.free()

	_cleanup()
	_check(_failures == 0, "profile save: all checks passed")
	quit(0 if _failures == 0 else 1)
